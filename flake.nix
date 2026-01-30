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
      username = "konstantinbaltsat";
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
            home-manager.users.${username} = import ./shared.nix;
            home-manager.extraSpecialArgs = { inherit username; };
          }
        ];
        specialArgs = { inherit username; };
      };

      # Linux configuration (ARM)
      homeConfigurations.linux = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-linux";
        };
        modules = [ ./linux.nix ];
        extraSpecialArgs = { inherit username; };
      };

      # Linux configuration (x86_64)
      homeConfigurations.linux-x86 = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
        };
        modules = [ ./linux.nix ];
        extraSpecialArgs = { inherit username; };
      };
    };
}
