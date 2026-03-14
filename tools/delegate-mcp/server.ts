import { randomUUID } from 'node:crypto';
import { mkdir, rename, rm, stat } from 'node:fs/promises';

const home = process.env.HOME ?? '/tmp';
const tmp = (process.env.TMPDIR ?? '/tmp').replace(/\/$/, '');
const legacy_state_file = `${tmp}/delegate-mcp-sessions.json`;
const state_dir = `${tmp}/delegate-mcp-sessions`;
const codex_history_turns = 12;
const codex_history_chars = 24000;
const lock_timeout_ms = Number(process.env.DELEGATE_SESSION_LOCK_TIMEOUT_MS ?? 3600000);
const orphan_lock_ms = 5000;
const pid_reuse_slop_ms = 5000;

type Agent = 'codex' | 'claude';
type Turn = { role: 'user' | 'assistant'; content: string };
type Status = 'running' | 'completed' | 'error';
type Session = {
  agent: Agent;
  cwd: string;
  conv_id?: string;
  history: Turn[];
  created_at: string;
  updated_at: string;
  status: Status;
  pid?: number;
  error?: string;
};

const sessions = new Map<string, Session>();

const gen_id = (prefix: Agent) => `${prefix}-${Date.now()}-${randomUUID()}`;
const stamp = () => new Date().toISOString();
const session_file = (session_id: string) => `${state_dir}/${session_id}.json`;
const lock_dir = (session_id: string) => `${state_dir}/${session_id}.lock`;

async function exec(cmd: string[], cwd: string, env = process.env) {
  const proc = Bun.spawn(cmd, { cwd, env, stdin: 'ignore', stdout: 'pipe', stderr: 'pipe' });
  const [out, err] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  return { code: await proc.exited, out: out.trim(), err: err.trim() };
}

async function ensure_state_dir() {
  await mkdir(state_dir, { recursive: true });
}

function pid_alive(pid: number) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e: any) {
    return e?.code !== 'ESRCH';
  }
}

function parse_etime(raw: string) {
  const text = raw.trim();
  if (!text) return;
  const [days_text, clock_text] = text.includes('-') ? text.split('-', 2) : [undefined, text];
  const parts = clock_text.split(':').map((part) => Number(part));
  if (parts.some((part) => Number.isNaN(part))) return;
  let seconds = 0;
  if (parts.length === 3) seconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
  else if (parts.length === 2) seconds = parts[0] * 60 + parts[1];
  else if (parts.length === 1) seconds = parts[0];
  else return;
  if (days_text) {
    const days = Number(days_text);
    if (Number.isNaN(days)) return;
    seconds += days * 86400;
  }
  return seconds * 1000;
}

async function pid_elapsed_ms(pid: number) {
  const result = await exec(['ps', '-o', 'etime=', '-p', String(pid)], home);
  if (result.code !== 0) return;
  return parse_etime(result.out || result.err);
}

async function read_lock_owner(session_id: string) {
  const file = Bun.file(`${lock_dir(session_id)}/owner.json`);
  if (!(await file.exists())) return;
  try {
    const parsed = JSON.parse(await file.text()) as { pid?: unknown; created_at?: unknown };
    if (typeof parsed.pid !== 'number') return;
    return {
      pid: parsed.pid,
      created_at: typeof parsed.created_at === 'string' ? parsed.created_at : undefined,
    };
  } catch {
    return;
  }
}

async function lock_age_ms(path: string) {
  try {
    return Date.now() - (await stat(path)).mtimeMs;
  } catch {
    return;
  }
}

