{
  description = "silverblue development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };

      treefmtFor =
        system:
        let
          pkgs = pkgsFor system;
        in
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            actionlint.enable = pkgs.stdenv.hostPlatform.isLinux;
            nixfmt.enable = true;
            shellcheck.enable = true;
            shfmt.enable = true;
            yamlfmt = {
              enable = true;
              settings.formatter.retain_line_breaks_single = true;
            };
            zizmor.enable = pkgs.stdenv.hostPlatform.isLinux;
          };
          settings.formatter.shellcheck.excludes = [ "*.envrc" ];
        };
    in
    {
      formatter = forEachSystem (system: (treefmtFor system).config.build.wrapper);

      devShells = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;

          languages = (pkgs.formats.toml { }).generate "languages.toml" {
            language = [
              {
                name = "markdown";
                language-servers = [
                  "marksman"
                  "mpls"
                ];
              }
              {
                name = "dockerfile";
                language-servers = [ "docker-langserver" ];
              }
              {
                name = "yaml";
                language-servers = [
                  "yaml-language-server"
                  "zizmor"
                ];
              }
              {
                name = "nix";
                auto-format = true;
                language-servers = [ "nixd" ];
              }
            ];

            language-server = {
              mpls = {
                command = "mpls";
                args = [
                  "--theme"
                  "dracula"
                  "--browser"
                  "helium"
                  "--enable-emoji"
                ];
              };
              nixd = {
                args = [ "--semantic-tokens=true" ];
                config.nixd.nixpkgs.expr = "import ${nixpkgs} { }";
              };
              yaml-language-server = {
                config.yaml.schemas."https://json.schemastore.org/github-workflow.json" =
                  ".github/workflows/*.{yml,yaml}";
              };
              systemd-lsp.command = "systemd-language-server";
            };
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bashInteractive

              # markdown
              marksman
              mpls

              # containerfile
              dockerfile-language-server
              dockerfmt

              # sh
              bash-language-server
              shellcheck

              # yaml
              yaml-language-server
              yamlfmt

              # actions
              zizmor

              # json
              vscode-langservers-extracted

              # nix
              nixd
              nixfmt

              # systemd
              systemd-language-server
            ];

            shellHook = ''
              mkdir -p .helix
              ln -sf ${languages} .helix/languages.toml
            '';
          };
        }
      );
    };
}
