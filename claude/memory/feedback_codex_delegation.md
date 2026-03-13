---
name: bidirectional delegation via MCP
description: use delegate MCP for cross-agent delegation — delegate_codex for implementation, delegate_claude for reasoning, each with built-in continuation via session_id
type: feedback
---

use the delegate MCP server for cross-agent delegation. `delegate_codex(task="...")` starts coding work and `delegate_codex(session_id="...", task="...")` continues it. `delegate_claude(task="...")` starts reasoning/review work and `delegate_claude(session_id="...", task="...")` continues it.

**Why:** bidirectional delegation — claude delegates coding to codex, codex can delegate complex reasoning to claude. one MCP server registered for both agents, but the visible API stays semantically explicit and keeps session lifecycle hidden behind the server. replaces old codex-delegate (codex mcp-server).

**How to apply:** for coding tasks >10 lines with clear spec: `delegate_codex(task="detailed spec", cwd="project-root")`. continue with `delegate_codex(session_id="...", task="follow-up")`. for reasoning/review: `delegate_claude(task="analysis request", cwd="project-root")`. delegated agents don't commit — you own git. don't edit same files while delegated agent is running.
