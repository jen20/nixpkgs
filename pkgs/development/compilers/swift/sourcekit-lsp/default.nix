{
  lib,
  stdenv,
  callPackage,
  pkg-config,
  swift,
  swiftpm,
  swiftpm2nix,
  Dispatch,
  Foundation,
  XCTest,
  sqlite,
  ncurses,
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
  pname = "sourcekit-lsp";

  inherit (sources) version;
  src = sources.sourcekit-lsp;

  nativeBuildInputs = [
    pkg-config
    swift
    swiftpm
  ];
  buildInputs = [
    Foundation
    XCTest
    sqlite
    ncursesInput
  ];

  env.LD_LIBRARY_PATH = lib.optionalString stdenv.hostPlatform.isLinux (
    lib.makeLibraryPath [ Dispatch ]
  );

  configurePhase = generated.configure + ''
    swiftpmMakeMutable indexstore-db
    patch -p1 -d .build/checkouts/indexstore-db -i ${./patches/indexstore-db-macos-target.patch}

    # `OSSignposter` and `OSSignpostID` are not `Sendable` in the SDK this
    # toolchain pins, and `QueueBasedMessageHandler` captures them in
    # `@Sendable` closures. Same package, same fix as swiftpm's build of it.
    swiftpmMakeMutable swift-tools-protocols
    patch -p1 -d .build/checkouts/swift-tools-protocols \
      -i ${../swiftpm/patches/tools-protocols-signposter-sendable.patch}

    # Required to link with swift-corelibs-xctest on Darwin.
    export SWIFTTSC_MACOS_DEPLOYMENT_TARGET=10.15
  '';

  # Build only what `installPhase` installs. A bare `swift-build` also builds
  # `SKTestSupport`, which exists for sourcekit-lsp's own test suite (we do not
  # run it) and which does `import Testing` — satisfying that would mean
  # dragging swift-testing and its macro plugin into this build for no output.
  swiftpmFlags = [ "--product sourcekit-lsp" ];

  # TODO: BuildServerBuildSystemTests fails
  #doCheck = true;

  installPhase = ''
    binPath="$(swiftpmBinPath)"
    mkdir -p $out/bin
    cp $binPath/sourcekit-lsp $out/bin/
  '';

  # Canary to verify output of our Swift toolchain does not depend on the Swift
  # compiler itself. (Only its 'lib' output.)
  disallowedRequisites = [ swift.swift ];

  meta = {
    description = "Language Server Protocol implementation for Swift and C-based languages";
    mainProgram = "sourcekit-lsp";
    homepage = "https://github.com/apple/sourcekit-lsp";
    platforms = with lib.platforms; linux ++ darwin;
    license = lib.licenses.asl20;
    teams = [ lib.teams.swift ];
  };
}
