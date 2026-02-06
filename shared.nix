{
  pkgs,
  config,
  lib,
  ...
}:

{
  # Use mkDefault so linux.nix can override with its own version
  home.stateVersion = lib.mkDefault "24.11";
  home.enableNixpkgsReleaseCheck = false;

  # Packages installed for the user
  home.packages = with pkgs; [
    # Core CLI
    coreutils
    curl
    wget
    git
    git-lfs
    gh
    gnupg

    # Search & Navigation
    ripgrep
    fd
    fzf
    tree
    zoxide
    eza

    # Data Processing
    jq
    yq
    duckdb

    # Development
    neovim
    tmux
    zellij
    blesh # bash line editor with autocomplete
    bat
    htop
    watch
    tldr
    delta
    bun

    # Formatters
    nixfmt
    shfmt
    shellcheck
    taplo
    nodePackages.prettier
    ruff

    # Media
    ffmpeg
    imagemagick
    yt-dlp

    # Shell
    starship
    direnv
    nix-direnv

    # Build
    gnumake

    # Archive
    xz
    zstd

    # Secrets
    age
    sops
  ];

  # Suppress login message
  home.file.".hushlogin".text = "";

  # Symlink config files after setup
  home.activation.linkFiles = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.bun}/bin/bun $HOME/box/script/files.ts || true
  '';

  # Install pre-commit hook
  home.activation.installPrecommit = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "$HOME/box/script/precommit.sh" ]; then
      cd $HOME/box && source script/precommit.sh && install_hook || true
    fi
  '';

  # Let home-manager manage itself
  programs.home-manager.enable = true;
}
