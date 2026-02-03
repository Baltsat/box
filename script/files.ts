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
const links: [string, string][] = [
  // Shell & prompt
  ['tools/starship.toml', '.config/starship.toml'],
  ['tools/gitconfig', '.gitconfig'],
  ['tools/aliases.sh', '.config/box/aliases.sh'],
  // Tmux
  ['tools/tmux.conf', '.tmux.conf'],
  // SSH
  ['tools/ssh/config', '.ssh/config'],
  // GitHub CLI
  ['tools/gh/config.yml', '.config/gh/config.yml'],
  // Claude global instructions
  ['tools/CLAUDE.md', '.claude/CLAUDE.md'],
  // Zed
  ['tools/zed/settings.json', '.config/zed/settings.json'],
  // Zellij
  ['tools/zellij.kdl', '.config/zellij/config.kdl'],
  // Codex
  ['tools/codex.toml', '.codex/config.toml'],
];

const macos_links: [string, string][] = [
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
  // Claude Code
  ['tools/claude.json', '.claude/settings.json'],
];

const all_links = is_macos ? [...links, ...macos_links] : links;

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
