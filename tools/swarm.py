#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""swarm — multi-agent orchestrator for AI coding tools."""

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import tomllib
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
            "cmd": "pi --thinking high --tools read,bash,edit,write,grep,find,ls",
            "ready_patterns": [
                "thinking off",
                "thinking on",
                "thinking high",
                "thinking:",
            ],
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

DEFAULT_GO_AGENTS = "claude,codex,pi"

DOCTOR_LIMIT_MIN = {
    "agent.max_turns": 500,
    "agent.max_retries": 25,
    "agents.max_threads": 64,
    "agents.max_depth": 32,
    "agents.job_max_runtime_seconds": 172800,
    "tool_output_token_limit": 250000,
    "history.persistence": "save-all",
    "history.max_bytes": 52428800,
    "project_doc_max_bytes": 1048576,
    "mcp_servers.codex_apps.tool_timeout_sec": 1800,
    "features.multi_agent": True,
    "features.memories": True,
    "features.sqlite": True,
}


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


ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def strip_ansi(text):
    if not text:
        return ""
    return ANSI_RE.sub("", text).replace("\r", "")


def _last_pct(pattern, text):
    matches = re.findall(pattern, text, flags=re.IGNORECASE)
    if not matches:
        return None
    raw = matches[-1]
    if isinstance(raw, tuple):
        raw = next((x for x in raw if x), None)
    if raw is None:
        return None
    try:
        val = float(raw)
    except ValueError:
        return None
    if val < 0:
        return None
    if val > 100:
        val = 100
    return int(round(val))


def parse_runtime_metrics(pane_text):
    text = strip_ansi(pane_text)
    lower = text.lower()
    five_hour_left = None
    context_left = None

    for line in lower.splitlines():
        five_h = re.search(r"5\s*h(?:our)?s?", line)
        if five_h:
            pct = None
            after = line[five_h.end() : five_h.end() + 48]
            before = line[max(0, five_h.start() - 48) : five_h.start()]

            m_after = re.search(r"(\d{1,3}(?:\.\d+)?)\s*%", after)
            if m_after:
                prefix = after[: m_after.start()]
                if "context" not in prefix:
                    try:
                        pct = int(round(float(m_after.group(1))))
                    except ValueError:
                        pct = None

            if pct is None:
                m_before = re.search(r"(\d{1,3}(?:\.\d+)?)\s*%", before)
                if m_before:
                    suffix = before[m_before.end() :]
                    if re.search(r"(left|remaining|quota|usage)", suffix):
                        try:
                            pct = int(round(float(m_before.group(1))))
                        except ValueError:
                            pct = None

            if pct is not None:
                if pct < 0:
                    pct = 0
                if pct > 100:
                    pct = 100
                five_hour_left = pct
        if "context" in line:
            pct = _last_pct(
                r"(?:context(?:\s+window)?[^0-9%]{0,20})(\d{1,3}(?:\.\d+)?)\s*%",
                line,
            )
            if pct is None:
                pct = _last_pct(
                    r"(\d{1,3}(?:\.\d+)?)\s*%[^%\n]{0,20}(?:context(?:\s+window)?)",
                    line,
                )
            if pct is not None:
                context_left = pct

    if five_hour_left is None:
        # Fallback only when we couldn't find a dedicated 5h line.
        five_hour_left = _last_pct(
            r"(\d{1,3}(?:\.\d+)?)\s*%\s*(?:left|remaining)[^\n]{0,24}(?:5\s*h(?:our)?s?)",
            lower,
        )

    if context_left is None:
        context_left = _last_pct(
            r"(?:context(?:\s+window)?\s*left[^0-9]{0,24})(\d{1,3}(?:\.\d+)?)\s*%",
            lower,
        )
    if context_left is None:
        # Generic fallback for agents that only print "% left" without a context label.
        context_left = _last_pct(r"(\d{1,3}(?:\.\d+)?)\s*%\s*left", lower)

    return {
        "context_left": context_left,
        "five_hour_left": five_hour_left,
    }


