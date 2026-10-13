{ callPackage, nativeApp, src, sourceLockHash, version ? "0.0.0+unknown" }:
(callPackage ./native-flutter-app.nix { inherit nativeApp; }) {
  name = "denial-settings";
  app = "settings_app";
  inherit src sourceLockHash version;
  pubspecLock = builtins.fromJSON (builtins.readFile ./settings_app-pubspec-lock.json);
}
