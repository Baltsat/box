#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp[cli]"]
# ///
"""MCP server exposing codex as a native tool for claude code."""

from mcp.server.fastmcp import FastMCP
import subprocess
import tempfile
import os

mcp = FastMCP("codex")


@mcp.tool()
def codex_implement(spec: str, dir: str = ".", timeout: int = 600) -> str:
    """Delegate implementation task to Codex.
    Use for focused implementation with clear spec.
    Codex does NOT commit — caller owns git state.
    After delegation, run adversarial review per GLOBAL.md."""
    dir = os.path.expanduser(dir)
    prompt = f"""You are implementing a task delegated from Claude Code.

CONSTRAINTS:
- Do NOT commit. Only make file changes.
- Do NOT push or interact with remote.
- Run tests/build checks after changes when applicable.
- Report: what changed, what validated, remaining risks.

TASK:
{spec}"""

    with tempfile.TemporaryDirectory(prefix="codex-delegate-") as tmp:
        out = os.path.join(tmp, "result.md")
        log = os.path.join(tmp, "codex.log")
        try:
            with open(log, "w") as log_f:
                subprocess.run(
                    [
                        "codex",
                        "exec",
                        "--skip-git-repo-check",
                        "--ephemeral",
                        "-C",
                        dir,
                        "-o",
                        out,
                    ],
                    input=prompt.encode(),
                    stdout=log_f,
                    stderr=subprocess.STDOUT,
                    timeout=timeout,
                )
        except subprocess.TimeoutExpired:
            return f"codex timed out after {timeout}s"

        if os.path.exists(out) and os.path.getsize(out) > 0:
            content = open(out).read()
            if len(content) > 4000:
                return "[...truncated...]\n" + content[-4000:]
            return content

        tail = ""
        if os.path.exists(log):
            tail = open(log).read()[-500:]
        return f"codex produced no output.\nlog:\n{tail}"


if __name__ == "__main__":
    mcp.run(transport="stdio")
