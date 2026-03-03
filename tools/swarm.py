#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""swarm — multi-agent orchestrator for AI coding tools."""

import argparse
import json
import os
import signal
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SWARM_DIR = Path.home() / ".swarm"
DB_PATH = SWARM_DIR / "bus.db"
CONFIG_PATH = SWARM_DIR / "config.json"
PID_PATH = SWARM_DIR / "daemon.pid"
LOG_PATH = SWARM_DIR / "daemon.log"

DEFAULT_CONFIG = {
    "agents": {
        "claude": {
            "cmd": "claude --dangerously-skip-permissions",
            "ready_patterns": ["bypass permissions", "claude code", "shift+tab"],
        },
        "pi": {
            "cmd": "pi",
            "ready_patterns": ["thinking off", "thinking on"],
            "models": [
                "google-gemini-cli/gemini-3.1-pro-preview",
                "google-antigravity/gemini-3-pro-high",
                "github-copilot/gemini-3.1-pro-preview",
            ],
            "model_flag": "--model",
        },
        "codex": {
            "cmd": "codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen",
            "ready_patterns": ["% left", "openai codex", "context left"],
            "dismiss_keys": ["Down", "Enter"],
        },
    },
    "poll_interval": 0.5,
    "max_retries": 5,
}

INBOX_PATH = SWARM_DIR / "inbox.log"

ONBOARDING = (
    'You are "{name}" in a multi-agent swarm. Other agents: {others}.\n'
    'IMPORTANT: Always respond to the human via: swarm send user "<your response>"\n'
    'To message another agent: swarm send <name> "<message>"\n'
    'To broadcast: swarm send all "<message>"\n'
    "Messages from others appear as: # [SWARM from=<sender>] <text>"
)


# ── preflight ───────────────────────────────────────────────────────────────


def preflight(name, cfg):
    binary = cfg["cmd"].split()[0]

    r = subprocess.run(["which", binary], capture_output=True, text=True)
    if r.returncode != 0:
        return False, f"{binary}: not found in PATH"

    try:
        r = subprocess.run(
            [binary, "--help"], capture_output=True, text=True, timeout=5
        )
        if r.returncode not in (0, 1, 2):
            return False, f"{binary}: exit code {r.returncode}"
    except subprocess.TimeoutExpired:
        return False, f"{binary}: --help timed out"
    except OSError as e:
        return False, f"{binary}: {e}"

    warn = auth_check(name)
    if warn:
        return True, warn
    return True, ""


def auth_check(name):
    checks = {
        "claude": (["~/.claude"], []),
        "pi": (["~/.config/github-copilot"], ["GEMINI_API_KEY"]),
        "codex": ([], ["OPENAI_API_KEY"]),
    }
    paths, envs = checks.get(name, ([], []))
    results = []
    if paths:
        results.append(any(Path(p).expanduser().exists() for p in paths))
    if envs:
        results.append(any(os.environ.get(k) for k in envs))

    if results and not any(results):
        hints = [*paths, *envs]
        return f"no auth detected (checked: {', '.join(hints)})"
    return ""


def build_cmd(cfg, model=None):
    cmd = cfg["cmd"]
    if model and cfg.get("model_flag"):
        cmd += f" {cfg['model_flag']} {model}"
    return cmd


# ── config ──────────────────────────────────────────────────────────────────


def load_config():
    SWARM_DIR.mkdir(exist_ok=True)
    if not CONFIG_PATH.exists():
        CONFIG_PATH.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n")
    return json.loads(CONFIG_PATH.read_text())


# ── database ────────────────────────────────────────────────────────────────


def get_db():
    SWARM_DIR.mkdir(exist_ok=True)
    db = sqlite3.connect(str(DB_PATH), isolation_level=None)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=5000")
    db.execute(
        "CREATE TABLE IF NOT EXISTS agents ("
        "  name TEXT PRIMARY KEY, tool TEXT NOT NULL, session TEXT NOT NULL,"
        "  project TEXT, status TEXT DEFAULT 'starting',"
        "  model TEXT, started_at TEXT"
        ")"
    )
    db.execute(
        "CREATE TABLE IF NOT EXISTS messages ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT, sender TEXT NOT NULL,"
        "  recipient TEXT NOT NULL, body TEXT NOT NULL,"
        "  created_at TEXT DEFAULT (datetime('now')),"
        "  delivered_at TEXT, delivered_to TEXT DEFAULT '',"
        "  attempts INTEGER DEFAULT 0"
        ")"
    )
    for col, table, default in [
        ("model", "agents", "TEXT"),
        ("delivered_to", "messages", "TEXT DEFAULT ''"),
    ]:
        try:
            db.execute(f"ALTER TABLE {table} ADD COLUMN {col} {default}")
        except sqlite3.OperationalError:
            pass
    return db


