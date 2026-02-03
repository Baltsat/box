{ pkgs, username, ... }:

{
  # Primary user for user-specific settings
  system.primaryUser = username;

  # Nix settings (managed by Determinate, not nix-darwin)
  nix.enable = false;

  # System packages (minimal, rest via home-manager)
  environment.systemPackages = with pkgs; [
    vim
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
      tilesize = 32;  # current system value
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
      ShowPathbar = false;  # current system
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      CreateDesktop = true;
      FXPreferredViewStyle = "icnv";  # icon view (current system)
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
      InitialKeyRepeat = 30;  # current system (lower = faster)
      KeyRepeat = 5;  # current system (lower = faster)
      ApplePressAndHoldEnabled = false;  # Enable key repeat
      AppleInterfaceStyleSwitchesAutomatically = true;  # Auto dark mode
      AppleICUForce24HourTime = true;  # 24 hour time
      AppleTemperatureUnit = "Celsius";
      AppleWindowTabbingMode = "always";
      AppleKeyboardUIMode = 2;  # Full keyboard access
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = true;  # current system
      NSAutomaticDashSubstitutionEnabled = true;  # current system
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = true;  # current system
      NSAutomaticInlinePredictionEnabled = false;
    };

    # Screenshot settings
    screencapture = {
      location = "~/Downloads";
      disable-shadow = true;
      type = "jpg";
      show-thumbnail = true;
    };

    # Menu bar clock
    menuExtraClock = {
      Show24Hour = true;
      ShowDate = 2;  # Always show date
      ShowDayOfWeek = false;
      ShowSeconds = false;
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
      # Safari
      "com.apple.Safari" = {
        AutoOpenSafeDownloads = false;
        CommandClickMakesTabs = true;
        ShowFullURLInSmartSearchField = true;
      };
      # Terminal
      "com.apple.Terminal" = {
        FocusFollowsMouse = true;
        "Default Window Settings" = "Pro";
      };
    };
  };

  # Homebrew (declarative management)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
    };

    # CLI tools (macOS-specific or not in nix)
    # Core CLI tools are in shared.nix (nix) for cross-platform support
    brews = [
      # Git extras (delta/gitui better via brew)
      "git-delta"
      "gitui"
      "lsd"  # ls alternative

      # Node/JS ecosystem (brew manages versions better)
      "node"
      "node@22"
      "nvm"
      "pnpm"
      "yarn"

      # Python (brew manages versions better)
      "pipx"
      "python@3.12"
      "python@3.10"
      "virtualenv"
      "fastapi"
      "jupyterlab"

      # Shell extras
      "thefuck"

      # OCR & documents (macOS specific libs)
      "tesseract"
      "tesseract-lang"
      "ocrmypdf"

      # Containers & infra (macOS integration)
      "docker"
      "docker-compose"
      "tailscale"
      "cloudflared"

      # Network tools
      "tcpdump"
      "telnet"
      "lftp"
      "privoxy"

      # Misc tools
      "act"
      "sops"  # needed for precommit hook
      "repomix"
      "commitizen"
      "sshpass"
      "rlwrap"
      "cmatrix"

      # Security/networking
      "aircrack-ng"
      "hashcat"
      "hcxtools"

      # Remote development
      "coder"

      # Additional runtimes
      "php"

      # Media (macOS specific libs)
      "ffmpeg@6"  # specific version
      "graphicsmagick"
      "telegram-downloader"
      "vips"
      "gstreamer"

      # Atlassian CLI
      "atlassian/acli/acli"

      # Torrents
      "autobrr"
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
      "wireshark-app"
      "ngrok"

      # Browsers
      "google-chrome"

      # Media
      "iina"
      "vlc"
      "obs"
      "audacity"

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

      # Window managers & input
      "amethyst"
      "middleclick"
      "multitouch"
      "intellidock"
      "mission-control-plus"
      "scroll-reverser"

      # Development extras
      "cursor-cli"
      "chromedriver"
      "sf-symbols"

      # Utilities
      "apparency"
      "clop"
      "context"
      "find-empty-folders"
      "glance-chamburr"
      "hazeover"
      "one-switch"
      "pally"
      "pdf-squeezer"
      "pine"
      "reminders-menubar"
      "serverbuddy"
      "sip-app"
      "swift-quit"
      "table-tool"
      "tempbox"
      "time-out"
      "unclack"

      # Network & VPN
      "protonvpn"
      "network-radar"
      "vibetunnel"

      # Media
      "droid"
      "flow-desktop"
      "riverside-studio"
      "macmediakeyforwarder"

      # Firefox
      "firefox@developer-edition"

      # DJ software snapshot
      "mixxx@snapshot"

      # UI tools
      "ui-tars"


      # Yandex
      "yandex"
      "yandex-music-unofficial"
    ];
  };

  # User configuration
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Additional macOS defaults (not available in nix-darwin)
  system.activationScripts.macosDefaults.text = ''
    if command -v bun &>/dev/null; then
      bun ${./script/macos.ts} || true
    fi
  '';

  # Required for nix-darwin
  system.stateVersion = 5;
}