def process_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def collect_status_snapshot():
    db = get_db()
    try:
        config = load_config()
        max_retries = config.get("max_retries", 5)
        agent_rows = db.execute(
            "SELECT name, session, status, model, started_at FROM agents ORDER BY name"
        ).fetchall()

        agents = []
        for name, session, status, model, started in agent_rows:
            alive = session_exists(session)
            if not alive and status in ("running", "starting"):
                db.execute("UPDATE agents SET status='dead' WHERE name=?", (name,))
                status = "dead"
            metrics = {"context_left": None, "five_hour_left": None}
            if alive:
                metrics = parse_runtime_metrics(capture_pane(session))
            agents.append(
                {
                    "name": name,
                    "session": session,
                    "status": status,
                    "model": model,
                    "started_at": started,
                    "alive": alive,
                    "metrics": metrics,
                }
            )

        pending = db.execute(
            "SELECT COUNT(*) FROM messages WHERE delivered_at IS NULL AND attempts < ?",
            (max_retries,),
        ).fetchone()[0]
        failed = db.execute(
            "SELECT COUNT(*) FROM messages WHERE delivered_at IS NULL AND attempts >= ?",
            (max_retries,),
        ).fetchone()[0]
        total = db.execute("SELECT COUNT(*) FROM messages").fetchone()[0]

        pid = daemon_pid()
        daemon = {"pid": pid, "running": False, "stale": False}
        if pid is None:
            daemon["state"] = "not running"
        elif process_alive(pid):
            daemon["running"] = True
            daemon["state"] = f"running (pid {pid})"
        else:
            daemon["stale"] = True
            daemon["state"] = "dead (stale pid)"

        active = sum(
            1 for a in agents if a["alive"] and a["status"] in {"running", "starting"}
        )

        return {
            "agents": agents,
            "active_agents": active,
            "queue": {"total": total, "pending": pending, "failed": failed},
            "daemon": daemon,
        }
    finally:
        db.close()


def _fmt_pct(value):
    return f"{value}%" if value is not None else "-"


def render_watch(snapshot):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        f"swarm watch  [{now}]",
        f"daemon: {snapshot['daemon']['state']}",
        f"agents: {snapshot['active_agents']} active / {len(snapshot['agents'])} registered",
        (
            "queue: "
            f"{snapshot['queue']['pending']} pending | "
            f"{snapshot['queue']['failed']} failed | "
            f"{snapshot['queue']['total']} total"
        ),
        "",
    ]

    if snapshot["agents"]:
        lines.append("  name         status      ctx-left  5h-left   session")
        for a in snapshot["agents"]:
            icon = "\u25cf" if a["alive"] else "\u25cb"
            ctx = _fmt_pct(a["metrics"]["context_left"])
            five = _fmt_pct(a["metrics"]["five_hour_left"])
            lines.append(
                f"  {icon} {a['name']:<10} {a['status']:<10} {ctx:<8} {five:<8} {a['session']}"
            )
    else:
        lines.append("  no agents registered")

    return "\n".join(lines)


def _nested_get(data, dotted_key):
    cur = data
    for part in dotted_key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


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
        # Ensure we don't fork with an active SQLite handle.
        db.close()
        daemon_start(config)
    else:
        db.close()


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
    snapshot = collect_status_snapshot()
    agents = snapshot["agents"]

    if agents:
        print("agents:")
        for a in agents:
            icon = "\u25cf" if a["alive"] else "\u25cb"
            model_str = f"  [{a['model']}]" if a["model"] else ""
            metrics_str = ""
            metric_parts = []
            if a["metrics"]["context_left"] is not None:
                metric_parts.append(f"ctx {a['metrics']['context_left']}% left")
            if a["metrics"]["five_hour_left"] is not None:
                metric_parts.append(f"5h {a['metrics']['five_hour_left']}% left")
            if metric_parts:
                metrics_str = "  |  " + "  |  ".join(metric_parts)
            print(
                f"  {icon} {a['name']:<12} {a['status']:<10} {a['session']}{model_str}{metrics_str}"
            )
    else:
        print("no agents registered")

    pending = snapshot["queue"]["pending"]
    failed = snapshot["queue"]["failed"]
    total = snapshot["queue"]["total"]
    print(f"\nmessages: {total} total, {pending} pending, {failed} failed")

    daemon = snapshot["daemon"]
    if daemon["running"]:
        print(f"daemon: running (pid {daemon['pid']})")
    elif daemon["stale"]:
        print("daemon: dead (stale pid)")
    else:
        print("daemon: not running")


