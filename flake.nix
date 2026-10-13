{
  description = "Denial Nix packaging, pinned to upstream v0.5.0";

  # A flake's nixConfig is not inherited when the flake is consumed as an
  # input, so upstream's denial.cachix.org settings have to be repeated here or
  # every engine lookup misses. Same two values as upstream flake.nix:8-11.
  nixConfig = {
    extra-substituters = [ "https://denial.cachix.org" ];
    extra-trusted-public-keys = [
      "denial.cachix.org-1:wd8YTnvPmugFrtdMJWtR1XdVknR3/g2nmBJkT+vAruo="
    ];
  };

  inputs = {
    # v0.5.0. A commit rather than the tag, so the reviewed text says exactly
    # what was reviewed; it is what the annotated, PGP-signed tag points at.
    denial.url = "github:denialwm/denial/c56aa2d6e8d70bd87b279e4edd70588c7ec15a6d";

    # A path input, not a flake. The overlay reads the taskbar plugin out of it
    # directly; upstream flake.nix:19 pins the same commit.
    denialPlugins = {
      url = "github:denialwm/denial-plugins/4b7adf998852b09b9a91c1cfab48be58debf2e80";
      flake = false;
    };
  };

  outputs =
    { self, denial, denialPlugins }:
    let
      # Upstream's pinned package sets. nixpkgs is not followed: its README says
      # following the host input also changes the engine cache key.
      nixpkgs = denial.inputs.nixpkgs;
      nixpkgsUnstable = denial.inputs.nixpkgsUnstable;

      lib = nixpkgs.lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs supportedSystems;

      # The fork in ./nix. Upstream pins its own Nix packaging to x86_64-linux
      # (upstream flake.nix:30); this one carries the AArch64 port, which needed
      # a dart and engine source hash that upstream has never had. See
      # patches/nix-aarch64.diff for the whole delta.
      localOverlay =
        import ./nix/overlay.nix {
          version = "0.0.0+${denial.rev}";
          buildIdentity = "nix.${denial.shortRev}";
          sourceRevision = denial.rev;
          denialSource = denial.outPath;
          flutterNixpkgs = nixpkgs;
          pluginCollection = denialPlugins;
        };

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ localOverlay ];
        };
      mkUnstablePkgs =
        system:
        import nixpkgsUnstable {
          inherit system;
          overlays = [ localOverlay ];
        };
    in
    {
      overlays.default = localOverlay;

      nixosModules.denial =
        { config, lib, ... }:
        {
          imports = [ ./nix/module.nix ];
          nixpkgs.overlays = lib.mkIf config.programs.denial.enable [ localOverlay ];
        };
      nixosModules.default = self.nixosModules.denial;

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          unstablePkgs = mkUnstablePkgs system;
          maintenance = pkgs.callPackage ./nix/flutter-engine.nix {
            maintenanceOnly = true;
            flutterNixpkgs = nixpkgs;
          };
        in
        {
          default = pkgs.denial;
          denial = pkgs.denial;
          denial-plugin-manager = pkgs.denialPluginManager;
          denial-unstable = unstablePkgs.denial;

          denial-flutter = pkgs.denialFlutter;
          denial-flutter-engine = pkgs.denialFlutter.engine;
          denial-flutter-engine-raw = pkgs.denialFlutter.pinnedRawEngine;
          denial-flutter-engine-source-build = pkgs.denialFlutter.hostSourceEngine;

          denial-flutter-engine-source = maintenance.engineSource;
          denial-flutter-depot-tools-source = maintenance.depotToolsSource;
          denial-flutter-framework-source = maintenance.fetchedFlutter;
          denial-flutter-dart = maintenance.dart;
        }
      );

      # engine-manifest and engine-cache build the engine from source and
      # path-contract needs the assembled package. Kept out of the default run
      # so `nix flake check` stays an integration check rather than a second
      # full build; ask for them by name.
      checks = forAllSystems (
        system:
        let
          mkModuleCheck =
            nixpkgsFlake:
            import ./nix/tests/module.nix {
              pkgs = import nixpkgsFlake {
                inherit system;
                overlays = [ localOverlay ];
              };
              module = self.nixosModules.denial;
              nixosSystem = nixpkgsFlake.lib.nixosSystem;
            };
          evaluated = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.denial
              {
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "none";
                  fsType = "tmpfs";
                };
                programs.denial.enable = true;
                system.stateVersion = "26.05";
              }
            ];
          };
        in
        {
          module = mkModuleCheck nixpkgs;
          module-unstable = mkModuleCheck nixpkgsUnstable;

          # `nixos-rebuild switch` asks whether system.build.toplevel leaves the
          # store. The module check above compares strings and would pass with
          # an unbuildable closure. Referenced as a link target so it is a build
          # input; a bare interpolation would leave the path alone on the first
          # line of the script and the shell would try to execute it.
          nixos-toplevel = (mkPkgs system).runCommand "denial-nixos-toplevel" { } ''
            mkdir -p $out
            ln -s ${evaluated.config.system.build.toplevel} $out/system
          '';

          locks = (mkPkgs system).callPackage ./nix/tests/locks.nix {
            source = denial.outPath;
            flutterSource = (mkPkgs system).denialFlutter.flutterSource;
            pluginCollection = denialPlugins;
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}