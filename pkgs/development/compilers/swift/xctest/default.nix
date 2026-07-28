{
  lib,
  stdenv,
  callPackage,
  cmake,
  ninja,
  swift,
  Foundation,
  DarwinTools,
}:

let
  sources = callPackage ../sources.nix { };
in
stdenv.mkDerivation {
  pname = "swift-corelibs-xctest";

  inherit (sources) version;
  src = sources.swift-corelibs-xctest;

  outputs = [ "out" ];

  nativeBuildInputs = [
    cmake
    ninja
    swift
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin DarwinTools; # sw_vers
  buildInputs = [ Foundation ];

  preConfigure = ''
    # We can target lower than aarch64-darwin's 11.0 minimum, and some
    # dependants require a lower target. 10.15 is the floor for Swift 6.
    # Harmless on non-Darwin.
    export MACOSX_DEPLOYMENT_TARGET=10.15
  '';

  # Since 6.x the install layout is derived from `swiftc -print-target-info`,
  # which already puts things in `lib/swift/<platform>` with no architecture
  # subdirectory, so no post-install fixup is needed.
  cmakeFlags = lib.optional stdenv.hostPlatform.isDarwin "-DUSE_FOUNDATION_FRAMEWORK=ON";

  meta = {
    description = "Framework for writing unit tests in Swift";
    homepage = "https://github.com/apple/swift-corelibs-xctest";
    platforms = lib.platforms.all;
    license = lib.licenses.asl20;
    teams = [ lib.teams.swift ];
  };
}