# ── cmd: watch ──────────────────────────────────────────────────────────────


def cmd_watch(args):
    try:
        while True:
            snapshot = collect_status_snapshot()
            if not args.no_clear:
                print("\033[2J\033[H", end="")
            print(render_watch(snapshot))
            if args.once:
                return
            print(f"\nrefresh: {args.interval:.1f}s  (ctrl+c to stop)")
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nwatch: stopped")


# ── cmd: doctor ─────────────────────────────────────────────────────────────


def _doctor_check_macos_permissions():
    checks = []
    if sys.platform != "darwin":
        return checks

    acc = subprocess.run(
        [
            "osascript",
            "-e",
            'tell application "System Events" to get name of every process',
        ],
        capture_output=True,
        text=True,
    )
    checks.append(
        ("permissions.accessibility", acc.returncode == 0, "System Events UI access")
    )

    auto = subprocess.run(
        ["osascript", "-e", 'tell application "Finder" to get name'],
        capture_output=True,
        text=True,
    )
    checks.append(
        ("permissions.automation", auto.returncode == 0, "AppleScript app automation")
    )

    tmp = Path(tempfile.gettempdir()) / f"swarm-doctor-{os.getpid()}.png"
    scr = subprocess.run(
        ["screencapture", "-x", str(tmp)], capture_output=True, text=True
    )
    ok_scr = scr.returncode == 0 and tmp.exists()
    checks.append(("permissions.screen_recording", ok_scr, "screen capture permission"))
    tmp.unlink(missing_ok=True)
    return checks


def _doctor_check_codex_limits():
    cfg_path = Path.home() / ".codex" / "config.toml"
    if not cfg_path.exists():
        return [("codex.config", False, f"missing {cfg_path}")]

    try:
        data = tomllib.loads(cfg_path.read_text())
    except Exception as e:  # noqa: BLE001
        return [("codex.config", False, f"parse failed: {e}")]

    checks = []
    for key, min_expected in DOCTOR_LIMIT_MIN.items():
        value = _nested_get(data, key)
        ok = False
        if isinstance(min_expected, bool):
            ok = value is min_expected
        elif isinstance(min_expected, str):
            ok = value == min_expected
        elif isinstance(min_expected, (int, float)):
            ok = isinstance(value, (int, float)) and value >= min_expected

        detail = f"{key}={value!r} (need >= {min_expected!r})"
        checks.append((f"codex.{key}", ok, detail))

    agents_cfg = data.get("agents", {})
    if isinstance(agents_cfg, dict):
        for agent_name, cfg in agents_cfg.items():
            if not isinstance(cfg, dict):
                continue
            raw = cfg.get("config_file")
            if not raw:
                checks.append(
                    (
                        f"codex.agents.{agent_name}.config_file",
                        False,
                        "missing config_file",
                    )
                )
                continue

            candidate = Path(str(raw)).expanduser()
            if not candidate.is_absolute():
                candidate = cfg_path.parent / candidate
            ok = candidate.exists()
            checks.append(
                (
                    f"codex.agents.{agent_name}.config_file",
                    ok,
                    f"{raw!r} -> {candidate}",
                )
            )
    return checks


