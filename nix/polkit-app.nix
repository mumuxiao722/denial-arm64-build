{ callPackage, nativeApp, src, sourceLockHash, version ? "0.0.0+unknown" }:
(callPackage ./native-flutter-app.nix { inherit nativeApp; }) {
  name = "denial-polkit-dialog";
  app = "polkit_app";
  inherit src sourceLockHash version;
  pubspecLock = builtins.fromJSON (builtins.readFile ./polkit_app-pubspec-lock.json);
}
