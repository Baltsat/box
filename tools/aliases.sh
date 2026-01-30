# Shell aliases
# Source this file in your .zshrc or .bashrc

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

# --- File system ---
alias ls='ls -G'
alias l='ls -lha'
alias ll='ls -l'
alias la='ls -a'
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
