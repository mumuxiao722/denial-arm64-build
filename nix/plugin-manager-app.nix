{ callPackage, nativeApp, src, sourceLockHash, pluginManagerBackend, version ? "0.0.0+unknown" }:
(callPackage ./native-flutter-app.nix { inherit nativeApp; }) {
  name = "denial-plugin-manager";
  app = "plugin_manager_app";
  inherit src sourceLockHash version;
  pubspecLock = builtins.fromJSON (builtins.readFile ./plugin_manager_app-pubspec-lock.json);
  postInstall = ''
    cat > $out/app/denial-plugin-manager/denial-plugin-manager.installation.json <<'JSON'
    {"schema":1,"backend":"${pluginManagerBackend}/bin/denial-plugins"}
    JSON
  '';
}
