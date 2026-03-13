const home = process.env.HOME ?? '/tmp';

type Session = { agent: 'codex' | 'claude'; cwd: string; conv_id?: string };
const sessions = new Map<string, Session>();
let counter = 0;

const gen_id = (prefix: string) => `${prefix}-${Date.now()}-${++counter}`;

async function exec(cmd: string[], cwd: string): Promise<string> {
  const proc = Bun.spawn(cmd, { cwd, stdout: 'pipe', stderr: 'pipe' });
  const [out, err] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  if (code !== 0 && !out.trim()) throw new Error(`${cmd[0]} exited ${code}: ${err.trim()}`);
  return out.trim() || err.trim();
}

async function call_codex(task: string, cwd: string) {
  const id = gen_id('codex');
  sessions.set(id, { agent: 'codex', cwd });
  const output = await exec(
    ['codex', 'exec', '--skip-git-repo-check', '-o', '/dev/stdout', task],
    cwd
  );
  return { session_id: id, output };
}

async function call_claude(task: string, cwd: string) {
  const id = gen_id('claude');
  const raw = await exec(
    ['claude', '-p', '--dangerously-skip-permissions', '--output-format', 'json', task],
    cwd
  );
  let output = raw;
  let conv_id: string | undefined;
  try {
    const parsed = JSON.parse(raw);
    conv_id = parsed.session_id;
    output = parsed.result ?? raw;
  } catch {}
  sessions.set(id, { agent: 'claude', cwd, conv_id });
  return { session_id: id, output };
}

async function call_reply(session_id: string, message: string) {
  const s = sessions.get(session_id);
  if (!s) throw new Error(`unknown session: ${session_id}`);

  if (s.agent === 'claude' && s.conv_id) {
    const raw = await exec(
      [
        'claude',
        '-p',
        '--dangerously-skip-permissions',
        '--output-format',
        'json',
        '--resume',
        s.conv_id,
        message,
      ],
      s.cwd
    );
    let output = raw;
    try {
      output = JSON.parse(raw).result ?? raw;
    } catch {}
    return { output };
  }

  const output = await exec(
    s.agent === 'codex'
      ? ['codex', 'exec', '--skip-git-repo-check', '-o', '/dev/stdout', message]
      : ['claude', '-p', '--dangerously-skip-permissions', '--output-format', 'text', message],
    s.cwd
  );
  return { output };
}

const tools = [
  {
    name: 'codex',
    description:
      'delegate implementation to codex. use for concrete coding: >10 lines, clear spec, boilerplate, tests.',
    inputSchema: {
      type: 'object',
      properties: {
        task: { type: 'string', description: 'detailed implementation spec' },
        cwd: { type: 'string', description: 'working directory (default: $HOME)' },
      },
      required: ['task'],
    },
  },
  {
    name: 'claude',
    description:
      'delegate to claude. use for reasoning, review, complex analysis, architectural decisions.',
    inputSchema: {
      type: 'object',
      properties: {
        task: { type: 'string', description: 'task description' },
        cwd: { type: 'string', description: 'working directory (default: $HOME)' },
      },
      required: ['task'],
    },
  },
  {
    name: 'reply',
    description: 'continue a previous delegation session with follow-up',
    inputSchema: {
      type: 'object',
      properties: {
        session_id: { type: 'string', description: 'session ID from codex() or claude()' },
        message: { type: 'string', description: 'follow-up message' },
      },
      required: ['session_id', 'message'],
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
        serverInfo: { name: 'delegate', version: '1.0.0' },
      },
    };

  if (method === 'notifications/initialized') return null;

  if (method === 'tools/list') return { jsonrpc: '2.0', id, result: { tools } };

  if (method === 'tools/call') {
    const { name, arguments: args } = params;
    const cwd = args?.cwd ?? home;
    try {
      let result;
      if (name === 'codex') result = await call_codex(args.task, cwd);
      else if (name === 'claude') result = await call_claude(args.task, cwd);
      else if (name === 'reply') result = await call_reply(args.session_id, args.message);
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
    } catch {}
  }
}
