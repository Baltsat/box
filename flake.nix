{
  description = "box — nix config for macos and linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-darwin,
      ...
    }:
    let
      # Default username - override via BOX_USER env var in setup.sh
      defaultUsername = "konstantinbaltsat";

      # Helper to create home-manager config for any user
      mkHomeConfig = { system, username }: home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        modules = [ ./linux.nix ];
        extraSpecialArgs = { inherit username; };
      };
    in
    {
      # macOS configuration (Apple Silicon)
      darwinConfigurations.macos = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./macos.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${defaultUsername} = import ./shared.nix;
            home-manager.extraSpecialArgs = { username = defaultUsername; };
          }
        ];
        specialArgs = { username = defaultUsername; };
      };

      # Linux configurations - default user
      homeConfigurations.linux = mkHomeConfig {
        system = "aarch64-linux";
        username = defaultUsername;
      };

      homeConfigurations.linux-x86 = mkHomeConfig {
        system = "x86_64-linux";
        username = defaultUsername;
      };

      # Linux configurations - generic (uses $USER)
      # Usage: home-manager switch --flake .#linux-generic-x86
      homeConfigurations.linux-generic = mkHomeConfig {
        system = "aarch64-linux";
        username = builtins.getEnv "USER";
      };

      homeConfigurations.linux-generic-x86 = mkHomeConfig {
        system = "x86_64-linux";
        username = builtins.getEnv "USER";
      };
    };
}