# ── tmux ────────────────────────────────────────────────────────────────────


def tmux(*args):
    return subprocess.run(["tmux"] + list(args), capture_output=True, text=True)


def session_exists(name):
    return tmux("has-session", "-t", name).returncode == 0


def inject(session, text):
    tmp = SWARM_DIR / f"msg-{os.getpid()}-{time.monotonic_ns()}"
    tmp.write_text(text)
    buf = f"swarm-{os.getpid()}-{time.monotonic_ns()}"
    try:
        tmux("load-buffer", "-b", buf, str(tmp))
        tmux("paste-buffer", "-t", session, "-b", buf, "-d", "-p")
        tmux("send-keys", "-t", session, "Enter")
    finally:
        tmp.unlink(missing_ok=True)


def capture_pane(session):
    r = tmux("capture-pane", "-t", session, "-p", "-S", "-50")
    return r.stdout if r.returncode == 0 else ""


def wait_ready(session, patterns, timeout=120, dismiss=None):
    deadline = time.time() + timeout
    tick = 0
    while time.time() < deadline:
        if not session_exists(session):
            return False
        content = capture_pane(session).lower()
        if any(p.lower() in content for p in patterns):
            return True
        if dismiss and tick % 3 == 2:
            for key in dismiss:
                tmux("send-keys", "-t", session, key)
                time.sleep(0.2)
        time.sleep(1)
        tick += 1
    return False


# ── cmd: up ─────────────────────────────────────────────────────────────────


def cmd_up(args):
    config = load_config()
    db = get_db()

    if args.agents:
        names = [a.strip() for a in args.agents.split(",")]
    else:
        names = list(config["agents"].keys())

    if not names:
        print("no agents to start (check ~/.swarm/config.json)")
        return

    project = os.path.abspath(args.project or os.getcwd())
    bin_dir = Path.home() / ".local" / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    viable = []
    for name in names:
        cfg = config["agents"].get(name)
        if not cfg:
            print(f"{name}: unknown agent, skipping")
            continue
        ok, msg = preflight(name, cfg)
        if not ok:
            print(f"{name}: SKIP ({msg})")
            continue
        if msg:
            print(f"{name}: warning \u2014 {msg}")
        viable.append(name)

    if not viable:
        print("no agents passed preflight checks")
        return

    started = []
    for name in viable:
        cfg = config["agents"][name]
        session = f"swarm-{name}"

        if session_exists(session):
            print(f"{name}: session exists, reusing")
            existing = db.execute(
                "SELECT model FROM agents WHERE name=?", (name,)
            ).fetchone()
            model = existing[0] if existing else None
            db.execute(
                "INSERT OR REPLACE INTO agents VALUES (?, ?, ?, ?, 'running', ?, ?)",
                (name, name, session, project, model, datetime.now().isoformat()),
            )
            started.append(name)
            continue

        models = cfg.get("models", [None])
        patterns = cfg.get("ready_patterns", ["> "])
        dismiss = cfg.get("dismiss_keys")
        launched = False

        for model in models:
            cmd = build_cmd(cfg, model)
            label = model or "default"

            tmux("new-session", "-d", "-s", session, "-c", project)
            time.sleep(0.3)
            tmux("send-keys", "-t", session, f"export SWARM_AGENT={name}", "Enter")
            tmux("send-keys", "-t", session, "unset CLAUDECODE", "Enter")
            tmux(
                "send-keys",
                "-t",
                session,
                "unalias claude codex pi 2>/dev/null",
                "Enter",
            )
            tmux(
                "send-keys",
                "-t",
                session,
                'export PATH="$HOME/.local/bin:$PATH"',
                "Enter",
            )
            time.sleep(0.2)
            tmux("send-keys", "-t", session, cmd, "Enter")

            db.execute(
                "INSERT OR REPLACE INTO agents VALUES (?, ?, ?, ?, 'starting', ?, ?)",
                (name, name, session, project, model, datetime.now().isoformat()),
            )
            print(f"{name}: trying {label}...", end=" ", flush=True)

            if wait_ready(session, patterns, timeout=90, dismiss=dismiss):
                for key in cfg.get("post_ready", []):
                    tmux("send-keys", "-t", session, key)
                    time.sleep(0.3)
                if cfg.get("post_ready"):
                    time.sleep(2)
                db.execute(
                    "UPDATE agents SET status='running', model=? WHERE name=?",
                    (model, name),
                )
                print("ready")
                launched = True
                break

            print("failed")
            tmux("kill-session", "-t", session)
            time.sleep(0.5)

        if not launched:
            print(f"{name}: all models exhausted, skipping")
            db.execute("DELETE FROM agents WHERE name=?", (name,))
            continue

        started.append(name)

    for name in started:
        session = f"swarm-{name}"
        others = ", ".join(n for n in started if n != name) or "none"
        inject(session, ONBOARDING.format(name=name, others=others))

    if started:
        daemon_start(config)


