{
    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
        zig.url = "github:mitchellh/zig-overlay";
    };

    outputs = {self, nixpkgs, zig}:
    let
        system = "x86_64-linux";
        pkgs = import nixpkgs { inherit system; };
    in {
        devShells.${system}.default = pkgs.mkShell {
            buildInputs = [
                zig.packages.${system}."0.15.1"
            ];
        };
    };
}
