{
  lib,
  stdenv,
  callPackage,
  swift,
  swiftpm,
  swiftpm2nix,
  Foundation,
  XCTest,
  sqlite,
  ncurses,
  clang,
  replaceVars,
}:
let
  sources = callPackage ../sources.nix { };
  generated = swiftpm2nix.helpers ./generated;

  # On Darwin, we only want ncurses in the linker search path, because headers
  # are part of libsystem. Adding its headers to the search path causes strange
  # mixing and errors.
  # TODO: Find a better way to prevent this conflict.
  ncursesInput = if stdenv.hostPlatform.isDarwin then ncurses.out else ncurses;
in
stdenv.mkDerivation {
  pname = "swift-driver";

  inherit (sources) version;
  src = sources.swift-driver;

  nativeBuildInputs = [
    swift
    swiftpm
  ];
  buildInputs = [
    Foundation
    XCTest
    sqlite
    ncursesInput
  ];

  patches = [
    ./patches/disable-catalyst.patch
    (replaceVars ./patches/linux-fix-linking.patch {
      inherit clang;
    })
    # Our wrappers pass injected flags through a response file created with a
    # process substitution, which swift-driver cannot read. Supersedes the
    # still-unmerged https://github.com/swiftlang/swift-driver/pull/1197,
    # which fixes only half of it.
    ./patches/response-file-special-files.patch
    # swift-driver is its own derivation here, so it cannot find the compiler's
    # plugins by looking next to itself.
    ./patches/toolchain-root-from-frontend.patch
    # Prevent a warning about SDK directories we don't have.
    (replaceVars ./patches/prevent-sdk-dirs-warnings.patch {
      inherit (builtins) storeDir;
    })
  ];

  configurePhase = generated.configure;

  # TODO: Tests depend on indexstore-db being provided by an existing Swift
  # toolchain. (ie. looks for `../lib/libIndexStore.so` relative to swiftc.
  #doCheck = true;

  # TODO: Darwin-specific installation includes more, but not sure why.
  installPhase = ''
    binPath="$(swiftpmBinPath)"
    mkdir -p $out/bin
    for executable in swift-driver swift-help swift-build-sdk-interfaces; do
      cp $binPath/$executable $out/bin/
    done
  '';

  meta = {
    description = "Swift compiler driver";
    homepage = "https://github.com/apple/swift-driver";
    platforms = with lib.platforms; linux ++ darwin;
    license = lib.licenses.asl20;
    teams = [ lib.teams.swift ];
  };
}
