---
name: bidirectional delegation via MCP
description: use delegate MCP for cross-agent delegation — codex(task) for implementation, claude(task) for reasoning, reply(id, msg) to iterate
type: feedback
---

use the delegate MCP server for cross-agent delegation. codex(task) delegates implementation. claude(task) delegates reasoning/review. reply(id, msg) continues either.

**Why:** bidirectional delegation — claude delegates coding to codex, codex delegates complex reasoning to claude. one MCP server registered for both agents. replaces old codex-delegate (codex mcp-server).

**How to apply:** for coding tasks >10 lines with clear spec: codex(task="detailed spec", cwd="project-root"). for reasoning/review: claude(task="analysis request"). iterate with reply(session_id, "follow-up"). delegated agents don't commit — you own git. don't edit same files while delegated agent is running.