async function with_session_lock<T>(session_id: string, fn: () => Promise<T>): Promise<T> {
  await ensure_state_dir();
  const path = lock_dir(session_id);
  const started = Date.now();
  let wait_ms = 25;
  while (true) {
    try {
      await mkdir(path);
      await Bun.write(
        `${path}/owner.json`,
        JSON.stringify({ pid: process.pid, created_at: stamp() }, null, 2)
      );
      break;
    } catch (e: any) {
      if (e?.code !== 'EEXIST') throw e;
      const owner = await read_lock_owner(session_id);
      if (owner) {
        if (!pid_alive(owner.pid)) {
          await rm(path, { recursive: true, force: true });
          continue;
        }
        if (owner.created_at) {
          const lock_started = Date.parse(owner.created_at);
          const elapsed_ms = await pid_elapsed_ms(owner.pid);
          if (
            Number.isFinite(lock_started) &&
            typeof elapsed_ms === 'number' &&
            Date.now() - elapsed_ms > lock_started + 1000
          ) {
            await rm(path, { recursive: true, force: true });
            continue;
          }
        }
      } else {
        const age = await lock_age_ms(path);
        if (typeof age === 'number' && age >= orphan_lock_ms) {
          await rm(path, { recursive: true, force: true });
          continue;
        }
      }
      if (lock_timeout_ms > 0 && Date.now() - started >= lock_timeout_ms) {
        throw new Error(`timed out waiting for session lock: ${session_id}`);
      }
      await Bun.sleep(wait_ms);
      wait_ms = Math.min(wait_ms * 2, 500);
    }
  }
  try {
    return await fn();
  } finally {
    try {
      await rm(path, { recursive: true, force: true });
    } catch {}
  }
}

function is_turn(turn: unknown): turn is Turn {
  return (
    !!turn &&
    typeof turn === 'object' &&
    ((turn as Turn).role === 'user' || (turn as Turn).role === 'assistant') &&
    typeof (turn as Turn).content === 'string'
  );
}

function normalize_session(raw: unknown, session_id: string): Session {
  if (!raw || typeof raw !== 'object') throw new Error(`corrupt session file: ${session_id}`);
  const session = raw as Partial<Session>;
  if (session.agent !== 'codex' && session.agent !== 'claude') {
    throw new Error(`corrupt session file: ${session_id}`);
  }
  if (typeof session.cwd !== 'string' || !session.cwd.trim()) {
    throw new Error(`corrupt session file: ${session_id}`);
  }
  if (!Array.isArray(session.history) || !session.history.every(is_turn)) {
    throw new Error(`corrupt session file: ${session_id}`);
  }
  const created_at = typeof session.created_at === 'string' ? session.created_at : stamp();
  const updated_at = typeof session.updated_at === 'string' ? session.updated_at : created_at;
  const raw_status = (session as any).status;
  const status: Status =
    raw_status === 'running' ? 'running' : raw_status === 'error' ? 'error' : 'completed';
  return {
    agent: session.agent,
    cwd: session.cwd,
    conv_id:
      typeof session.conv_id === 'string' && session.conv_id.trim() ? session.conv_id : undefined,
    history: session.history.map((turn) => ({ role: turn.role, content: turn.content })),
    created_at,
    updated_at,
    status,
    pid: typeof (session as any).pid === 'number' ? (session as any).pid : undefined,
    error: typeof (session as any).error === 'string' ? (session as any).error : undefined,
  };
}

async function read_session_file(session_id: string) {
  await ensure_state_dir();
  const file = Bun.file(session_file(session_id));
  if (!(await file.exists())) return;
  const raw = await file.text();
  if (!raw.trim()) throw new Error(`corrupt session file: ${session_id}`);
  const session = normalize_session(JSON.parse(raw), session_id);
  sessions.set(session_id, session);
  return session;
}

async function read_legacy_session(session_id: string) {
  const file = Bun.file(legacy_state_file);
  if (!(await file.exists())) return;
  const raw = await file.text();
  if (!raw.trim()) return;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('corrupt legacy session store');
  }
  if (!parsed || typeof parsed !== 'object') throw new Error('corrupt legacy session store');
  if (!(session_id in parsed)) return;
  return normalize_session((parsed as Record<string, unknown>)[session_id], session_id);
}

function parse_claude(raw: string) {
  let output = raw.trim();
  let conv_id: string | undefined;
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed.session_id === 'string') conv_id = parsed.session_id;
    if (typeof parsed.result === 'string' && parsed.result.trim()) output = parsed.result.trim();
  } catch {}
  return { output, conv_id };
}

