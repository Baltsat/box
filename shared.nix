{ pkgs, username, config, ... }:

{
  home.stateVersion = "24.05";

  # Packages installed for the user
  home.packages = with pkgs; [
    # === Core CLI Tools ===
    coreutils
    curl
    wget
    git
    git-lfs
    gh
    gnupg

    # === Search & Navigation ===
    ripgrep
    fd
    fzf
    tree
    zoxide
    eza  # modern ls replacement

    # === Data Processing ===
    jq
    yq
    duckdb

    # === Development ===
    neovim
    tmux
    bat
    htop
    watch
    tldr
    delta  # better git diffs
    bun

    # === Media Processing ===
    ffmpeg
    imagemagick
    yt-dlp

    # === Shell ===
    starship
    pay-respects  # thefuck replacement

    # === Build Tools ===
    gnumake

    # === Archive ===
    xz
    zstd

    # === Secrets ===
    age
    sops
  ];

  # Symlink config files after setup
  home.activation.linkFiles = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    if command -v bun &>/dev/null && [ -f "$HOME/box/script/files.ts" ]; then
      ${pkgs.bun}/bin/bun "$HOME/box/script/files.ts" || true
    fi
  '';

  # Git configuration
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = "Konstantin Baltsat";
        email = "baltsat2002@mail.ru";
      };
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      credential.helper = "osxkeychain";
      alias = {
        lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };
    };
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      command_timeout = 1000;
      add_newline = false;
    };
  };

  # Zoxide (smart cd)
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # fzf (fuzzy finder)
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # Direnv (per-directory environments)
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Let home-manager manage itself
  programs.home-manager.enable = true;
}
