# Shell aliases and functions
# Source this file in your .zshrc or .bashrc

# --- Box Functions ---
box() { cd ~/box && ./setup.sh "$@"; }
secrets() { ~/box/tools/secrets.sh "$@"; }

# --- Navigation ---
alias zshconfig="vim ~/.zshrc"
alias zshsource="source ~/.zshrc"
alias ohmyzsh="cd ~/.oh-my-zsh"
alias sshhome="cd ~/.ssh"
alias sshconfig="vim ~/.ssh/config"
alias gitconfig="vim ~/.gitconfig"

# --- Git ---
alias gits="git status"
alias gitd="git diff"
alias gitl="git lg"
alias gita="git add ."
alias gitc="cz commit"
alias gs="git status"
alias gd="git diff"
alias gl="git lg"
alias ga="git add"

# --- File system (with modern tools if available) ---
if command -v eza &>/dev/null; then
    alias ls='eza'
    alias l='eza -la'
    alias ll='eza -l'
    alias la='eza -a'
    alias tree='eza --tree'
else
    alias ls='ls -G'
    alias l='ls -lha'
    alias ll='ls -l'
    alias la='ls -a'
fi
alias c='clear'
alias t='trash'
alias etrash='empty-trash'

# --- Tools ---
alias loc="npx sloc --format cli-table --format-option head --exclude 'build|\\.svg$|\\.xml' ./"
alias thispath='echo "Working Directory:\n$PWD\n\nReal Working Directory:\n$(pwd -P)"'

# --- macOS Apps ---
alias safari='open -a "Safari"'
alias xcode='open -a "Xcode"'
alias preview='open -a "Preview"'

# --- Claude ---
alias claude='claude --dangerously-skip-permissions'

# --- Tool Initialization (run once on shell startup) ---
init_box_tools() {
    command -v zoxide &>/dev/null && eval "$(zoxide init ${SHELL##*/})"
    command -v direnv &>/dev/null && eval "$(direnv hook ${SHELL##*/})"
    command -v starship &>/dev/null && eval "$(starship init ${SHELL##*/})"
}
