{
  lib,
  stdenv,
  callPackage,
  cmake,
  ninja,
  swift,
  Foundation,
  Dispatch,
  DarwinTools,
  replaceVars,
}:

let
  sources = callPackage ../sources.nix { };

  sharedLibraryExt = stdenv.hostPlatform.extensions.sharedLibrary;

  # Where the macro plugin ends up, and so where `-plugin-path` has to point:
  # a `testing` subdirectory on Darwin, the plain plugin directory elsewhere.
  # From `Sources/TestingMacros/CMakeLists.txt`.
  pluginSubdir =
    if stdenv.hostPlatform.isDarwin then "lib/swift/host/plugins/testing" else "lib/swift/host/plugins";

  # The 14 swift-syntax modules the compiler installs, from
  # `SWIFT_SYNTAX_MODULES` in swift's `lib/SwiftSyntax/CMakeLists.txt`.
  swiftSyntaxModules = [
    "SwiftBasicFormat"
    "SwiftIfConfig"
    "SwiftParser"
    "SwiftParserDiagnostics"
    "SwiftDiagnostics"
    "SwiftSyntax"
    "SwiftOperators"
    "SwiftSyntaxBuilder"
    "SwiftSyntaxMacros"
    "SwiftSyntaxMacroExpansion"
    "SwiftCompilerPluginMessageHandling"
    "SwiftIDEUtils"
    "SwiftRefactor"
    "SwiftLibraryPluginProvider"
  ];

  swiftSyntaxLibDir = "${swift.swift.lib}/lib/swift/host";
in
stdenv.mkDerivation {
  pname = "swift-testing";

  inherit (sources) version;
  src = sources.swift-testing;

  outputs = [ "out" ];

  nativeBuildInputs = [
    cmake
    ninja
    swift
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin DarwinTools; # sw_vers

  # On Darwin these come from the SDK; upstream only looks for them elsewhere.
  buildInputs = lib.optionals (!stdenv.hostPlatform.isDarwin) [
    Dispatch
    Foundation
  ];

  # The macro plugin has to be built as a shared library, and upstream only
  # does that when `find_package(SwiftSyntax)` succeeds — otherwise it fetches
  # swift-syntax and builds the plugin as an *executable*, which the compiler
  # then rejects at use time with "produced malformed response", so `#expect`
  # does not work at all. The plugin also genuinely has to link the toolchain's
  # own copy of swift-syntax: it is loaded in-process, and the compiler checks
  # each macro type against the `Macro` protocol from the swift-syntax that
  # `libSwiftLibraryPluginProvider` links. A plugin carrying its own copy
  # builds and loads, but every macro is then rejected with "is not a valid
  # macro implementation type".
  #
  # No toolchain ships a `SwiftSyntaxConfig.cmake` — swift's
  # `lib/SwiftSyntax/CMakeLists.txt` and swift-syntax's own
  # `cmake/modules/CMakeLists.txt` both generate it with `export()`, which only
  # writes into a build tree — so write one describing what is installed.
  preConfigure = ''
    syntaxCMakeDir="$NIX_BUILD_TOP/swift-syntax-cmake"
    mkdir -p "$syntaxCMakeDir"
    cat > "$syntaxCMakeDir/SwiftSyntaxConfig.cmake" <<EOF
    set(_SwiftSyntax_libdir "${swiftSyntaxLibDir}")
    set(_SwiftSyntax_modules ${lib.concatStringsSep " " swiftSyntaxModules})

    set(_SwiftSyntax_all_libs)
    foreach(_module IN LISTS _SwiftSyntax_modules)
      list(APPEND _SwiftSyntax_all_libs
           "\''${_SwiftSyntax_libdir}/lib\''${_module}${sharedLibraryExt}")
    endforeach()

    # Every module is linked whenever any one of them is used. The real export
    # file records each module's own dependencies, but those cannot be
    # recovered from an installed toolchain, and getting them wrong fails at
    # link time: these modules refer to each other's generic
    # protocol-extension members, which autolinking does not pick up. Over-
    # linking costs a few extra load commands in one macro plugin.
    foreach(_module IN LISTS _SwiftSyntax_modules)
      if(NOT TARGET SwiftSyntax::\''${_module})
        add_library(SwiftSyntax::\''${_module} SHARED IMPORTED GLOBAL)
        set_target_properties(SwiftSyntax::\''${_module} PROPERTIES
          IMPORTED_LOCATION "\''${_SwiftSyntax_libdir}/lib\''${_module}${sharedLibraryExt}"
          INTERFACE_INCLUDE_DIRECTORIES "\''${_SwiftSyntax_libdir}"
          INTERFACE_LINK_DIRECTORIES "\''${_SwiftSyntax_libdir}"
          INTERFACE_LINK_LIBRARIES "\''${_SwiftSyntax_all_libs}")
      endif()
    endforeach()

    set(SwiftSyntax_FOUND TRUE)
    EOF

    cmakeFlagsArray+=( "-DSwiftSyntax_DIR=$syntaxCMakeDir" )
  '';

  cmakeFlags = [
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
  ];

  # The macro plugin is built by a nested `ExternalProject` whose install prefix
  # upstream hardcodes to `CMAKE_BINARY_DIR` (`Sources/CMakeLists.txt`), so it
  # lands in the build tree rather than in `$out`. Copy it across, keeping the
  # path a toolchain would use.
  postInstall = ''
    install -Dm755 ${pluginSubdir}/libTestingMacros${sharedLibraryExt} \
      $out/${pluginSubdir}/libTestingMacros${sharedLibraryExt}

    # Upstream installs only the textual `.swiftinterface`. Swift 6.3.3 emits
    # `@_optimize(none)` on a stored property into it, and then refuses to
    # re-parse its own output ("'@_optimize(none)' attribute cannot be applied
    # to stored properties"), so every `import Testing` fails. Install the
    # binary module as well — it is preferred over the interface, so this
    # side-steps the bug while leaving the interface in place.
    moduleDir=$out/${swift.swiftModuleSubdir}/testing/Testing.swiftmodule
    triple=$(basename "$(echo "$moduleDir"/*.swiftinterface | cut -d' ' -f1)" .swiftinterface)
    install -m644 swift/Testing.swiftmodule "$moduleDir/$triple.swiftmodule"
  '';

  # Modules and the macro plugin live in subdirectories the generic Swift
  # wrapper hook does not look in, so add them here.
  setupHook = replaceVars ./setup-hook.sh {
    moduleSubdir = "${swift.swiftModuleSubdir}/testing";
    libSubdir = "${swift.swiftLibSubdir}/testing";
    inherit pluginSubdir;
  };

  meta = {
    description = "Modern, expressive testing package for Swift";
    homepage = "https://github.com/swiftlang/swift-testing";
    platforms = lib.platforms.all;
    license = lib.licenses.asl20;
    teams = [ lib.teams.swift ];
  };
}