def cmd_doctor(args):
    config = load_config()
    results = []
    fixes = []

    # Core tools
    tmux_ok = shutil.which("tmux") is not None
    results.append(("core.tmux", tmux_ok, "tmux binary in PATH"))
    uv_ok = shutil.which("uv") is not None
    results.append(("core.uv", uv_ok, "uv binary in PATH"))

    # Agent preflight + auth hints
    for name, cfg in config.get("agents", {}).items():
        ok, msg = preflight(name, cfg)
        results.append((f"agent.{name}.preflight", ok, msg or "ok"))
        auth_warn = auth_check(name)
        results.append(
            (
                f"agent.{name}.auth",
                not bool(auth_warn),
                auth_warn or "credentials detected",
            )
        )

    # Codex runtime sanity check (catches broken config_file references).
    codex_bin = shutil.which("codex")
    if codex_bin:
        rt = subprocess.run(
            [codex_bin, "features", "list"],
            capture_output=True,
            text=True,
        )
        if rt.returncode == 0:
            results.append(("agent.codex.runtime", True, "codex features list ok"))
        else:
            detail = (rt.stderr or rt.stdout or "non-zero exit").strip().splitlines()
            results.append(
                ("agent.codex.runtime", False, detail[0] if detail else "non-zero exit")
            )

    # Database / queue
    try:
        db = get_db()
        total = db.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
        results.append(("db.sqlite", True, f"ok (messages={total})"))

        stale_rows = []
        for name, session in db.execute(
            "SELECT name, session FROM agents WHERE status IN ('running','starting','dead')"
        ).fetchall():
            if not session_exists(session):
                stale_rows.append(name)
        if stale_rows:
            results.append(
                ("db.agents.rows", False, f"stale rows: {', '.join(stale_rows)}")
            )
            if args.fix:
                for name in stale_rows:
                    db.execute("DELETE FROM agents WHERE name=?", (name,))
                fixes.append(f"removed stale agent rows: {', '.join(stale_rows)}")
        else:
            results.append(("db.agents.rows", True, "no stale rows"))
    finally:
        try:
            db.close()
        except Exception:
            pass

    # Daemon
    pid = daemon_pid()
    if pid is None:
        results.append(("daemon.pid", True, "no pid file"))
        daemon_running = False
    elif process_alive(pid):
        results.append(("daemon.pid", True, f"running (pid {pid})"))
        daemon_running = True
    else:
        results.append(("daemon.pid", False, f"stale pid file (pid {pid})"))
        daemon_running = False
        if args.fix:
            PID_PATH.unlink(missing_ok=True)
            fixes.append("removed stale daemon pid file")

    if args.fix and not daemon_running and not args.no_start_daemon:
        daemon_start(config)
        fixes.append("started daemon")

    # macOS permissions
    for key, ok, detail in _doctor_check_macos_permissions():
        results.append((key, ok, detail))
    if args.fix and sys.platform == "darwin":
        failed_perm = [
            r for r in results if r[0].startswith("permissions.") and not r[1]
        ]
        if failed_perm:
            subprocess.run(
                [
                    "open",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                ],
                capture_output=True,
            )
            subprocess.run(
                [
                    "open",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                ],
                capture_output=True,
            )
            subprocess.run(
                [
                    "open",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                ],
                capture_output=True,
            )
            fixes.append("opened Privacy settings panes for permission grants")

    # Codex limits/config
    results.extend(_doctor_check_codex_limits())

    # Print report
    ok_count = sum(1 for _, ok, _ in results if ok)
    fail_count = len(results) - ok_count
    print("swarm doctor")
    print("=" * 60)
    for key, ok, detail in results:
        mark = "OK" if ok else "WARN"
        print(f"[{mark:<4}] {key:<36} {detail}")

    if fixes:
        print("\nauto-fixes:")
        for item in fixes:
            print(f"  - {item}")

    print(f"\nsummary: {ok_count} ok, {fail_count} warn")
    if args.strict and fail_count > 0:
        raise SystemExit(1)


# ── cmd: send ───────────────────────────────────────────────────────────────


def cmd_send(args):
    if args.recipient == "all":
        if not active_agents():
            print(f"auto-start: {DEFAULT_GO_AGENTS}")
            up_args = argparse.Namespace(agents=DEFAULT_GO_AGENTS, project=os.getcwd())
            cmd_up(up_args)
    elif args.recipient not in {"all", "user"}:
        session = f"swarm-{args.recipient}"
        if not session_exists(session):
            print(f"auto-start: {args.recipient}")
            up_args = argparse.Namespace(agents=args.recipient, project=os.getcwd())
            cmd_up(up_args)

    db = get_db()
    sender = os.environ.get("SWARM_AGENT", "user")
    db.execute(
        "INSERT INTO messages (sender, recipient, body) VALUES (?, ?, ?)",
        (sender, args.recipient, args.message),
    )
    preview = args.message[:80] + ("..." if len(args.message) > 80 else "")
    print(f"\u2192 {args.recipient}: {preview}")


