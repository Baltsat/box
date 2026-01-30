#!/usr/bin/env bash
# Shell aliases and functions for box
# Source this file in your .zshrc or .bashrc

# === Box Functions ===
box() { cd ~/box && ./setup.sh "$@"; }
secrets() { ~/box/tools/secrets.sh "$@"; }

# === Directory Navigation ===
alias zshconfig="vim ~/.zshrc"
alias zshsource="source ~/.zshrc"
alias ohmyzsh="cd ~/.oh-my-zsh"
alias sshhome="cd ~/.ssh"
alias sshconfig="vim ~/.ssh/config"
alias gitconfig="vim ~/.gitconfig"

# === Git Shortcuts ===
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline -20"
alias ga="git add"
alias gaa="git add ."
alias gc="git commit"
alias gp="git push"
alias gpf="git push -f"
alias gpl="git pull"
alias gco="git checkout"
alias gb="git branch"
alias gm="git merge"
alias gr="git restore"
alias grs="git restore --staged"

# Git log with graph
alias gitl="git log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

# Quick commit and push
gg() {
    local msg="${*:-update}"
    git add . && git commit -m "$msg" && git push
}

# === File Listing (eza/ls) ===
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias l='eza -la'
    alias ll='eza -laah --git --time-style=relative --sort=modified'
    alias la='eza -a'
    alias lt='eza --tree'
    alias ld='eza -laah --git --time-style=relative --sort=modified --only-dirs'
    alias lf='eza -laah --git --time-style=relative --sort=modified --only-files'
    tree() {
        local path="." depth=2
        for arg in "$@"; do
            [[ "$arg" =~ ^[0-9]+$ ]] && depth="$arg" || path="$arg"
        done
        eza --tree -a -L "$depth" "$path"
    }
else
    alias ls='ls -G'
    alias l='ls -lha'
    alias ll='ls -l'
    alias la='ls -a'
fi

# === Common Operations ===
alias c='clear'
alias t='trash'
alias etrash='empty-trash'
alias py='python3'
alias loc="npx sloc --format cli-table --format-option head --exclude 'build|\\.svg$|\\.xml' ./"
alias thispath='echo "Working Directory:\n$PWD\n\nReal Working Directory:\n$(pwd -P)"'

# === macOS Apps ===
alias safari='open -a "Safari"'
alias xcode='open -a "Xcode"'
alias preview='open -a "Preview"'

# === Claude ===
alias claude='claude --dangerously-skip-permissions'

# === Zoxide (smart cd) ===
if command -v zoxide &>/dev/null; then
    alias z='zoxide query'
    alias zi='zoxide query -i'
fi

# === Direnv ===
alias da='direnv allow .'

# === Nix ===
# Quick nix shell with packages
ns() {
    local pkgs=()
    for arg in "$@"; do
        pkgs+=("nixpkgs#$arg")
    done
    nix shell --impure "${pkgs[@]}"
}

# === Utility Functions ===

# Copy all files content to clipboard (for sharing with AI)
displayall() {
    (tree -I "node_modules|dist" && echo "\n\nFile content:" && find . -type f ! -path "./dist/*" ! -path "./.git/*" ! -path "./node_modules/*" -exec sh -c 'echo "\n--- {} ---"; cat "{}"' \;) | pbcopy
}

# Find repos in home directory
repos() {
    fd -H -t d '^\.git$' ~ --max-depth 2 2>/dev/null | sed 's/\/\.git\/$//';
}

# === Tool Initialization (call once in shell rc) ===
init_box_tools() {
    command -v zoxide &>/dev/null && eval "$(zoxide init ${SHELL##*/})"
    command -v direnv &>/dev/null && eval "$(direnv hook ${SHELL##*/})"
    command -v starship &>/dev/null && eval "$(starship init ${SHELL##*/})"
    command -v fzf &>/dev/null && eval "$(fzf --${SHELL##*/})"
}
