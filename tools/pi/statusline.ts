import type { AssistantMessage } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

export default function (pi: ExtensionAPI) {
  let turnCount = 0;
  let failovers = 0;
  let lastFailoverTarget = "";

  pi.on("session_start", async (_event, ctx) => {
    turnCount = 0;
    failovers = 0;
    updateStatus(ctx);

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());

      return {
        dispose: unsub,
        invalidate() {},
        render(width: number): string[] {
          let input = 0, output = 0, cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              input += m.usage.input;
              output += m.usage.output;
              cost += m.usage.cost.total;
            }
          }

          const branch = footerData.getGitBranch();
          const fmt = (n: number) => n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`;

          const usage = ctx.getContextUsage();
          const pct = usage ? Math.round((usage.tokens / (ctx.model?.contextWindow ?? 200000)) * 100) : 0;
          const bar = progressBar(pct, 12);

          const provider = ctx.model?.provider ?? "?";
          const model = ctx.model?.id ?? "?";
          const branchStr = branch ? ` ${theme.fg("muted", branch)}` : "";
          const failStr = failovers > 0
            ? theme.fg("warning", ` ⚡${failovers}`)
            : "";

          const left = [
            theme.fg("accent", `${provider}`),
            theme.fg("dim", "/"),
            theme.fg("accent", `${model}`),
            theme.fg("dim", ` ${bar} ${pct}%`),
            failStr,
          ].join("");

          const right = [
            theme.fg("dim", `↑${fmt(input)} ↓${fmt(output)}`),
            cost > 0 ? theme.fg("dim", ` $${cost.toFixed(3)}`) : "",
            theme.fg("dim", ` t${turnCount}`),
            branchStr,
          ].join("");

          const pad = " ".repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(right)));
          return [truncateToWidth(left + pad + right, width)];
        },
      };
    });
  });

  pi.on("session_switch", async (event) => {
    if (event.reason === "new") {
      turnCount = 0;
      failovers = 0;
    }
  });

  pi.on("turn_start", async () => { turnCount++; });

  pi.on("message_end", async (event, ctx) => {
    const msg = event.message;
    if (msg.role !== "assistant" || msg.stopReason !== "error") return;

    const err = msg.errorMessage ?? "";
    if (QUOTA_RE.test(err)) {
      failovers++;
      updateStatus(ctx);
    }
  });

  function updateStatus(ctx: any) {
    if (failovers > 0 && lastFailoverTarget) {
      ctx.ui.setStatus(
        "failover",
        ctx.ui.theme.fg("warning", `⚡ → ${lastFailoverTarget}`)
      );
    }
  }

  const QUOTA_RE =
    /rate.limit|429|quota|credit|exhaust|capacity|overload|too many|resource_exhausted|billing|limit exceeded/i;
}

function progressBar(pct: number, width: number): string {
  const filled = Math.round((pct / 100) * width);
  const empty = width - filled;
  return "█".repeat(filled) + "░".repeat(empty);
}
