import type { AssistantMessage } from '@mariozechner/pi-ai';
import type { ExtensionAPI } from '@mariozechner/pi-coding-agent';
import { truncateToWidth, visibleWidth } from '@mariozechner/pi-tui';
import { exec } from 'node:child_process';

const NOTIFY_THRESHOLD_MS = 30_000;
const COMPACT_WARN_PCT = 80;

export default function (pi: ExtensionAPI) {
  let turnCount = 0;
  let failovers = 0;
  let turnStartTime = 0;
  let compactWarned = false;

  function macNotify(title: string, body: string) {
    exec(`osascript -e 'display notification "${body}" with title "${title}"'`);
  }

  function contextPct(ctx: any): number {
    const usage = ctx.getContextUsage?.();
    if (!usage) return 0;
    return Math.round((usage.tokens / (ctx.model?.contextWindow ?? 200000)) * 100);
  }

  pi.on('session_start', async (_event, ctx) => {
    turnCount = 0;
    failovers = 0;
    compactWarned = false;

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());

      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          let input = 0,
            output = 0,
            cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === 'message' && e.message.role === 'assistant') {
              const m = e.message as AssistantMessage;
              input += m.usage.input;
              output += m.usage.output;
              cost += m.usage.cost.total;
            }
          }

          const branch = footerData.getGitBranch();
          const fmt = (n: number) => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`);

          const pct = contextPct(ctx);
          const bar = progressBar(pct, 12);

          const provider = ctx.model?.provider ?? '?';
          const model = ctx.model?.id ?? '?';
          const branchStr = branch ? ` ${theme.fg('muted', branch)}` : '';
          const failStr = failovers > 0 ? theme.fg('warning', ` ⚡${failovers}`) : '';

          const pctColor = pct >= COMPACT_WARN_PCT ? 'warning' : 'dim';

          const left = [
            theme.fg('accent', `${provider}`),
            theme.fg('dim', '/'),
            theme.fg('accent', `${model}`),
            theme.fg('dim', ` ${bar} `),
            theme.fg(pctColor, `${pct}%`),
            failStr,
          ].join('');

          const right = [
            theme.fg('dim', `↑${fmt(input)} ↓${fmt(output)}`),
            cost > 0 ? theme.fg('dim', ` $${cost.toFixed(3)}`) : '',
            theme.fg('dim', ` t${turnCount}`),
            branchStr,
          ].join('');

          const pad = ' '.repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(right)));
          return [truncateToWidth(left + pad + right, width)];
        },
      };
    });
  });

  pi.on('session_switch', async (event) => {
    if (event.reason === 'new') {
      turnCount = 0;
      failovers = 0;
      compactWarned = false;
    }
  });

  pi.on('turn_start', async () => {
    turnCount++;
    turnStartTime = Date.now();
  });

  pi.on('turn_end', async (_event, ctx) => {
    const elapsed = Date.now() - turnStartTime;
    if (elapsed >= NOTIFY_THRESHOLD_MS) {
      const secs = Math.round(elapsed / 1000);
      macNotify('pi', `turn ${turnCount} done (${secs}s)`);
    }

    const pct = contextPct(ctx);
    if (pct >= COMPACT_WARN_PCT && !compactWarned) {
      compactWarned = true;
      macNotify('pi', `context at ${pct}% — compact soon`);
    }
  });

  pi.on('message_end', async (event, ctx) => {
    const msg = event.message;
    if (msg.role !== 'assistant' || msg.stopReason !== 'error') return;

    const err = msg.errorMessage ?? '';
    if (QUOTA_RE.test(err)) {
      failovers++;
    }
  });

  const QUOTA_RE =
    /rate.limit|429|529|quota|credit|exhaust|capacity|overload|too many|resource_exhausted|billing|limit.exceeded|insufficient|usage.limit|tokens.per.min|requests.per.min|monthly.limit|daily.limit|spending.limit|budget.exceed|abuse.detect|secondary.rate/i;
}

function progressBar(pct: number, width: number): string {
  const filled = Math.round((pct / 100) * width);
  const empty = width - filled;
  return '█'.repeat(filled) + '░'.repeat(empty);
}
