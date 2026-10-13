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

  inputs.denial.url = "github:denialwm/denial/c56aa2d6e8d70bd87b279e4edd70588c7ec15a6d";

  outputs =
    { self, denial }:
    let
      lib = denial.inputs.nixpkgs.lib;

      # Upstream's own gate, flake.nix:30. Nothing here widens it; see
      # unsupported below.
      validatedSystems = [ "x86_64-linux" ];
      forAllValidatedSystems = lib.genAttrs validatedSystems;

      # Asking for AArch64 has to say why rather than fail with a missing
      # attribute. Upstream README.md:210-211 defers it until the engine source
      # closure is pinned and validated for the architecture, and the deferral
      # is real rather than cautious: nix/flutter-engine.nix:28-32 and
      # nix/flutter-engine-source.nix:21-26,95-97 carry x86_64-only hash tables,
      # so there is no aarch64 dart or engine source hash to substitute.
      #
      # The compositor itself does run on AArch64; this repository builds it for
      # five distributions already.
      unsupported =
        system:
        throw ''
          denial-arm64-builder does not provide Nix packages for ${system}.

          Upstream pins its Nix packaging to x86_64-linux (upstream
          flake.nix:30) and carries no aarch64 engine source hash, so the
          AArch64 engine cannot be built from Nix yet.

          On AArch64, install the packages this repository builds instead:
          denial-deb-arm64, denial-rpm-fedora-arm64, denial-rpm-opensuse-arm64
          and denial-apk-arm64, plus their -plugin-manager counterparts.
        '';
    in
    {
      overlays.default = denial.overlays.default;

      nixosModules.denial = denial.nixosModules.denial;
      nixosModules.default = self.nixosModules.denial;

      # Upstream's set is small enough to pass through whole. checks below is
      # the exception.
      packages = forAllValidatedSystems (system: denial.packages.${system})
        // { aarch64-linux = unsupported "aarch64-linux"; };

      # Deliberately not upstream's full set. engine-manifest, engine-cache and
      # engine-cache-unstable each build the Flutter engine from source, and
      # path-contract needs the assembled package; upstream validates those on
      # every push to its own tree. What is kept here covers what this flake is
      # responsible for: the module wiring into a real NixOS configuration on
      # both of the package sets it pins, the lock consistency of the commit it
      # pins, and whether the resulting system configuration can be built.
      checks = forAllValidatedSystems (
        system:
        let
          mkPkgs = flake: import flake {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          # Same minimal configuration upstream's own module check evaluates
          # (nix/tests/module.nix:28-35), so the two checks describe the same
          # system.
          hostModule =
            nixpkgsFlake: { ... }:
            nixpkgsFlake.lib.nixosSystem {
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
          # Upstream's checks.module passes its own self.nixosModules.denial
          # (flake.nix:119), so reusing that attribute would test upstream's
          # alias rather than this flake's. Its test file takes the module as an
          # argument, so it is pointed at the one re-exported here instead. The
          # mirror of a passthrough is cheap to assert; the module wiring around
          # it is the part that can rot.
          module = import (denial.outPath + "/nix/tests/module.nix") {
            pkgs = mkPkgs denial.inputs.nixpkgs;
            module = self.nixosModules.denial;
            nixosSystem = denial.inputs.nixpkgs.lib.nixosSystem;
          };

          module-unstable = import (denial.outPath + "/nix/tests/module.nix") {
            pkgs = mkPkgs denial.inputs.nixpkgsUnstable;
            module = self.nixosModules.denial;
            nixosSystem = denial.inputs.nixpkgsUnstable.lib.nixosSystem;
          };

          # The module check above only compares strings, so it would still pass
          # if every derivation in the closure were unbuildable. This is the
          # question `nixos-rebuild switch` actually asks: does
          # config.system.build.toplevel come out of the store.
          #
          # Referencing the store path inside a runCommand makes it a build
          # input, so building this check builds the whole system closure. The
          # engine comes from denial.cachix.org, so what is left to compile is
          # the Rust compositor and the Flutter applications.
          nixos-toplevel = let
            evaluated = hostModule denial.inputs.nixpkgs;
          in
          (mkPkgs denial.inputs.nixpkgs).runCommand "denial-nixos-toplevel" { } ''
            ${evaluated.config.system.build.toplevel}
            touch $out
          '';

          # Re-exported rather than rebuilt: this one reads the pinned commit's
          # own lock files, which is what moves when the pin moves.
          locks = denial.checks.${system}.locks;
        }
      ) // { aarch64-linux = unsupported "aarch64-linux"; };

      formatter = forAllValidatedSystems (system: denial.formatter.${system});
    };
}