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
      expose-group-apps = false;
    };

    # Finder settings
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      CreateDesktop = true;
      FXPreferredViewStyle = "Nlsv";  # List view
      _FXShowPosixPathInTitle = true;
    };

    # Trackpad settings
    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = false;
      TrackpadRightClick = true;
    };

    # Global settings
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;  # Enable key repeat
      AppleInterfaceStyleSwitchesAutomatically = true;  # Auto dark mode
      AppleICUForce24HourTime = true;  # 24 hour time
      AppleTemperatureUnit = "Celsius";
      AppleWindowTabbingMode = "always";
      AppleActionOnDoubleClick = "Maximize";
      AppleKeyboardUIMode = 2;  # Full keyboard access
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;
      NSAllowContinuousSpellChecking = false;
    };

    # Screenshot settings
    screencapture = {
      location = "~/Desktop";
      disable-shadow = true;
    };

    # Login window
    loginwindow = {
      GuestEnabled = false;
    };

    # Prevent .DS_Store on network/USB drives
    CustomUserPreferences = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      # Rectangle window manager
      "com.knollsoft.Rectangle" = {
        launchOnLogin = true;
        alternateDefaultShortcuts = true;
      };
    };
  };

  # Homebrew (declarative management)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "none";  # Don't remove unlisted packages
    };

    taps = [
      "homebrew/cask-fonts"
    ];

    # CLI tools (from your brew leaves)
    brews = [
      # Core
      "bash"
      "coreutils"
      "curl"
      "wget"
      "git"
      "git-lfs"
      "gh"

      # Search & navigation
      "ripgrep"
      "fd"
      "fzf"
      "tree"
      "lsd"
      "zoxide"

      # Data processing
      "jq"

      # Development
      "neovim"
      "tmux"
      "bat"
      "htop"
      "tldr"
      "watch"

      # Node/JS
      "node"
      "nvm"
      "pnpm"
      "yarn"

      # Python
      "pipx"
      "python@3.12"

      # Media
      "ffmpeg"
      "ffmpeg@6"
      "imagemagick"
      "graphicsmagick"
      "yt-dlp"

      # Shell
      "starship"
      "thefuck"

      # OCR & documents
      "tesseract"
      "tesseract-lang"
      "ocrmypdf"

      # Containers & infra
      "docker"
      "docker-compose"
      "tailscale"

      # Network tools
      "tcpdump"
      "telnet"
      "lftp"
      "privoxy"

      # Misc tools
      "act"
      "age"
      "sops"
      "repomix"
      "commitizen"
      "sshpass"
      "rlwrap"
      "cmatrix"
    ];

    # GUI applications
    casks = [
      # Productivity
      "raycast"
      "rectangle"
      "alt-tab"
      "bartender"
      "karabiner-elements"
      "maccy"
      "itsycal"

      # Development
      "iterm2"
      "warp"
      "cursor"
      "postman"
      "dbeaver-community"
      "tableplus"
      "sequel-ace"
      "github"
      "mitmproxy"
      "wireshark"
      "ngrok"

      # Browsers
      "google-chrome"
      "firefox-developer-edition"

      # Media
      "iina"
      "vlc"
      "obs"
      "audacity"
      "mixxx"

      # Utilities
      "appcleaner"
      "keka"
      "the-unarchiver"
      "cleanshot"
      "shottr"
      "stats"
      "monitorcontrol"
      "macs-fan-control"
      "betterdisplay"
      "bettertouchtool"
      "lulu"
      "little-snitch"
      "keycastr"
      "numi"
      "latest"

      # Cloud & sync
      "google-drive"
      "dropzone"
      "motrix"

      # Communication
      "slack"
      "discord"
      "zoom"
      "notion"
      "telegram"

      # Design
      "figma"
      "canva"
      "imageoptim"

      # Media server
      "plex-media-server"

      # Reading
      "adobe-acrobat-reader"
      "fbreader"

      # QuickLook plugins
      "qlcolorcode"
      "qlmarkdown"
      "qlstephen"
      "qlvideo"
      "quicklook-json"
      "quicklook-csv"
      "quicklookase"
      "syntax-highlight"
      "webpquicklook"
      "ipynb-quicklook"
      "suspicious-package"

      # Fonts
      "font-fira-code"
      "font-hack-nerd-font"
      "font-bebas-neue"
      "font-inconsolata"
      "font-pt-serif"
      "font-readex-pro"
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