function push_turn(session: Session, role: 'user' | 'assistant', content: string) {
  const text = content.trim();
  if (!text) return;
  session.history.push({ role, content: text });
  session.updated_at = stamp();
}

async function store_session(session_id: string, session: Session) {
  if (!session.created_at) session.created_at = stamp();
  if (!session.updated_at) session.updated_at = session.created_at;
  await ensure_state_dir();
  sessions.set(session_id, session);
  const body = JSON.stringify(session, null, 2);
  const path = session_file(session_id);
  const temp = `${path}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await Bun.write(temp, body);
    try {
      await rename(temp, path);
    } catch {
      await Bun.write(path, body);
      await rm(temp, { force: true });
    }
  } catch (e) {
    await rm(temp, { force: true });
    throw e;
  }
}

async function load_session(session_id: string) {
  const current = await read_session_file(session_id);
  if (current) return current;
  const legacy = await read_legacy_session(session_id);
  if (!legacy) throw new Error(`unknown session: ${session_id}`);
  await store_session(session_id, legacy);
  return legacy;
}

async function session_pid_alive(session: Session) {
  if (typeof session.pid !== 'number') return false;
  if (!pid_alive(session.pid)) return false;
  const created_at = Date.parse(session.created_at);
  const elapsed_ms = await pid_elapsed_ms(session.pid);
  if (!Number.isFinite(created_at)) return true;
  if (typeof elapsed_ms !== 'number') return pid_alive(session.pid);
  return Date.now() - elapsed_ms <= created_at + pid_reuse_slop_ms;
}

function finish_session(session: Session, status: Status, error?: string) {
  session.status = status;
  if (error) session.error = error;
  else delete session.error;
  session.updated_at = stamp();
  delete session.pid;
}

function build_context_prompt(session: Session, task: string) {
  if (session.history.length === 0) return task;
  const recent: string[] = [];
  let chars = 0;
  for (let i = session.history.length - 1; i >= 0; i--) {
    const block = `#${i + 1} ${session.history[i].role}\n${session.history[i].content}`;
    if (recent.length >= codex_history_turns || chars + block.length > codex_history_chars) break;
    recent.unshift(block);
    chars += block.length;
  }
  const transcript = recent.join('\n\n');
  return [
    `Continue this delegated ${session.agent} session.`,
    'Preserve prior context and respond only to the latest task.',
    '',
    recent.length === session.history.length ? 'Session history:' : 'Recent session history:',
    transcript,
    '',
    'Latest task:',
    task,
  ].join('\n');
}

async function run_codex(prompt: string, cwd: string) {
  const result = await exec(
    ['codex', 'exec', '--skip-git-repo-check', '-o', '/dev/stdout', prompt],
    cwd
  );
  if (result.code !== 0 && !result.out) {
    throw new Error(result.err || `codex exited ${result.code}`);
  }
  return result.out || result.err;
}

function claude_env() {
  const env = { ...process.env };
  delete env.CLAUDECODE;
  return env;
}

async function run_claude(prompt: string, cwd: string, conv_id?: string) {
  const result = await exec(
    conv_id
      ? [
          'claude',
          '--dangerously-skip-permissions',
          '--setting-sources',
          'user,project,local',
          '--output-format',
          'json',
          '--resume',
          conv_id,
          '-p',
          prompt,
        ]
      : [
          'claude',
          '--dangerously-skip-permissions',
          '--setting-sources',
          'user,project,local',
          '--output-format',
          'json',
          '-p',
          prompt,
        ],
    cwd,
    claude_env()
  );
  if (result.code !== 0) {
    throw new Error(result.out || result.err || `claude exited ${result.code}`);
  }
  return parse_claude(result.out || result.err);
}

