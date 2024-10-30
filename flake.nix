{
  description = "JamZig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";

    # Overlays
    zig.url = "github:mitchellh/zig-overlay";
    rust.url = "github:oxalica/rust-overlay";

    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    overlays = [
      # Other overlays
      (final: prev: {
        zigpkgs = inputs.zig.packages.${prev.system};
        rustpkgs = inputs.rust.packages.${prev.system};
      })
    ];

    # Our supported systems are the same supported systems as the Zig binaries
    systems = builtins.attrNames inputs.zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system;};
      in rec {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            zigpkgs.master
            rustpkgs.rust-beta
          ];

          # shellHook = "exec zsh";
        
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;

        # For shell.nix eems to need it
        packages.default = self.devShells.${system}.default;
      }
    );
}
