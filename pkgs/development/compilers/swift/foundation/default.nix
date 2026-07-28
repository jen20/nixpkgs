{
  lib,
  stdenv,
  fetchFromGitHub,
  callPackage,
  cmake,
  ninja,
  swift,
  Dispatch,
  libxml2,
  curl,
}:

let
  sources = callPackage ../sources.nix { };

  # Since Swift 6, swift-corelibs-foundation is a thin shim over the
  # Swift-native swift-foundation, which it (and swift-foundation in turn)
  # pulls in using FetchContent. Provide the checkouts locally so that no
  # network access is needed during the build.
  swift-collections = fetchFromGitHub {
    owner = "apple";
    repo = "swift-collections";
    rev = "1.1.6";
    hash = "sha256-+f9Azcl+NbDvxlMsX0UbT3n87aYaBR1Kjp3rDqoLgkA=";
  };
in
stdenv.mkDerivation {
  pname = "swift-corelibs-foundation";

  inherit (sources) version;
  src = sources.swift-corelibs-foundation;

  outputs = [
    "out"
    "dev"
  ];

  nativeBuildInputs = [
    cmake
    ninja
    swift
  ];
  buildInputs = [
    libxml2
    curl
  ];
  propagatedBuildInputs = [ Dispatch ];

  # ICU now comes from swift-foundation-icu rather than the system copy.
  cmakeFlags = [
    (lib.cmakeFeature "_SwiftFoundation_SourceDIR" "${sources.swift-foundation}")
    (lib.cmakeFeature "_SwiftFoundationICU_SourceDIR" "${sources.swift-foundation-icu}")
    (lib.cmakeFeature "_SwiftCollections_SourceDIR" "${swift-collections}")
  ];

  preConfigure = ''
    # Fails to build with -D_FORTIFY_SOURCE.
    NIX_HARDENING_ENABLE=''${NIX_HARDENING_ENABLE/fortify/}
  '';

  postInstall = ''
    # Split up the output.
    mkdir $dev
    mv $out/lib/swift/${swift.swiftOs} $out/swiftlibs
    mv $out/lib/swift $dev/include
    mkdir $out/lib/swift
    mv $out/swiftlibs $out/lib/swift/${swift.swiftOs}

    # Provide a CMake module. This is primarily used to glue together parts of
    # the Swift toolchain. Modifying the CMake config to do this for us is
    # otherwise more trouble.
    mkdir -p $dev/lib/cmake/Foundation
    export dylibExt="${stdenv.hostPlatform.extensions.sharedLibrary}"
    export swiftOs="${swift.swiftOs}"
    substituteAll ${./glue.cmake} $dev/lib/cmake/Foundation/FoundationConfig.cmake
  '';

  meta = {
    description = "Core utilities, internationalization, and OS independence for Swift";
    mainProgram = "plutil";
    homepage = "https://github.com/apple/swift-corelibs-foundation";
    platforms = lib.platforms.linux;
    license = lib.licenses.asl20;
    teams = [ lib.teams.swift ];
  };
}
