{ pkgs, username, ... }:

{
  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System packages available to all users
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
  ];

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # macOS system preferences
  system.defaults = {
    # Dock settings
    dock = {
      autohide = true;
      autohide-time-modifier = 0.25;
      show-recents = false;
      tilesize = 48;
      largesize = 30;
      magnification = true;
      mineffect = "genie";
      minimize-to-application = false;
      mouse-over-hilite-stack = true;
      orientation = "bottom";
      launchanim = true;
    };

    # Finder settings
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      CreateDesktop = true;
    };

    # Trackpad settings
    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

    # Global settings
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 30;
      KeyRepeat = 5;
      "com.apple.swipescrolldirection" = true;
    };
  };

  # Homebrew (declarative management)
  # Note: Homebrew must be installed separately first
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";  # Don't remove unlisted packages
    };

    # CLI tools
    brews = [
      "bat"
      "fzf"
      "gh"
      "git"
      "git-lfs"
      "htop"
      "jq"
      "neovim"
      "node"
      "nvm"
      "pnpm"
      "ripgrep"
      "starship"
      "thefuck"
      "tldr"
      "tmux"
      "tree"
      "watch"
      "wget"
      "yarn"
      "yt-dlp"
      "zoxide"
    ];

    # GUI applications
    casks = [
      # Productivity
      "raycast"
      "rectangle"
      "alt-tab"
      "bartender"
      "karabiner-elements"

      # Development
      "iterm2"
      "warp"
      "cursor-cli"
      "postman"
      "dbeaver-community"
      "tableplus"

      # Browsers
      "google-chrome"
      "firefox-developer-edition"

      # Media
      "iina"
      "vlc"
      "obs"

      # Utilities
      "appcleaner"
      "keka"
      "the-unarchiver"
      "cleanshot"
      "shottr"
      "maccy"
      "stats"
      "monitorcontrol"
      "macs-fan-control"

      # Communication
      "slack"
      "discord"
      "zoom"
      "notion"

      # Design
      "figma"

      # QuickLook plugins
      "qlcolorcode"
      "qlmarkdown"
      "qlstephen"
      "quicklook-json"
      "syntax-highlight"

      # Fonts
      "font-fira-code"
      "font-hack-nerd-font"
    ];
  };

  # User configuration
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Required for nix-darwin
  system.stateVersion = 5;
}
