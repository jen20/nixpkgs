{
  lib,
  newScope,
  stdenv,
  llvmPackages,
  darwin,
}:

let
  self = rec {

    callPackage = newScope self;

    # Provided for backwards compatibility.
    inherit stdenv;

    # Swift 6 cannot be built without an existing Swift compiler: its standard
    # library uses macros, which require swift-syntax, which is itself written
    # in Swift. Swift 5.10 is the last release whose stdlib builds with the
    # C++-only bootstrap, so we build that first and use it as the host
    # toolchain. It is an internal detail and not exposed as a package.
    swift-bootstrap-unwrapped = callPackage ./bootstrap {
      inherit (llvmPackages) stdenv;
      inherit (darwin) DarwinTools sigtool autoSignDarwinBinariesHook;
    };

    swiftBootstrap = callPackage ./wrapper {
      swift = swift-bootstrap-unwrapped;
      useSwiftDriver = false;
    };

    swift-unwrapped = callPackage ./compiler {
      inherit (llvmPackages) stdenv;
      inherit (darwin) DarwinTools sigtool autoSignDarwinBinariesHook;
      inherit swiftBootstrap;
    };

    swiftNoSwiftDriver = callPackage ./wrapper {
      swift = swift-unwrapped;
      useSwiftDriver = false;
    };

    Dispatch =
      if stdenv.hostPlatform.isDarwin then
        null # part of apple-sdk
      else
        callPackage ./libdispatch {
          inherit (llvmPackages) stdenv;
          swift = swiftNoSwiftDriver;
        };

    Foundation =
      if stdenv.hostPlatform.isDarwin then
        null # part of apple-sdk
      else
        callPackage ./foundation {
          inherit (llvmPackages) stdenv;
          swift = swiftNoSwiftDriver;
        };

    # TODO: Apple distributes a binary XCTest with Xcode, but it is not part of
    # CLTools (or SUS), so would have to figure out how to fetch it. The binary
    # version has several extra features, like a test runner and ObjC support.
    XCTest = callPackage ./xctest {
      inherit (darwin) DarwinTools;
      swift = swiftNoSwiftDriver;
    };

    # New toolchain component in Swift 6.x; upstream ships it alongside XCTest.
    swift-testing = callPackage ./swift-testing {
      inherit (darwin) DarwinTools;
      swift = swiftNoSwiftDriver;
    };

    swiftpm = callPackage ./swiftpm {
      inherit (llvmPackages) stdenv;
      inherit (darwin) DarwinTools;
      swift = swiftNoSwiftDriver;
    };

    swift-driver = callPackage ./swift-driver {
      inherit (llvmPackages) stdenv;
      swift = swiftNoSwiftDriver;
    };

    swift = callPackage ./wrapper {
      swift = swift-unwrapped;
    };

    sourcekit-lsp = callPackage ./sourcekit-lsp {
      inherit (llvmPackages) stdenv;
    };

    swift-docc = callPackage ./swift-docc {
      inherit (llvmPackages) stdenv;
    };

    swift-format = callPackage ./swift-format {
      inherit (llvmPackages) stdenv;
    };

    swiftpm2nix = callPackage ./swiftpm2nix { };

  };

in
self