def active_agents():
    db = get_db()
    try:
        rows = db.execute(
            "SELECT name, session FROM agents WHERE status IN ('running','starting')"
        ).fetchall()
        return [name for name, session in rows if session_exists(session)]
    finally:
        db.close()


def cmd_start(args):
    cmd_go(args)


def cmd_stop(args):
    down_args = argparse.Namespace(agent=None)
    cmd_down(down_args)


def cmd_reset(args):
    down_args = argparse.Namespace(agent=None)
    cmd_down(down_args)
    go_args = argparse.Namespace(
        recipient=args.recipient,
        agents=args.agents,
        project=args.project,
        wait=args.wait,
    )
    cmd_go(go_args)


def cmd_clean(_args):
    db = get_db()
    try:
        deleted = db.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
        db.execute("DELETE FROM messages")
    finally:
        db.close()

    INBOX_PATH.write_text("")
    print(f"cleaned: {deleted} messages, inbox cleared")


def fetch_user_messages(last_id, sender=None):
    db = get_db()
    try:
        if sender:
            rows = db.execute(
                "SELECT id, sender, body, created_at "
                "FROM messages "
                "WHERE recipient='user' AND id>? AND sender=? "
                "ORDER BY id",
                (last_id, sender),
            ).fetchall()
        else:
            rows = db.execute(
                "SELECT id, sender, body, created_at "
                "FROM messages "
                "WHERE recipient='user' AND id>? "
                "ORDER BY id",
                (last_id,),
            ).fetchall()
        return rows
    finally:
        db.close()


def last_user_message_id(sender=None):
    db = get_db()
    try:
        if sender:
            row = db.execute(
                "SELECT COALESCE(MAX(id), 0) "
                "FROM messages WHERE recipient='user' AND sender=?",
                (sender,),
            ).fetchone()
        else:
            row = db.execute(
                "SELECT COALESCE(MAX(id), 0) FROM messages WHERE recipient='user'"
            ).fetchone()
        return int(row[0] or 0)
    finally:
        db.close()


def cmd_chat(args):
    recipient = args.recipient

    if recipient == "all":
        if not active_agents():
            print(f"auto-start: {DEFAULT_GO_AGENTS}")
            up_args = argparse.Namespace(agents=DEFAULT_GO_AGENTS, project=os.getcwd())
            cmd_up(up_args)
    else:
        session = f"swarm-{recipient}"
        if not session_exists(session):
            print(f"auto-start: {recipient}")
            up_args = argparse.Namespace(agents=recipient, project=os.getcwd())
            cmd_up(up_args)

    print(f"chat -> {recipient} (type /exit to quit, empty line to refresh)")
    print("commands: /help /status /peek <agent> /send <agent> <msg> /clear /down")
    last_id = last_user_message_id(None if recipient == "all" else recipient)

    while True:
        rows = fetch_user_messages(last_id, None if recipient == "all" else recipient)
        for msg_id, sender, body, created in rows:
            last_id = msg_id
            ts = created[11:16] if created else "??:??"
            print(f"[{ts}] {sender}: {body}")

        try:
            text = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("")
            break

        if not text:
            continue
        if text in {"/exit", "/quit", ":q"}:
            break
        if text == "/help":
            print(
                "commands: /help /status /peek <agent> /send <agent> <msg> /clear /down"
            )
            continue
        if text == "/status":
            cmd_status(argparse.Namespace())
            continue
        if text == "/down":
            cmd_down(argparse.Namespace(agent=None))
            break
        if text == "/clear":
            cmd_clean(argparse.Namespace())
            last_id = last_user_message_id(None if recipient == "all" else recipient)
            continue
        if text.startswith("/peek "):
            parts = shlex.split(text)
            if len(parts) >= 2:
                cmd_peek(argparse.Namespace(agent=parts[1], last=50))
            else:
                print("usage: /peek <agent>")
            continue
        if text.startswith("/send "):
            parts = shlex.split(text)
            if len(parts) >= 3:
                target = parts[1]
                msg = " ".join(parts[2:])
                cmd_send(argparse.Namespace(recipient=target, message=msg))
            else:
                print("usage: /send <agent> <message>")
            continue

        send_args = argparse.Namespace(recipient=recipient, message=text)
        cmd_send(send_args)

        deadline = time.time() + args.wait
        while time.time() < deadline:
            rows = fetch_user_messages(
                last_id, None if recipient == "all" else recipient
            )
            if rows:
                for msg_id, sender, body, created in rows:
                    last_id = msg_id
                    ts = created[11:16] if created else "??:??"
                    print(f"[{ts}] {sender}: {body}")
                break
            time.sleep(0.3)


