{ lib, denialSource, rustPlatform, pkg-config, wayland, libglvnd, libxkbcommon, src }:
rustPlatform.buildRustPackage {
  pname = "denial-native-app";
  version = "0.0.0";
  inherit src;
  sourceRoot = "source/native_app";
  cargoLock.lockFile = ${denialSource}/native_app/Cargo.lock;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ wayland libglvnd libxkbcommon ];
  doCheck = true;
  meta = {
    description = "Native Wayland runner for Denial Flutter applications";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
