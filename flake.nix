{
  description = "fizzy-oidc — OIDC single sign-on for Fizzy (Rails engine gem)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          # Fizzy pins Ruby 3.4.8; nixpkgs carries the latest 3.4 patch release.
          # The native gems (sqlite3, psych, openssl) build against the libraries below.
          packages = [ pkgs.ruby_3_4 pkgs.sqlite pkgs.libyaml pkgs.openssl pkgs.pkg-config ];
        };
      });
    };
}