async function start_session(agent: Agent, task: string, cwd: string) {
  const session_id = gen_id(agent);
  const now = stamp();

  const cmd =
    agent === 'codex'
      ? ['codex', 'exec', '--skip-git-repo-check', '-o', '/dev/stdout', task]
      : [
          'claude',
          '--dangerously-skip-permissions',
          '--setting-sources',
          'user,project,local',
          '--output-format',
          'json',
          '-p',
          task,
        ];

  const session: Session = {
    agent,
    cwd,
    history: [],
    status: 'running',
    created_at: now,
    updated_at: now,
  };
  await store_session(session_id, session);

  const proc = Bun.spawn(cmd, {
    cwd,
    stdin: 'ignore',
    stdout: 'pipe',
    stderr: 'pipe',
    env: agent === 'claude' ? claude_env() : process.env,
  });
  session.pid = proc.pid;
  session.updated_at = stamp();
  await store_session(session_id, session);

  (async () => {
    let err = '';
    let code: number | undefined;
    try {
      const [out, raw_err] = await Promise.all([
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
      ]);
      err = raw_err.trim();
      code = await proc.exited;
      const output = out.trim() || err;
      await with_session_lock(session_id, async () => {
        const s = await load_session(session_id);
        if (agent === 'claude') {
          const parsed = parse_claude(output);
          s.conv_id = parsed.conv_id;
          push_turn(s, 'user', task);
          push_turn(s, 'assistant', parsed.output);
        } else {
          push_turn(s, 'user', task);
          push_turn(s, 'assistant', output);
        }
        if (agent === 'claude' && code === 0 && !s.conv_id) {
          finish_session(s, 'error', 'claude did not return session_id');
        } else {
          finish_session(s, code === 0 ? 'completed' : 'error', code !== 0 ? err || `exited ${code}` : undefined);
        }
        await store_session(session_id, s);
      });
    } catch (e: any) {
      code ??= await proc.exited.catch(() => undefined);
      const status: Status = code === 0 ? 'completed' : 'error';
      const error =
        status === 'error'
          ? err || e?.message || (typeof code === 'number' ? `exited ${code}` : 'background handler failed')
          : undefined;
      console.error(`[delegate] background handler failed for ${session_id}: ${e?.message ?? e}`);
      try {
        await with_session_lock(session_id, async () => {
          const s = await load_session(session_id);
          finish_session(s, status, error);
          await store_session(session_id, s);
        });
      } catch (inner: any) {
        console.error(`[delegate] failed to persist terminal status for ${session_id}: ${inner?.message}`);
        try {
          const s = await load_session(session_id);
          if (s.status === 'running' && s.pid === proc.pid && !(await session_pid_alive(s))) {
            finish_session(s, status, error);
            await store_session(session_id, s);
          }
        } catch (fallback: any) {
          console.error(`[delegate] fallback persist failed for ${session_id}: ${fallback?.message}`);
        }
      }
    }
  })();

  return { session_id, agent, status: 'running' };
}

async function check_status(session_id: string, expected_agent?: Agent) {
  let session = await load_session(session_id);
  if (expected_agent && session.agent !== expected_agent) {
    throw new Error(
      `session ${session_id} belongs to ${session.agent}; use delegate_${session.agent}`
    );
  }
  if (session.status === 'running') {
    session = await with_session_lock(session_id, async () => {
      const current = await load_session(session_id);
      if (current.status !== 'running') return current;
      if (await session_pid_alive(current)) return current;
      if (current.pid) {
        finish_session(current, 'error', current.error || 'process exited before handler completed');
      } else {
        finish_session(current, 'completed');
      }
      await store_session(session_id, current);
      return current;
    });
  }
  return {
    session_id,
    agent: session.agent,
    status: session.status,
    output: session.status !== 'running' ? session.history.at(-1)?.content : undefined,
    error: session.error,
  };
}