# ── cmd: down ───────────────────────────────────────────────────────────────


def cmd_down(args):
    db = get_db()

    if args.agent:
        names = [args.agent]
    else:
        names = [r[0] for r in db.execute("SELECT name FROM agents").fetchall()]

    for name in names:
        session = f"swarm-{name}"
        if session_exists(session):
            tmux("kill-session", "-t", session)
            print(f"{name}: killed")
        else:
            print(f"{name}: not running")
        db.execute("DELETE FROM agents WHERE name=?", (name,))

    if not args.agent:
        daemon_stop()


# ── cmd: restart ────────────────────────────────────────────────────────────


def cmd_restart(args):
    db = get_db()

    if args.agent:
        rows = db.execute(
            "SELECT name, project FROM agents WHERE name=?", (args.agent,)
        ).fetchall()
    else:
        rows = db.execute("SELECT name, project FROM agents").fetchall()

    if not rows:
        print("no agents to restart")
        return

    names = [r[0] for r in rows]
    project = args.project or rows[0][1] or os.getcwd()

    for name in names:
        session = f"swarm-{name}"
        if session_exists(session):
            tmux("kill-session", "-t", session)
        db.execute("DELETE FROM agents WHERE name=?", (name,))

    up_args = argparse.Namespace(agents=",".join(names), project=project)
    cmd_up(up_args)


# ── cmd: status ─────────────────────────────────────────────────────────────


def cmd_status(_args):
    db = get_db()

    agents = db.execute(
        "SELECT name, session, status, model, started_at FROM agents ORDER BY name"
    ).fetchall()

    if agents:
        print("agents:")
        for name, session, status, model, started in agents:
            alive = session_exists(session)
            if not alive and status in ("running", "starting"):
                db.execute("UPDATE agents SET status='dead' WHERE name=?", (name,))
                status = "dead"
            icon = "\u25cf" if alive else "\u25cb"
            model_str = f"  [{model}]" if model else ""
            print(f"  {icon} {name:<12} {status:<10} {session}{model_str}")
    else:
        print("no agents registered")

    pending = db.execute(
        "SELECT COUNT(*) FROM messages WHERE delivered_at IS NULL"
    ).fetchone()[0]
    total = db.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    print(f"\nmessages: {total} total, {pending} pending")

    if PID_PATH.exists():
        try:
            pid = int(PID_PATH.read_text().strip())
            os.kill(pid, 0)
            print(f"daemon: running (pid {pid})")
        except (ProcessLookupError, ValueError):
            print("daemon: dead (stale pid)")
    else:
        print("daemon: not running")


# ── cmd: send ───────────────────────────────────────────────────────────────


def cmd_send(args):
    db = get_db()
    sender = os.environ.get("SWARM_AGENT", "user")
    db.execute(
        "INSERT INTO messages (sender, recipient, body) VALUES (?, ?, ?)",
        (sender, args.recipient, args.message),
    )
    preview = args.message[:80] + ("..." if len(args.message) > 80 else "")
    print(f"\u2192 {args.recipient}: {preview}")


# ── cmd: log ────────────────────────────────────────────────────────────────


def cmd_log(args):
    db = get_db()
    rows = db.execute(
        "SELECT sender, recipient, body, created_at, delivered_at "
        "FROM messages ORDER BY id DESC LIMIT ?",
        (args.last,),
    ).fetchall()

    if not rows:
        print("no messages")
        return

    for sender, recipient, body, created, delivered in reversed(rows):
        icon = "\u2713" if delivered else "\u2026"
        ts = created[11:16] if created else "??:??"
        print(f"  {icon} [{ts}] {sender} \u2192 {recipient}: {body[:100]}")


