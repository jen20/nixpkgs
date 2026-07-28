{
  lib,
  stdenv,
  callPackage,
  cmake,
  ninja,
  git,
  swift,
  swiftpm2nix,
  Foundation,
  XCTest,
  pkg-config,
  sqlite,
  ncurses,
  replaceVars,
  runCommandLocal,
  makeWrapper,
  DarwinTools, # sw_vers
  cctools, # vtool
  xcbuild,
}:

let

  inherit (swift)
    swiftOs
    swiftModuleSubdir
    swiftStaticModuleSubdir
    ;
  sharedLibraryExt = stdenv.hostPlatform.extensions.sharedLibrary;

  sources = callPackage ../sources.nix { };
  generated = swiftpm2nix.helpers ./generated;
  cmakeGlue = callPackage ./cmake-glue.nix { };

  # Common attributes for the bootstrap swiftpm and the final swiftpm.
  commonAttrs = {
    inherit (sources) version;
    src = sources.swift-package-manager;
    nativeBuildInputs = [ makeWrapper ];
    # Required at run-time for the host platform to build package manifests.
    propagatedBuildInputs = [ Foundation ];
    patches = [
      ./patches/cmake-disable-rpath.patch
      ./patches/disable-index-store.patch
      ./patches/disable-sandbox.patch
      ./patches/disable-xctest.patch
      ./patches/fix-clang-cxx.patch
      ./patches/nix-pkgconfig-vars.patch
      (replaceVars ./patches/fix-stdlib-path.patch {
        inherit (builtins) storeDir;
        swiftLib = swift.swift.lib;
      })
    ];
    postPatch = ''
      # The location of xcrun is hardcoded. We need PATH lookup instead.
      find Sources -name '*.swift' | xargs sed -i -e 's|/usr/bin/xcrun|xcrun|g'

      # Patch the location where swiftpm looks for its API modules.
      substituteInPlace Sources/PackageModel/UserToolchain.swift \
        --replace-fail \
          'librariesPath = applicationPath.parentDirectory' \
          "librariesPath = try AbsolutePath(validating: \"$out\")"
    '';
  };

  # Tools invoked by swiftpm at run-time.
  runtimeDeps = [
    git
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    xcbuild.xcrun
    # These tools are part of cctools, but adding that as a build input puts
    # an unwrapped linker in PATH, and breaks builds. This small derivation
    # exposes just the tools we need:
    # - vtool is used to determine a minimum deployment target.
    # - libtool is used to build static libraries.
    (runCommandLocal "swiftpm-cctools" { } ''
      mkdir -p $out/bin
      ln -s ${cctools}/bin/vtool $out/bin/vtool
      ln -s ${cctools}/bin/libtool $out/bin/libtool
    '')
  ];

  # Common attributes for the bootstrap derivations.
  mkBootstrapDerivation =
    attrs:
    stdenv.mkDerivation (
      attrs
      // {
        nativeBuildInputs =
          (attrs.nativeBuildInputs or [ ])
          ++ [
            cmake
            ninja
            swift
          ]
          ++ lib.optionals stdenv.hostPlatform.isDarwin [ DarwinTools ];

        buildInputs = (attrs.buildInputs or [ ]) ++ [ Foundation ];

        postPatch =
          (attrs.postPatch or "")
          + lib.optionalString stdenv.hostPlatform.isDarwin ''
            # On Darwin only, Swift uses arm64 as cpu arch.
            if [ -e cmake/modules/SwiftSupport.cmake ]; then
              # At least in swift-asn1, this has been removed and the module uses the full target triple as the name
              # (https://github.com/apple/swift-asn1/pull/103)
              substituteInPlace cmake/modules/SwiftSupport.cmake \
                --replace '"aarch64" PARENT_SCOPE' '"arm64" PARENT_SCOPE'
            fi
          '';

        postInstall =
          (attrs.postInstall or "")
          + lib.optionalString stdenv.hostPlatform.isDarwin ''
            # The install name of libraries is incorrectly set to lib/ (via our
            # CMake setup hook) instead of lib/swift/. This'd be easily fixed by
            # fixDarwinDylibNames, but some builds create libraries that reference
            # eachother, and we also have to fix those references.
            # Search all of `lib`, not just `lib/swift*`: libraries in plain
            # `lib` reference the ones under `lib/swift/host` too (swiftpm's
            # `libCommands.dylib` needs `libSwiftRefactor.dylib`), so they need
            # the same rewrites. For a library already in the right place the
            # `-id` is simply a no-op.
            dylibs="$(find $out/lib -name '*.dylib' 2>/dev/null)"
            changes=""
            for dylib in $dylibs; do
              changes+=" -change $(otool -D $dylib | tail -n 1) $dylib"
            done
            for dylib in $dylibs; do
              install_name_tool -id $dylib $changes $dylib
            done

            # Executables need the same rewrites. They record the same wrong
            # `$out/lib/<name>` paths, so without this they cannot start at all
            # ("Library not loaded: .../lib/libSwiftRefactor.dylib").
            #
            # Two things to be careful about. `$changes` is empty for packages
            # whose libraries are not under `lib/swift*`, and `install_name_tool`
            # with no operations exits non-zero. And `otool -L` exits 0 even on
            # the shell wrappers `wrapProgram` leaves behind — it reports "is not
            # an object file" rather than failing — so the exit status is not a
            # usable test for "is this Mach-O".
            if [[ -n "$changes" ]]; then
              for prog in $out/bin/* $out/bin/.*-wrapped; do
                [[ -f $prog ]] || continue
                otool -L "$prog" 2>&1 | grep -q "is not an object file" && continue
                install_name_tool $changes "$prog"
              done
            fi
          '';

        cmakeFlags = (attrs.cmakeFlags or [ ]) ++ [
          # Some builds link to libraries within the same build. Make sure these
          # create references to $out. None of our builds run their own products,
          # so we don't have to account for that scenario.
          "-DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON"
        ];
      }
    );

  # On Darwin, we only want ncurses in the linker search path, because headers
  # are part of libsystem. Adding its headers to the search path causes strange
  # mixing and errors.
  # TODO: Find a better way to prevent this conflict.
  ncursesInput = if stdenv.hostPlatform.isDarwin then ncurses.out else ncurses;

  # Derivations for bootstrapping dependencies using CMake.
  # This is based on the `swiftpm/Utilities/bootstrap` script.
  #
  # Some of the installation steps here are a bit hacky, because it seems like
  # these packages were not really meant to be installed using CMake. The
  # regular swiftpm bootstrap simply refers to the source and build
  # directories. The advantage of separate builds is that we can more easily
  # link libs together using existing Nixpkgs infra.
  #
  # In the end, we don't expose these derivations, and they only exist during
  # the bootstrap phase. The final swiftpm derivation does not depend on them.

  swift-system = mkBootstrapDerivation {
    name = "swift-system";
    src = generated.sources.swift-system;

    postInstall =
      cmakeGlue.SwiftSystem
      + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
        # The cmake rules apparently only use the Darwin install convention.
        # Fix up the installation so the module can be found on non-Darwin.
        mkdir -p $out/${swiftStaticModuleSubdir}
        mv $out/lib/swift_static/${swiftOs}/*.swiftmodule $out/${swiftStaticModuleSubdir}/
      '';
  };

  swift-collections = mkBootstrapDerivation {
    name = "swift-collections";
    src = generated.sources.swift-collections;

    postPatch = ''
      # Only builds static libs on Linux, but this installation difference is a
      # hassle. Because this installation is temporary for the bootstrap, may
      # as well build static libs everywhere.
      sed -i -e '/BUILD_SHARED_LIBS/d' CMakeLists.txt
    '';

    postInstall =
      cmakeGlue.SwiftCollections
      + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
        # The cmake rules apparently only use the Darwin install convention.
        # Fix up the installation so the module can be found on non-Darwin.
        mkdir -p $out/${swiftStaticModuleSubdir}
        mv $out/lib/swift_static/${swiftOs}/*.swiftmodule $out/${swiftStaticModuleSubdir}/
      '';
  };

  swift-tools-support-core = mkBootstrapDerivation {
    name = "swift-tools-support-core";
    src = generated.sources.swift-tools-support-core;

    buildInputs = [
      swift-system
      sqlite
    ];

    postInstall = cmakeGlue.TSC + ''
      # Swift modules are not installed.
      mkdir -p $out/${swiftModuleSubdir}
      cp swift/*.swift{module,doc} $out/${swiftModuleSubdir}/

      # Static libs are not installed.
      cp lib/*.a $out/lib/

      # Headers are not installed.
      mkdir -p $out/include
      cp -r ../Sources/TSCclibc/include $out/include/TSC
    '';
  };

  swift-argument-parser = mkBootstrapDerivation {
    name = "swift-argument-parser";
    src = generated.sources.swift-argument-parser;

    buildInputs = [
      ncursesInput
      sqlite
    ];

    cmakeFlags = [
      "-DBUILD_TESTING=NO"
      "-DBUILD_EXAMPLES=NO"
    ];

    postInstall =
      cmakeGlue.ArgumentParser
      + ''
        # `ArgumentParserToolInfo` is a static library that upstream builds but
        # never installs: its code ends up inside libArgumentParser, so only the
        # Swift module is missing. swift-driver's `swift-help` imports it
        # directly, so install the module the same way `_install_target` would.
        # Take the module triple from the sibling module CMake did install, so
        # this stays right on every platform without hardcoding it.
        apModule=$out/lib/swift/${swiftOs}/ArgumentParser.swiftmodule
        triple=$(basename "$(echo "$apModule"/*.swiftmodule | cut -d' ' -f1)" .swiftmodule)
        moduleDir=$out/lib/swift/${swiftOs}/ArgumentParserToolInfo.swiftmodule
        mkdir -p "$moduleDir"
        for ext in swiftmodule swiftdoc; do
          install -m644 "swift/ArgumentParserToolInfo.$ext" "$moduleDir/$triple.$ext"
        done
      ''
      + lib.optionalString stdenv.hostPlatform.isLinux ''
        # Fix rpath so ArgumentParserToolInfo can be found.
        patchelf --add-rpath "$out/lib/swift/${swiftOs}" \
          $out/lib/swift/${swiftOs}/libArgumentParser.so
      '';
  };

  llbuild = mkBootstrapDerivation {
    name = "llbuild";
    src = generated.sources.swift-llbuild;

    nativeBuildInputs = lib.optional stdenv.hostPlatform.isDarwin xcbuild;
    buildInputs = [
      ncursesInput
      sqlite
    ];

    patches = [
      ./patches/llbuild-cmake-disable-rpath.patch
      ./patches/llbuild-fix-missing-cstdint.patch
    ];

    postPatch = ''
      # Substitute ncurses for curses.
      find . -name CMakeLists.txt | xargs sed -i -e 's/curses/ncurses/'

      # Use absolute install names instead of rpath.
      substituteInPlace \
        products/libllbuild/CMakeLists.txt \
        products/llbuildSwift/CMakeLists.txt \
        --replace-fail '@rpath' "$out/lib"

      # This subdirectory is enabled for Darwin only, but requires ObjC XCTest
      # (and only Swift XCTest is open source).
      substituteInPlace perftests/CMakeLists.txt \
        --replace-fail 'add_subdirectory(Xcode/' '#add_subdirectory(Xcode/'
    '';

    cmakeFlags = [
      "-DLLBUILD_SUPPORT_BINDINGS=Swift"
    ];

    postInstall = cmakeGlue.LLBuild + ''
      # Install module map.
      cp ../products/libllbuild/include/module.modulemap $out/include

      # Swift modules are not installed.
      mkdir -p $out/${swiftModuleSubdir}
      cp products/llbuildSwift/*.swift{module,doc} $out/${swiftModuleSubdir}/
    '';
  };

  swift-driver = mkBootstrapDerivation {
    name = "swift-driver";
    src = generated.sources.swift-driver;

    buildInputs = [
      llbuild
      swift-system
      swift-argument-parser
      swift-tools-support-core
    ];

    postInstall = cmakeGlue.SwiftDriver + ''
      # Swift modules are not installed.
      mkdir -p $out/${swiftModuleSubdir}
      cp swift/*.swift{module,doc} $out/${swiftModuleSubdir}/
    '';
  };

  swift-crypto = mkBootstrapDerivation {
    name = "swift-crypto";
    src = generated.sources.swift-crypto;

    buildInputs = [
      swift-asn1
    ];

    patches = [
      ./patches/install-crypto-extras.patch
    ];

    postPatch = ''
      # Fix use of hardcoded tool paths on Darwin.
      substituteInPlace CMakeLists.txt \
        --replace-fail /usr/bin/ar $NIX_CC/bin/ar
      substituteInPlace CMakeLists.txt \
        --replace-fail /usr/bin/ranlib $NIX_CC/bin/ranlib
    '';

    postInstall = cmakeGlue.SwiftCrypto + ''
      # Static libs are not installed.
      cp lib/*.a $out/lib/

      # Headers are not installed.
      cp -r ../Sources/CCryptoBoringSSL/include $out/include

      # Swift modules are put in the wrong place by default (and not all are linked)
      mkdir -p $out/${swiftModuleSubdir}
      rm -rf $out/${swiftModuleSubdir}/*.swift{module,doc}
      # I assume we don't care about .swiftsourceinfo
      cp swift/*.swift{module,doc} $out/${swiftModuleSubdir}/
    '';
  };

  swift-asn1 = mkBootstrapDerivation {
    name = "swift-asn1";
    src = generated.sources.swift-asn1;

    postInstall =
      cmakeGlue.SwiftASN1
      + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
        # SwiftASN1 uses the full target triple as the name of the swiftmodule
        # (https://github.com/apple/swift-asn1/pull/103)
        mkdir -p $out/${swiftModuleSubdir}
        cp swift/*.swift{module,doc} $out/${swiftModuleSubdir}/
      '';
  };

  swift-certificates = mkBootstrapDerivation {
    name = "swift-certificates";
    src = generated.sources.swift-certificates;

    buildInputs = [
      swift-asn1
      swift-crypto
    ];

    postInstall = cmakeGlue.SwiftCertificates;
  };

  swift-tools-protocols = mkBootstrapDerivation {
    name = "swift-tools-protocols";
    src = generated.sources.swift-tools-protocols;

    patches = lib.optionals stdenv.hostPlatform.isDarwin [
      ./patches/tools-protocols-signposter-sendable.patch
    ];

    buildInputs = [
      swift-system
    ];

    postInstall = cmakeGlue.SwiftToolsProtocols + ''
      # This package installs its static libraries directly into `lib` and does
      # not install Swift modules at all, so consumers can neither link against
      # it nor import it. Move everything into the `lib/swift_static/<os>`
      # layout the other bootstrap dependencies use, and install the modules
      # from the build tree alongside.
      mkdir -p $out/lib/swift_static/${swiftOs} $out/${swiftStaticModuleSubdir}
      mv $out/lib/*.a $out/lib/swift_static/${swiftOs}/
      install -m644 swift/*.swiftmodule swift/*.swiftdoc $out/${swiftStaticModuleSubdir}/

      # `ToolsProtocolsCAtomics` is a header-only Clang module, so it has no
      # build product at all — copy its headers and module map across.
      mkdir -p $out/include
      cp -r ../Sources/ToolsProtocolsCAtomics/include $out/include/ToolsProtocolsCAtomics
    '';
  };

  swift-build = mkBootstrapDerivation {
    name = "swift-build";
    src = generated.sources.swift-build;

    buildInputs = [
      llbuild
      sqlite
      swift-argument-parser
      swift-collections
      swift-driver
      swift-system
      swift-tools-protocols
      swift-tools-support-core
    ];

    postInstall = cmakeGlue.SwiftBuild + ''
      # Swift modules are not installed.
      mkdir -p $out/${swiftModuleSubdir}
      cp swift/*.swift{module,doc} $out/${swiftModuleSubdir}/

      # Neither are the headers of the two C targets. `SwiftBuild.swiftmodule`
      # refers to `SWBCLibc`, so anything importing SwiftBuild needs their
      # module maps on the include path, even though nothing links them
      # directly.
      mkdir -p $out/include
      cp -r ../Sources/SWBCLibc/include $out/include/SWBCLibc
      cp -r ../Sources/SWBCSupport $out/include/SWBCSupport
    '';
  };

  # Build a bootrapping swiftpm using CMake.
  swiftpm-bootstrap = mkBootstrapDerivation (
    commonAttrs
    // {
      pname = "swiftpm-bootstrap";

      buildInputs = [
        llbuild
        sqlite
        swift-argument-parser
        swift-asn1
        swift-build
        swift-certificates
        swift-collections
        swift-crypto
        swift-driver
        swift-system
        swift-tools-protocols
        swift-tools-support-core
      ];

      # swift-syntax is added with `FetchContent`, so its targets are excluded
      # from `all` and only the ones swiftpm links get built — but swiftpm sets
      # `SWIFT_SYNTAX_INSTALL_TARGETS`, so the install step expects every one of
      # them. `SwiftCompilerPlugin` is the only one nothing links (it is for
      # macro plugin authors), so name it explicitly or the install dies on
      # "file INSTALL cannot find .../libSwiftCompilerPlugin.dylib".
      ninjaFlags = [
        "all"
        "SwiftCompilerPlugin"
      ];

      cmakeFlags = [
        "-DUSE_CMAKE_INSTALL=ON"
        # swiftpm needs swift-syntax for its macro support and pulls it in with
        # `FetchContent` when `find_package(SwiftSyntax)` fails — which it always
        # does here, because the toolchain never installs a `SwiftSyntaxConfig.cmake`
        # (both swift and swift-syntax generate it with `export()`, which only
        # writes into a build tree). Point it at our pinned checkout so nothing
        # is cloned during the build; `BuildSupport/SwiftSyntax/CMakeLists.txt`
        # provides this variable for exactly that purpose.
        "-DSWIFTPM_PATH_TO_SWIFT_SYNTAX_SOURCE=${sources.swift-syntax}"
      ];

      postInstall = ''
        for program in $out/bin/swift-*; do
          wrapProgram $program --prefix PATH : ${lib.makeBinPath runtimeDeps}
        done
      '';
    }
  );

in
# Build the final swiftpm with the bootstrapping swiftpm.
stdenv.mkDerivation (
  commonAttrs
  // {
    pname = "swiftpm";

    nativeBuildInputs = commonAttrs.nativeBuildInputs ++ [
      pkg-config
      swift
      swiftpm-bootstrap
    ];
    buildInputs = [
      ncursesInput
      sqlite
      XCTest
    ];

    configurePhase =
      generated.configure
      + ''
        # Functionality provided by Xcode XCTest, but not available in
        # swift-corelibs-xctest.
        swiftpmMakeMutable swift-tools-support-core
        substituteInPlace .build/checkouts/swift-tools-support-core/Sources/TSCTestSupport/XCTestCasePerf.swift \
          --replace-fail 'canImport(Darwin)' 'false'

        # Prevent a warning about SDK directories we don't have.
        swiftpmMakeMutable swift-driver
        patch -p1 -d .build/checkouts/swift-driver -i ${
          replaceVars ../swift-driver/patches/prevent-sdk-dirs-warnings.patch {
            inherit (builtins) storeDir;
          }
        }
      ''
      + lib.optionalString stdenv.hostPlatform.isDarwin ''
        # The same `OSSignposter` Sendable fix the CMake bootstrap needs. This
        # build compiles swift-tools-protocols from the vendored checkout rather
        # than using our derivation, so it has to be patched here too.
        swiftpmMakeMutable swift-tools-protocols
        patch -p1 -d .build/checkouts/swift-tools-protocols \
          -i ${./patches/tools-protocols-signposter-sendable.patch}

        swiftpmMakeMutable swift-build
        patch -p1 -d .build/checkouts/swift-build \
          -i ${./patches/swift-build-oslog-sendable.patch}
      '';

    buildPhase = ''
      # Build only what `installPhase` actually installs. A bare `swift-build`
      # builds every target in the package, including `_InternalTestSupport`,
      # which exists solely for swiftpm's own test suite — and which we neither
      # build nor run (`doCheck` is off, `checkPhase` is commented out below).
      #
      # That target is not merely wasted work: it does `import Testing` without
      # declaring a dependency, expecting swift-testing to come from the
      # toolchain, and then uses its `#expect` macro. Satisfying that needs
      # swift-testing's module, its library, *and* its macro plugin passed by
      # hand — and our plugin is an executable rather than the dylib a real
      # toolchain ships (see ../swift-testing), which the compiler rejects with
      # "produced malformed response". None of it affects the output, so build
      # the three things we install and nothing else.
      # `--product`, not `--target`: for an executable target, `--target` only
      # compiles the module and never links the binary.
      TERM=dumb swift-build -c release --product swift-package-manager
      TERM=dumb swift-build -c release --product PackageDescription
      TERM=dumb swift-build -c release --product PackagePlugin
    '';

    # TODO: Tests depend on indexstore-db being provided by an existing Swift
    # toolchain. (ie. looks for `../lib/libIndexStore.so` relative to swiftc.
    #doCheck = true;
    #checkPhase = ''
    #  TERM=dumb swift-test -c release
    #'';

    # The following is derived from Utilities/bootstrap, see install_swiftpm.
    installPhase = ''
      binPath="$(swift-build --show-bin-path -c release)"

      mkdir -p $out/bin $out/lib/swift

      cp $binPath/swift-package-manager $out/bin/swift-package
      wrapProgram $out/bin/swift-package \
        --prefix PATH : ${lib.makeBinPath runtimeDeps}
      # `swift-package-manager` dispatches on its own basename and calls
      # `fatalError` for anything it does not recognise, so this list has to
      # match the switch in `Sources/swift-package-manager/SwiftPM.swift`.
      # `swift-experimental-destination` was removed in the 6.x window and
      # replaced by `swift-sdk` (plus a deprecated `swift-experimental-sdk`).
      for tool in swift-build swift-test swift-run swift-package-collection \
                  swift-package-registry swift-sdk swift-experimental-sdk; do
        ln -s $out/bin/swift-package $out/bin/$tool
      done

      # Modules moved out of the bin directory into a `Modules` subdirectory of
      # it. `Utilities/bootstrap`'s `install_dylib` reads them from there, and
      # also installs more than one module per dylib — `CompilerPluginSupport`
      # is part of the `PackageDescription` product and has no dylib of its own.
      installSwiftpmModule() {
        local dylib=$1 dest=$2
        shift 2

        mkdir -p $out/lib/swift/pm/$dest
        cp $binPath/lib$dylib${sharedLibraryExt} $out/lib/swift/pm/$dest/

        for module in "$@"; do
          # Install the binary module *and* the textual interface where both
          # exist. swiftc prefers the binary one, which is also what upstream
          # effectively ships: its own `.swiftinterface` check looks in the bin
          # directory rather than `Modules`, so it never fires.
          cp -r $binPath/Modules/$module.swiftmodule $out/lib/swift/pm/$dest/
          if [[ -f $binPath/Modules/$module.swiftinterface ]]; then
            cp $binPath/Modules/$module.swiftinterface $out/lib/swift/pm/$dest/
          fi
          cp $binPath/Modules/$module.swiftdoc $out/lib/swift/pm/$dest/
        done
      }
      installSwiftpmModule PackageDescription ManifestAPI \
        PackageDescription CompilerPluginSupport
      installSwiftpmModule PackagePlugin PluginAPI PackagePlugin
    '';

    setupHook = ./setup-hook.sh;

    meta = {
      description = "Package Manager for the Swift Programming Language";
      homepage = "https://github.com/apple/swift-package-manager";
      platforms = with lib.platforms; linux ++ darwin;
      license = lib.licenses.asl20;
      teams = [ lib.teams.swift ];
    };
  }
)
