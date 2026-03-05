{ pkgs, username, ... }:

{
  imports = [ ./shared.nix ];

  home = {
    username = username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";
  };

  # Linux-specific packages
  home.packages = with pkgs; [
    htop
    tree
    # Keep mosh version deterministic through flake.lock pinned nixpkgs.
    mosh
  ];
}
