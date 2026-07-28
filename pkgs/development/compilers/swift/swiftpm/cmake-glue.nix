# SwiftPM dependencies are normally not installed using CMake, and only provide
# CMake modules to link them together in a build tree. We have separate
# derivations, so need a real install step. Here we provide our own minimal
# CMake modules to install along with the build products.
{
  lib,
  stdenv,
  swift,
}:
let

  inherit (stdenv.hostPlatform) extensions;

  # This file exports shell snippets for use in postInstall.
  mkInstallScript = module: template: ''
    mkdir -p $out/lib/cmake/${module}
    (
      export staticLibExt="${extensions.staticLibrary}"
      export sharedLibExt="${extensions.sharedLibrary}"
      export swiftOs="${swift.swiftOs}"
      substituteAll \
        ${builtins.toFile "${module}Config.cmake" template} \
        $out/lib/cmake/${module}/${module}Config.cmake
    )
  '';

in
lib.mapAttrs mkInstallScript {
  # swift-system now installs its static library to `lib`; only the
  # `.swiftmodule` still goes under `lib/swift_static/<os>`.
  SwiftSystem = ''
    add_library(SwiftSystem::SystemPackage STATIC IMPORTED)
    set_property(TARGET SwiftSystem::SystemPackage PROPERTY IMPORTED_LOCATION "@out@/lib/libSystemPackage@staticLibExt@")
  '';

  # swift-tools-protocols is new in the 6.3 dependency graph. It installs its
  # static libraries but no CMake package and no Swift modules at all, so
  # consumers can neither find nor import it; `postInstall` moves the products
  # into the usual `lib/swift_static/<os>` layout and this supplies the targets
  # swift-build and swiftpm link against.
  SwiftToolsProtocols = ''
    # Header-only Clang module (an INTERFACE library upstream), so it needs an
    # include directory rather than a library to link.
    add_library(SwiftToolsProtocols::ToolsProtocolsCAtomics INTERFACE IMPORTED)
    set_property(TARGET SwiftToolsProtocols::ToolsProtocolsCAtomics PROPERTY INTERFACE_INCLUDE_DIRECTORIES "@out@/include/ToolsProtocolsCAtomics")

    add_library(SwiftToolsProtocols::ToolsProtocolsSwiftExtensions STATIC IMPORTED)
    set_property(TARGET SwiftToolsProtocols::ToolsProtocolsSwiftExtensions PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libToolsProtocolsSwiftExtensions@staticLibExt@")

    add_library(SwiftToolsProtocols::SKLogging STATIC IMPORTED)
    set_property(TARGET SwiftToolsProtocols::SKLogging PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libSKLogging@staticLibExt@")

    add_library(SwiftToolsProtocols::LanguageServerProtocol STATIC IMPORTED)
    set_property(TARGET SwiftToolsProtocols::LanguageServerProtocol PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libLanguageServerProtocol@staticLibExt@")

    add_library(SwiftToolsProtocols::LanguageServerProtocolTransport STATIC IMPORTED)
    set_property(TARGET SwiftToolsProtocols::LanguageServerProtocolTransport PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libLanguageServerProtocolTransport@staticLibExt@")

    add_library(SwiftToolsProtocols::BuildServerProtocol STATIC IMPORTED)
    set_property(TARGET SwiftToolsProtocols::BuildServerProtocol PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libBuildServerProtocol@staticLibExt@")
  '';

  # swift-build (the new build engine, new in the 6.3 graph) installs its
  # dylibs but no CMake package and no Swift modules.
  SwiftBuild = ''
    add_library(SwiftBuild::SwiftBuild SHARED IMPORTED)
    set_property(TARGET SwiftBuild::SwiftBuild PROPERTY IMPORTED_LOCATION "@out@/lib/libSwiftBuild@sharedLibExt@")
    # `SwiftBuild.swiftmodule` refers to the `SWBCLibc` Clang module, so
    # consumers need these module maps on the include path.
    set_property(TARGET SwiftBuild::SwiftBuild PROPERTY INTERFACE_INCLUDE_DIRECTORIES "@out@/include/SWBCLibc;@out@/include/SWBCSupport")

    add_library(SwiftBuild::SWBBuildService SHARED IMPORTED)
    set_property(TARGET SwiftBuild::SWBBuildService PROPERTY IMPORTED_LOCATION "@out@/lib/libSWBBuildService@sharedLibExt@")
  '';

  SwiftCollections = ''
    add_library(SwiftCollections::Collections STATIC IMPORTED)
    set_property(TARGET SwiftCollections::Collections PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libCollections@staticLibExt@")

    add_library(SwiftCollections::DequeModule STATIC IMPORTED)
    set_property(TARGET SwiftCollections::DequeModule PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libDequeModule@staticLibExt@")

    add_library(SwiftCollections::OrderedCollections STATIC IMPORTED)
    set_property(TARGET SwiftCollections::OrderedCollections PROPERTY IMPORTED_LOCATION "@out@/lib/swift_static/@swiftOs@/libOrderedCollections@staticLibExt@")
  '';

  TSC = ''
    add_library(TSCLibc SHARED IMPORTED)
    set_property(TARGET TSCLibc PROPERTY IMPORTED_LOCATION "@out@/lib/libTSCLibc@sharedLibExt@")

    add_library(TSCBasic SHARED IMPORTED)
    set_property(TARGET TSCBasic PROPERTY IMPORTED_LOCATION "@out@/lib/libTSCBasic@sharedLibExt@")

    add_library(TSCUtility SHARED IMPORTED)
    set_property(TARGET TSCUtility PROPERTY IMPORTED_LOCATION "@out@/lib/libTSCUtility@sharedLibExt@")
  '';

  # swift-argument-parser now installs its library to `lib` (only the
  # `.swiftmodule` still goes to `lib/swift/<os>`), and no longer builds a
  # separate `ArgumentParserToolInfo` — nothing in swift-driver or swiftpm
  # refers to that target any more.
  ArgumentParser = ''
    add_library(ArgumentParser SHARED IMPORTED)
    set_property(TARGET ArgumentParser PROPERTY IMPORTED_LOCATION "@out@/lib/libArgumentParser@sharedLibExt@")
  '';

  LLBuild = ''
    add_library(libllbuild SHARED IMPORTED)
    set_property(TARGET libllbuild PROPERTY IMPORTED_LOCATION "@out@/lib/libllbuild@sharedLibExt@")

    add_library(llbuildSwift SHARED IMPORTED)
    set_property(TARGET llbuildSwift PROPERTY IMPORTED_LOCATION "@out@/lib/swift/pm/llbuild/libllbuildSwift@sharedLibExt@")
  '';

  SwiftDriver = ''
    add_library(SwiftDriver SHARED IMPORTED)
    set_property(TARGET SwiftDriver PROPERTY IMPORTED_LOCATION "@out@/lib/libSwiftDriver@sharedLibExt@")

    add_library(SwiftDriverExecution SHARED IMPORTED)
    set_property(TARGET SwiftDriverExecution PROPERTY IMPORTED_LOCATION "@out@/lib/libSwiftDriverExecution@sharedLibExt@")

    add_library(SwiftOptions SHARED IMPORTED)
    set_property(TARGET SwiftOptions PROPERTY IMPORTED_LOCATION "@out@/lib/libSwiftOptions@sharedLibExt@")
  '';

  SwiftCrypto = ''
    add_library(Crypto SHARED IMPORTED)
    set_property(TARGET Crypto PROPERTY IMPORTED_LOCATION "@out@/lib/swift/@swiftOs@/libCrypto@sharedLibExt@")

    add_library(_CryptoExtras SHARED IMPORTED)
    # this can't possibly be right... I really think it should be `libCryptoExtras`
    # swift-certificates did build with this though.....
    set_property(TARGET _CryptoExtras PROPERTY IMPORTED_LOCATION "@out@/lib/swift/@swiftOs@/libCrypto@sharedLibExt@")
  '';

  SwiftASN1 = ''
    add_library(SwiftASN1 SHARED IMPORTED)
    set_property(TARGET SwiftASN1 PROPERTY IMPORTED_LOCATION "@out@/lib/swift/@swiftOs@/libSwiftASN1@sharedLibExt@")
  '';

  SwiftCertificates = ''
    add_library(SwiftCertificates SHARED IMPORTED)
    set_property(TARGET SwiftCertificates PROPERTY IMPORTED_LOCATION "@out@/lib/swift/@swiftOs@/libCertificates@sharedLibExt@")
  '';
}
