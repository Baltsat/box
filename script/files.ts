#!/usr/bin/env bun

/**
 * Symlinks config files from ~/box/tools to their proper locations
 * Run via: bun script/files.ts
 */

import { dirname, join } from 'path';

const { $ } = Bun;

const home = Bun.env.HOME!;
const root = dirname(dirname(Bun.main));
const is_macos = process.platform === 'darwin';

// [source in box/tools, destination in $HOME]
// IMPORTANT: Don't symlink sensitive/platform-specific configs here!
// - SSH config: macOS-specific (UseKeychain, paths), setup.sh handles it safely
// - tmux.conf: setup.sh writes it directly (no symlink needed)
const links: [string, string][] = [
  // Shell & prompt
  ['tools/starship.toml', '.config/starship.toml'],
  ['tools/gitconfig', '.gitconfig'],
  ['tools/aliases.sh', '.config/box/aliases.sh'],
  // Bashrc (Linux only, but harmless on mac)
  ['tools/bashrc.sh', '.config/box/bashrc.sh'],
  // GitHub CLI
  ['tools/gh/config.yml', '.config/gh/config.yml'],
  // Global instructions (shared across all AI coding tools)
  ['GLOBAL.md', '.claude/CLAUDE.md'],
  ['GLOBAL.md', '.gemini/GEMINI.md'],
  ['GLOBAL.md', '.qwen/QWEN.md'],
  ['GLOBAL.md', '.copilot/copilot-instructions.md'],
  // Zed
  ['tools/zed/settings.json', '.config/zed/settings.json'],
  // Zellij
  ['tools/zellij.kdl', '.config/zellij/config.kdl'],
  // Codex
  ['tools/codex.toml', '.codex/config.toml'],
  // Organize (file automation)
  ['tools/organize/config.yaml', '.config/organize/config.yaml'],
  // Claude Code statusline
  ['tools/claude/statusline.sh', '.claude/statusline.sh'],
  // Claude Code skills
  ['tools/claude/skills/deslop', '.claude/skills/deslop'],
  ['tools/claude/skills/simplify', '.claude/skills/simplify'],
  ['tools/claude/skills/rams', '.claude/skills/rams'],
  ['tools/claude/skills/knip', '.claude/skills/knip'],
  ['tools/claude/skills/agent-browser', '.claude/skills/agent-browser'],
  ['tools/claude/skills/favicon', '.claude/skills/favicon'],
  ['tools/claude/skills/find-skills', '.claude/skills/find-skills'],
  ['tools/claude/skills/skill-creator', '.claude/skills/skill-creator'],
  ['tools/claude/skills/reclaude', '.claude/skills/reclaude'],
  ['tools/claude/skills/bun', '.claude/skills/bun'],
  ['tools/claude/skills/frontend', '.claude/skills/frontend'],
  // Claude Code agents
  ['tools/claude/agents/security-reviewer.md', '.claude/agents/security-reviewer.md'],
];

const macos_links: [string, string][] = [
  // SSH config (macOS-only - uses UseKeychain, macOS paths)
  ['tools/ssh/config', '.ssh/config'],
  // Tmux (macOS - on Linux, setup.sh writes it directly to avoid conflicts)
  ['tools/tmux.conf', '.tmux.conf'],
  // Karabiner
  ['tools/karabiner.json', '.config/karabiner/karabiner.json'],
  // Cursor
  ['tools/cursor/settings.json', 'Library/Application Support/Cursor/User/settings.json'],
  ['tools/cursor/keybindings.json', 'Library/Application Support/Cursor/User/keybindings.json'],
  // Windsurf
  ['tools/windsurf/settings.json', 'Library/Application Support/Windsurf/User/settings.json'],
  // VSCode
  ['tools/vscode/settings.json', 'Library/Application Support/Code/User/settings.json'],
  // Warp
  ['tools/warp/keybindings.yaml', '.warp/keybindings.yaml'],
  // Organize drain (launchd)
  ['tools/organize/com.organize.drain.plist', 'Library/LaunchAgents/com.organize.drain.plist'],
];

