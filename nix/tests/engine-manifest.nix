{ runCommand, python3 }:
runCommand "denial-engine-manifest-tests" { nativeBuildInputs = [ python3 ]; } ''
  python3 ${./engine-manifest-test.py} ${../engine-manifest.py}
  touch $out
''