def cmd_go(args):
    recipient = args.recipient
    agents = args.agents

    if not agents:
        if recipient == "all":
            agents = DEFAULT_GO_AGENTS
        else:
            agents = recipient

    up_args = argparse.Namespace(agents=agents, project=args.project)
    cmd_up(up_args)

    chat_args = argparse.Namespace(recipient=recipient, wait=args.wait)
    cmd_chat(chat_args)


# ── cmd: log ────────────────────────────────────────────────────────────────


def cmd_log(args):
    db = get_db()
    config = load_config()
    max_retries = config.get("max_retries", 5)
    rows = db.execute(
        "SELECT sender, recipient, body, created_at, delivered_at, attempts "
        "FROM messages ORDER BY id DESC LIMIT ?",
        (args.last,),
    ).fetchall()

    if not rows:
        print("no messages")
        return

    for sender, recipient, body, created, delivered, attempts in reversed(rows):
        if delivered:
            icon = "\u2713"
        elif attempts >= max_retries:
            icon = "\u2717"
        else:
            icon = "\u2026"
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
    pid = daemon_pid()
    if pid is not None:
        try:
            os.kill(pid, 0)
            print(f"daemon: already running (pid {pid})")
            return
        except ProcessLookupError:
            PID_PATH.unlink(missing_ok=True)

    if LOG_PATH.exists() and LOG_PATH.stat().st_size > 1_000_000:
        LOG_PATH.write_text("")

    swarm_bin = shutil.which("swarm") or os.path.abspath(sys.argv[0])
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

    with open(os.devnull, "r") as devnull, open(LOG_PATH, "a") as log_file:
        proc = subprocess.Popen(
            [swarm_bin, "daemon", "--foreground"],
            stdin=devnull,
            stdout=log_file,
            stderr=log_file,
            close_fds=True,
            start_new_session=True,
            env=os.environ.copy(),
        )

    PID_PATH.write_text(str(proc.pid))
    time.sleep(0.2)
    if proc.poll() is not None:
        PID_PATH.unlink(missing_ok=True)
        print("daemon: failed to start (check ~/.swarm/daemon.log)")
        return

    print(f"daemon: started (pid {proc.pid})")


def daemon_stop():
    pid = daemon_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
        print(f"daemon: stopped (pid {pid})")
    except ProcessLookupError:
        pass
    PID_PATH.unlink(missing_ok=True)