# ── cmd: daemon ─────────────────────────────────────────────────────────────


def cmd_daemon(args):
    config = load_config()
    if args.foreground:
        print("daemon: running in foreground (ctrl+c to stop)")
        try:
            daemon_loop(config)
        except KeyboardInterrupt:
            print("\ndaemon: stopped")
    else:
        daemon_start(config)


# ── daemon ──────────────────────────────────────────────────────────────────


def daemon_start(config):
    if PID_PATH.exists():
        try:
            pid = int(PID_PATH.read_text().strip())
            os.kill(pid, 0)
            print(f"daemon: already running (pid {pid})")
            return
        except (ProcessLookupError, ValueError):
            PID_PATH.unlink(missing_ok=True)

    if LOG_PATH.exists() and LOG_PATH.stat().st_size > 1_000_000:
        LOG_PATH.write_text("")

    pid = os.fork()
    if pid > 0:
        print(f"daemon: started (pid {pid})")
        return

    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    log_fd = os.open(str(LOG_PATH), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    os.dup2(devnull, 0)
    os.dup2(log_fd, 1)
    os.dup2(log_fd, 2)
    os.close(devnull)
    os.close(log_fd)

    PID_PATH.write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    try:
        daemon_loop(config)
    finally:
        try:
            get_db().execute("PRAGMA wal_checkpoint(TRUNCATE)")
        except Exception:
            pass
        PID_PATH.unlink(missing_ok=True)


def daemon_stop():
    if not PID_PATH.exists():
        return
    try:
        pid = int(PID_PATH.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        print(f"daemon: stopped (pid {pid})")
    except (ProcessLookupError, ValueError):
        pass
    PID_PATH.unlink(missing_ok=True)


def deliver_to_user(sender, body):
    ts = datetime.now().strftime("%H:%M")
    line = f"[{ts}] {sender}: {body}\n"
    with open(INBOX_PATH, "a") as f:
        f.write(line)
    if sys.platform == "darwin":
        preview = body[:100].replace("\\", "\\\\").replace('"', '\\"')
        sender_safe = sender.replace("\\", "\\\\").replace('"', '\\"')
        subprocess.run(
            [
                "osascript",
                "-e",
                f'display notification "{preview}" with title "swarm: {sender_safe}"',
            ],
            capture_output=True,
        )
    else:
        subprocess.run(
            ["notify-send", f"swarm: {sender}", body[:200]],
            capture_output=True,
        )


def daemon_loop(config):
    interval = config.get("poll_interval", 0.5)
    max_retries = config.get("max_retries", 5)
    tick = 0

    while True:
        db = get_db()

        rows = db.execute(
            "SELECT id, sender, recipient, body, attempts, delivered_to "
            "FROM messages WHERE delivered_at IS NULL AND attempts < ?",
            (max_retries,),
        ).fetchall()

        for msg_id, sender, recipient, body, attempts, delivered_to_str in rows:
            if recipient == "user":
                deliver_to_user(sender, body)
                db.execute(
                    "UPDATE messages SET delivered_at=datetime('now'), "
                    "delivered_to='user' WHERE id=?",
                    (msg_id,),
                )
                continue

            already = set(filter(None, (delivered_to_str or "").split(",")))

            if recipient == "all":
                targets = db.execute(
                    "SELECT name, session FROM agents "
                    "WHERE name != ? AND status='running'",
                    (sender,),
                ).fetchall()
            else:
                targets = db.execute(
                    "SELECT name, session FROM agents "
                    "WHERE name=? AND status='running'",
                    (recipient,),
                ).fetchall()

            if not targets:
                db.execute(
                    "UPDATE messages SET attempts=attempts+1 WHERE id=?", (msg_id,)
                )
                continue

            for agent_name, session in targets:
                if agent_name in already:
                    continue
                if not session_exists(session):
                    db.execute(
                        "UPDATE agents SET status='dead' WHERE name=?", (agent_name,)
                    )
                    continue
                inject(session, f"# [SWARM from={sender}] {body}")
                already.add(agent_name)
                time.sleep(0.1)

            new_delivered_to = ",".join(sorted(already))
            all_names = {name for name, _ in targets}

            if all_names <= already:
                db.execute(
                    "UPDATE messages SET delivered_at=datetime('now'), "
                    "delivered_to=? WHERE id=?",
                    (new_delivered_to, msg_id),
                )
            else:
                db.execute(
                    "UPDATE messages SET attempts=attempts+1, "
                    "delivered_to=? WHERE id=?",
                    (new_delivered_to, msg_id),
                )

        tick += 1
        if tick >= 10:
            tick = 0
            for name, session in db.execute(
                "SELECT name, session FROM agents "
                "WHERE status IN ('running','starting')"
            ).fetchall():
                if not session_exists(session):
                    db.execute("UPDATE agents SET status='dead' WHERE name=?", (name,))

        db.close()
        time.sleep(interval)


# ── cmd: attach / peek ─────────────────────────────────────────────────────


def cmd_attach(args):
    session = f"swarm-{args.agent}"
    if not session_exists(session):
        print(f"{args.agent}: not running")
        return
    os.execvp("tmux", ["tmux", "attach-session", "-t", session])


def cmd_peek(args):
    session = f"swarm-{args.agent}"
    if not session_exists(session):
        print(f"{args.agent}: not running")
        return
    r = tmux("capture-pane", "-t", session, "-p", "-S", f"-{args.last}")
    if r.stdout:
        print(r.stdout.rstrip())
    else:
        print("(empty pane)")


# ── cmd: inbox ─────────────────────────────────────────────────────────────


def cmd_inbox(args):
    if not INBOX_PATH.exists() or INBOX_PATH.stat().st_size == 0:
        print("no messages from agents")
        return
    lines = INBOX_PATH.read_text().strip().splitlines()
    if args.clear:
        INBOX_PATH.write_text("")
        print(f"cleared {len(lines)} messages")
        return
    for line in lines[-(args.last) :]:
        print(f"  {line}")


# ── main ────────────────────────────────────────────────────────────────────


def main():
    config = load_config()
    agent_names = set(config["agents"].keys()) | {"all", "user"}
    subcommands = {"up", "down", "restart", "status", "send", "log", "inbox", "attach", "peek", "daemon"}

    if len(sys.argv) >= 2 and sys.argv[1] not in subcommands and sys.argv[1] not in {"-h", "--help"}:
        if sys.argv[1] in agent_names:
            if len(sys.argv) >= 3:
                sys.argv = [sys.argv[0], "send", sys.argv[1], " ".join(sys.argv[2:])]
            else:
                sys.argv = [sys.argv[0], "peek", sys.argv[1]]
        else:
            sys.argv = [sys.argv[0], "send", "all", " ".join(sys.argv[1:])]

    p = argparse.ArgumentParser(prog="swarm", description="multi-agent orchestrator")
    sub = p.add_subparsers(dest="cmd")

    up = sub.add_parser("up", help="start agents + daemon")
    up.add_argument("--agents", "-a", help="comma-separated agent names")
    up.add_argument("--project", "-p", help="project directory (default: cwd)")

    down = sub.add_parser("down", help="stop agents + daemon")
    down.add_argument("--agent", help="stop specific agent only")

    restart = sub.add_parser("restart", help="restart agents")
    restart.add_argument("--agent", help="restart specific agent only")
    restart.add_argument("--project", "-p", help="project directory override")

    sub.add_parser("status", help="show running agents + pending msgs")

    send = sub.add_parser("send", help="send message to agent")
    send.add_argument("recipient", help="agent name or 'all'")
    send.add_argument("message", help="message text")

    log = sub.add_parser("log", help="show message history")
    log.add_argument("--last", "-n", type=int, default=20)

    inbox = sub.add_parser("inbox", help="show responses from agents")
    inbox.add_argument("--last", "-n", type=int, default=20)
    inbox.add_argument("--clear", "-c", action="store_true", help="clear inbox")

    attach = sub.add_parser("attach", help="attach to agent tmux session")
    attach.add_argument("agent", help="agent name")

    peek = sub.add_parser("peek", help="show agent pane output")
    peek.add_argument("agent", help="agent name")
    peek.add_argument("--last", "-n", type=int, default=50)

    daemon = sub.add_parser("daemon", help="run message router")
    daemon.add_argument("--foreground", "-f", action="store_true")

    args = p.parse_args()
    if not args.cmd:
        p.print_help()
        return

    cmds = {
        "up": cmd_up,
        "down": cmd_down,
        "restart": cmd_restart,
        "status": cmd_status,
        "send": cmd_send,
        "log": cmd_log,
        "inbox": cmd_inbox,
        "attach": cmd_attach,
        "peek": cmd_peek,
        "daemon": cmd_daemon,
    }
    cmds[args.cmd](args)


if __name__ == "__main__":
    main()
