{
  stdenv,
  pkg-config,
  libgbm,
  libglvnd,
  embedderHeader,
}:
stdenv.mkDerivation {
  pname = "denial-engine-probe";
  version = "0";
  dontUnpack = true;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libgbm
    libglvnd
  ];
  buildPhase = ''
    cp ${embedderHeader} flutter_embedder.h
    $CC -std=c11 -Wall -Wextra -Werror -O2 -I. \
      ${./tests/engine-probe.c} -o probe \
      $(pkg-config --cflags --libs gbm egl glesv2) -ldl
  '';
  installPhase = ''
    install -Dm755 probe $out/bin/denial-engine-probe
  '';
}