async function continue_session(session_id: string, task: string, expected_agent?: Agent) {
  return with_session_lock(session_id, async () => {
    const session = await load_session(session_id);
    if (expected_agent && session.agent !== expected_agent) {
      throw new Error(
        `session ${session_id} belongs to ${session.agent}; use delegate_${session.agent}`
      );
    }
    if (session.status !== 'completed') {
      throw new Error(`session ${session_id} is ${session.status}; cannot continue`);
    }

    let output = '';
    if (session.agent === 'codex') {
      output = await run_codex(build_context_prompt(session, task), session.cwd);
    } else {
      if (!session.conv_id) throw new Error(`session ${session_id} has no claude session_id`);
      const result = await run_claude(task, session.cwd, session.conv_id);
      if (!result.conv_id) throw new Error('claude did not return session_id');
      output = result.output;
      session.conv_id = result.conv_id;
    }

    push_turn(session, 'user', task);
    push_turn(session, 'assistant', output);
    await store_session(session_id, session);
    return { session_id, agent: session.agent, status: 'continued', output };
  });
}

async function call_named_delegate(agent: Agent, args: any) {
  const task = typeof args?.task === 'string' ? args.task.trim() : '';
  const sid = typeof args?.session_id === 'string' ? args.session_id.trim() : '';

  if (sid && !task) return check_status(sid, agent);
  if (sid && task) return continue_session(sid, task, agent);
  if (!task) throw new Error(`delegate_${agent} requires task for new sessions`);

  const cwd = typeof args?.cwd === 'string' && args.cwd.trim() ? args.cwd.trim() : home;
  return start_session(agent, task, cwd);
}

const tools = [
  {
    name: 'delegate_codex',
    description:
      'delegate implementation to codex. async: returns immediately with session_id. poll with delegate_codex(session_id) for status. continue with delegate_codex(session_id, task).',
    inputSchema: {
      type: 'object',
      properties: {
        task: {
          type: 'string',
          description: 'task to delegate. required for new sessions, optional for status checks',
        },
        cwd: { type: 'string', description: 'working directory for new session (default: $HOME)' },
        session_id: {
          type: 'string',
          description: 'existing session; without task = status check, with task = continue',
        },
      },
    },
  },
  {
    name: 'delegate_claude',
    description:
      'delegate reasoning/review/analysis to claude. async: returns immediately with session_id. poll with delegate_claude(session_id) for status. continue with delegate_claude(session_id, task).',
    inputSchema: {
      type: 'object',
      properties: {
        task: {
          type: 'string',
          description: 'task to delegate. required for new sessions, optional for status checks',
        },
        cwd: { type: 'string', description: 'working directory for new session (default: $HOME)' },
        session_id: {
          type: 'string',
          description: 'existing session; without task = status check, with task = continue',
        },
      },
    },
  },
];

async function handle(req: any) {
  const { id, method, params } = req;

  if (method === 'initialize')
    return {
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'delegate', version: '4.0.0' },
      },
    };

  if (method === 'notifications/initialized') return null;

  if (method === 'tools/list') return { jsonrpc: '2.0', id, result: { tools } };

  if (method === 'tools/call') {
    const { name, arguments: args } = params;
    try {
      let result;
      if (name === 'delegate_codex') result = await call_named_delegate('codex', args);
      else if (name === 'delegate_claude') result = await call_named_delegate('claude', args);
      else return { jsonrpc: '2.0', id, error: { code: -32601, message: `unknown tool: ${name}` } };
      return {
        jsonrpc: '2.0',
        id,
        result: { content: [{ type: 'text', text: JSON.stringify(result) }] },
      };
    } catch (e: any) {
      return {
        jsonrpc: '2.0',
        id,
        result: { content: [{ type: 'text', text: `error: ${e.message}` }], isError: true },
      };
    }
  }

  return { jsonrpc: '2.0', id, error: { code: -32601, message: `unknown method: ${method}` } };
}

await ensure_state_dir();

const reader = Bun.stdin.stream().getReader();
const decoder = new TextDecoder();
let buf = '';

while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  buf += decoder.decode(value, { stream: true });
  let nl: number;
  while ((nl = buf.indexOf('\n')) !== -1) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    try {
      const res = await handle(JSON.parse(line));
      if (res) process.stdout.write(JSON.stringify(res) + '\n');
    } catch (e: any) {
      console.error(`[delegate] handle error: ${e?.message}`);
    }
  }
}
