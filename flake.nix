{
  description = "JamZig - ⚡️🛠️ A Zig-fueled implementation for the JAM protocol";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Rust overlay for better Rust toolchain management
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    
    # Flake utils for multi-system support
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        # Rust toolchain with multiple targets
        rustToolchain = pkgs.rust-bin.beta.latest.default.override {
          targets = [
            "x86_64-unknown-linux-gnu"
            "x86_64-unknown-linux-musl"
            "aarch64-unknown-linux-gnu"
            "aarch64-unknown-linux-musl"
            "aarch64-apple-darwin"
            "x86_64-apple-darwin"
            "powerpc64-unknown-linux-gnu"
          ];
          extensions = [ "rust-analyzer" "rust-src" ];
        };
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          name = "jamzig-dev";
          
          buildInputs = with pkgs; [
            # Zig development
            zig
            zls
            
            # Rust development
            rustToolchain
            
            # Additional tools
            qemu
          ];

          shellHook = ''
            echo "Zig + ZLS + Rust development environment"
            echo "Zig version: $(zig version)"
            echo "ZLS version: $(zls version)"
            echo "Rust version: $(rustc --version)"
            echo ""
          '';
        };

      });
}