def daemon_pid():
    if not PID_PATH.exists():
        return None
    raw = PID_PATH.read_text().strip()
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


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
            "FROM messages WHERE delivered_at IS NULL "
            "AND (recipient='user' OR attempts < ?)",
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
    subcommands = {
        "go",
        "start",
        "stop",
        "reset",
        "clean",
        "up",
        "down",
        "restart",
        "status",
        "watch",
        "doctor",
        "send",
        "chat",
        "log",
        "inbox",
        "attach",
        "peek",
        "daemon",
    }

    if len(sys.argv) == 1:
        sys.argv = [sys.argv[0], "go"]

    if (
        len(sys.argv) >= 2
        and sys.argv[1] not in subcommands
        and sys.argv[1] not in {"-h", "--help"}
    ):
        if sys.argv[1] in agent_names:
            if len(sys.argv) >= 3:
                sys.argv = [sys.argv[0], "send", sys.argv[1], " ".join(sys.argv[2:])]
            else:
                sys.argv = [sys.argv[0], "chat", sys.argv[1]]
        else:
            sys.argv = [sys.argv[0], "send", "all", " ".join(sys.argv[1:])]

    p = argparse.ArgumentParser(prog="swarm", description="multi-agent orchestrator")
    sub = p.add_subparsers(dest="cmd")

    go = sub.add_parser("go", help="start and enter chat in one command")
    go.add_argument(
        "recipient",
        nargs="?",
        default="all",
        help="chat target: agent name or 'all' (default: all)",
    )
    go.add_argument(
        "--agents",
        "-a",
        help="agents to start before chat (comma-separated, default: all or recipient)",
    )
    go.add_argument("--project", "-p", help="project directory (default: cwd)")
    go.add_argument(
        "--wait",
        "-w",
        type=float,
        default=2.0,
        help="seconds to wait for an immediate response after each message",
    )
    start = sub.add_parser("start", help="alias for go")
    start.add_argument(
        "recipient",
        nargs="?",
        default="all",
        help="chat target: agent name or 'all' (default: all)",
    )
    start.add_argument(
        "--agents",
        "-a",
        help="agents to start before chat (comma-separated, default: all or recipient)",
    )
    start.add_argument("--project", "-p", help="project directory (default: cwd)")
    start.add_argument(
        "--wait",
        "-w",
        type=float,
        default=2.0,
        help="seconds to wait for an immediate response after each message",
    )

    sub.add_parser("stop", help="stop all agents and daemon")

    reset = sub.add_parser("reset", help="down + go")
    reset.add_argument(
        "recipient",
        nargs="?",
        default="all",
        help="chat target: agent name or 'all' (default: all)",
    )
    reset.add_argument(
        "--agents",
        "-a",
        help="agents to start before chat (comma-separated, default: all or recipient)",
    )
    reset.add_argument("--project", "-p", help="project directory (default: cwd)")
    reset.add_argument(
        "--wait",
        "-w",
        type=float,
        default=2.0,
        help="seconds to wait for an immediate response after each message",
    )

    sub.add_parser("clean", help="clear swarm message history and inbox")

    up = sub.add_parser("up", help="start agents + daemon")
    up.add_argument("--agents", "-a", help="comma-separated agent names")
    up.add_argument("--project", "-p", help="project directory (default: cwd)")

    down = sub.add_parser("down", help="stop agents + daemon")
    down.add_argument("--agent", help="stop specific agent only")

    restart = sub.add_parser("restart", help="restart agents")
    restart.add_argument("--agent", help="restart specific agent only")
    restart.add_argument("--project", "-p", help="project directory override")

    sub.add_parser("status", help="show running agents + pending msgs")

    watch = sub.add_parser("watch", help="live dashboard for swarm status")
    watch.add_argument(
        "--interval",
        "-i",
        type=float,
        default=2.0,
        help="refresh interval seconds",
    )
    watch.add_argument("--once", action="store_true", help="render once and exit")
    watch.add_argument(
        "--no-clear",
        action="store_true",
        help="do not clear terminal between refreshes",
    )

    doctor = sub.add_parser("doctor", help="run diagnostics and optional autofixes")
    doctor.add_argument("--fix", action="store_true", help="apply safe auto-fixes")
    doctor.add_argument(
        "--no-start-daemon",
        action="store_true",
        help="when --fix is used, do not auto-start daemon",
    )
    doctor.add_argument(
        "--strict",
        action="store_true",
        help="exit with non-zero status if any checks warn/fail",
    )

    send = sub.add_parser("send", help="send message to agent")
    send.add_argument("recipient", help="agent name or 'all'")
    send.add_argument("message", help="message text")

    chat = sub.add_parser("chat", help="interactive chat with agent")
    chat.add_argument(
        "recipient", nargs="?", default="codex", help="agent name or 'all'"
    )
    chat.add_argument(
        "--wait",
        "-w",
        type=float,
        default=2.0,
        help="seconds to wait for an immediate response after each message",
    )

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
        "go": cmd_go,
        "start": cmd_start,
        "stop": cmd_stop,
        "reset": cmd_reset,
        "clean": cmd_clean,
        "up": cmd_up,
        "down": cmd_down,
        "restart": cmd_restart,
        "status": cmd_status,
        "watch": cmd_watch,
        "doctor": cmd_doctor,
        "send": cmd_send,
        "chat": cmd_chat,
        "log": cmd_log,
        "inbox": cmd_inbox,
        "attach": cmd_attach,
        "peek": cmd_peek,
        "daemon": cmd_daemon,
    }
    cmds[args.cmd](args)


if __name__ == "__main__":
    main()
