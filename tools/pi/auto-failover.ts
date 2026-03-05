import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const FALLBACK_CHAIN = [
  { provider: "google-gemini-cli", model: "gemini-3.1-pro-preview" },
  { provider: "google-antigravity", model: "gemini-3-pro-high" },
  { provider: "google-antigravity", model: "claude-opus-4-6-thinking" },
  { provider: "github-copilot", model: "claude-opus-4.6" },
  { provider: "github-copilot", model: "gemini-3.1-pro-preview" },
  { provider: "zai", model: "glm-5" },
];

const COOLDOWN_MS = 5 * 60 * 1000;

const QUOTA_RE =
  /rate.limit|429|quota|credit|exhaust|capacity|overload|too many|resource_exhausted|billing|limit exceeded/i;

export default function (pi: ExtensionAPI) {
  let failoverActive = false;
  let originalIdx = 0;
  let failedProviders = new Map<string, number>();
  let recoveryTimer: ReturnType<typeof setTimeout> | null = null;

  function providerKey(entry: (typeof FALLBACK_CHAIN)[number]) {
    return `${entry.provider}/${entry.model}`;
  }

  function currentIdx(ctx: any): number {
    const p = ctx.model?.provider;
    const m = ctx.model?.id;
    if (!p || !m) return 0;
    const idx = FALLBACK_CHAIN.findIndex((f) => f.provider === p && f.model === m);
    return idx >= 0 ? idx : 0;
  }

  async function tryRecover(ctx: any) {
    const now = Date.now();
    const cur = currentIdx(ctx);
    if (cur === originalIdx) return;

    for (let i = originalIdx; i < cur; i++) {
      const entry = FALLBACK_CHAIN[i];
      const key = providerKey(entry);
      const failedAt = failedProviders.get(key);
      if (!failedAt || now - failedAt < COOLDOWN_MS) continue;

      const model = ctx.modelRegistry.find(entry.provider, entry.model);
      if (!model) continue;
      const ok = await pi.setModel(model);
      if (ok) {
        failedProviders.delete(key);
        ctx.ui.notify(`recovered → ${key}`, "info");
        scheduleRecovery(ctx);
        return;
      }
    }
    scheduleRecovery(ctx);
  }

  function scheduleRecovery(ctx: any) {
    if (recoveryTimer) clearTimeout(recoveryTimer);
    if (failedProviders.size === 0) return;

    const oldest = Math.min(...failedProviders.values());
    const wait = Math.max(1000, COOLDOWN_MS - (Date.now() - oldest));
    recoveryTimer = setTimeout(() => tryRecover(ctx), wait);
  }

  pi.on("message_end", async (event, ctx) => {
    const msg = event.message;
    if (msg.role !== "assistant" || msg.stopReason !== "error") return;
    if (failoverActive) return;
    if (!QUOTA_RE.test(msg.errorMessage ?? "")) return;

    failoverActive = true;
    const cur = currentIdx(ctx);
    failedProviders.set(providerKey(FALLBACK_CHAIN[cur]), Date.now());

    for (let i = 1; i < FALLBACK_CHAIN.length; i++) {
      const next = FALLBACK_CHAIN[(cur + i) % FALLBACK_CHAIN.length];
      if (failedProviders.has(providerKey(next))) continue;

      const model = ctx.modelRegistry.find(next.provider, next.model);
      if (!model) continue;
      const ok = await pi.setModel(model);
      if (ok) {
        ctx.ui.notify(
          `quota hit → ${next.provider}/${next.model}`,
          "warning"
        );
        pi.sendUserMessage("continue — provider switched due to quota.", {
          deliverAs: "followUp",
        });
        scheduleRecovery(ctx);
        failoverActive = false;
        return;
      }
    }
    ctx.ui.notify("all providers exhausted", "error");
    failoverActive = false;
  });

  pi.on("session_start", async (_event, ctx) => {
    originalIdx = currentIdx(ctx);
    failedProviders.clear();
    if (recoveryTimer) clearTimeout(recoveryTimer);
  });

  pi.on("session_switch", async (event) => {
    if (event.reason === "new") {
      failedProviders.clear();
      if (recoveryTimer) clearTimeout(recoveryTimer);
    }
  });
}