const linux_links: [string, string][] = [
  // Cursor (Linux paths)
  ['tools/cursor/settings.json', '.config/Cursor/User/settings.json'],
  ['tools/cursor/keybindings.json', '.config/Cursor/User/keybindings.json'],
  // Windsurf (Linux paths)
  ['tools/windsurf/settings.json', '.config/Windsurf/User/settings.json'],
  // VSCode (Linux paths)
  ['tools/vscode/settings.json', '.config/Code/User/settings.json'],
];

const all_links = is_macos ? [...links, ...macos_links] : [...links, ...linux_links];

for (const [src, dst] of all_links) {
  const src_path = join(root, src);
  const dst_path = join(home, dst);
  const dst_dir = dirname(dst_path);

  // Create destination directory
  await $`mkdir -p ${dst_dir}`.quiet();

  // Check if destination exists (as file or symlink)
  const exists = await $`test -e ${dst_path} || test -L ${dst_path}`.quiet().nothrow();

  if (exists.exitCode === 0) {
    // Check if it's already correctly linked
    const link = await $`readlink ${dst_path}`.quiet().nothrow();
    if (link.exitCode === 0 && link.text().trim() === src_path) continue;

    // Check if it's a real file (not a symlink)
    const is_symlink = await $`test -L ${dst_path}`.quiet().nothrow();
    if (is_symlink.exitCode !== 0) {
      // It's a real file - backup before replacing
      const backup_path = `${dst_path}.backup`;
      await $`mv ${dst_path} ${backup_path}`.quiet();
      console.log(`[files] ⚠️  backed up existing file: ${dst} -> ${dst}.backup`);
    } else {
      // It's a different symlink - safe to remove
      await $`rm -f ${dst_path}`.quiet();
    }
  }

  // Check if source exists in box
  const src_exists = await $`test -e ${src_path}`.quiet().nothrow();
  if (src_exists.exitCode !== 0) {
    console.log(`[files] ⚠️  skipped (source missing): ${src}`);
    continue;
  }

  // Create symlink
  await $`ln -sfn ${src_path} ${dst_path}`;
  console.log(`[files] ${src} -> ${dst}`);
}

console.log(`[files] linked ${all_links.length} configs`);

// Files that should be MERGED (not symlinked) because the target app rewrites them.
// Symlinks would cause the app to overwrite the source file in git.
// Deep merge ensures our config (hooks, env, etc.) survives app rewrites.
const merges: [string, string][] = [['tools/claude.json', '.claude/settings.json']];

for (const [src, dst] of merges) {
  const src_path = join(root, src);
  const dst_path = join(home, dst);
  const dst_dir = dirname(dst_path);

  await $`mkdir -p ${dst_dir}`.quiet();

  const src_exists = await $`test -e ${src_path}`.quiet().nothrow();
  if (src_exists.exitCode !== 0) {
    console.log(`[files] ⚠️  skipped (source missing): ${src}`);
    continue;
  }

  // Remove existing symlink if present (migration from old symlink approach)
  const is_symlink = await $`test -L ${dst_path}`.quiet().nothrow();
  if (is_symlink.exitCode === 0) {
    await $`rm -f ${dst_path}`.quiet();
  }

  const dst_exists = await $`test -f ${dst_path}`.quiet().nothrow();
  if (dst_exists.exitCode === 0) {
    try {
      const existing = await Bun.file(dst_path).json();
      const source = await Bun.file(src_path).json();
      const merged = { ...existing, ...source, hooks: { ...existing.hooks, ...source.hooks } };
      await Bun.write(dst_path, JSON.stringify(merged, null, 2) + '\n');
      console.log(`[files] ${src} -> ${dst} (merged)`);
    } catch {
      await $`cp ${src_path} ${dst_path}`;
      console.log(`[files] ${src} -> ${dst} (merge failed, copied)`);
    }
  } else {
    await $`cp ${src_path} ${dst_path}`;
    console.log(`[files] ${src} -> ${dst} (copied)`);
  }
}
