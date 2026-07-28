{ lib, fetchFromGitHub }:

let

  # These packages are all part of the Swift toolchain, and have a single
  # upstream version that should match. We also list the hashes here so a basic
  # version upgrade touches only this file.
  version = "6.3.3";
  hashes = {
    llvm-project = "sha256-b+0G3b5f/i+4SgLV0nsZte5pc/tHd9fVIOPAxWInQXs=";
    sourcekit-lsp = "sha256-vjVcsxFCg1s8L96HSllgGGVpOQeHAWfVnLmUcP05F/o=";
    swift = "sha256-7/jT/U0sOsr4iWnCluyUWjnD/XH5CnPyAG9EQ+Nq+tI=";
    swift-cmark = "sha256-0pyZ5yQRsbiKwz2XT8N6dMwCLcmM28qQOrxHcV6uH7g=";
    swift-corelibs-foundation = "sha256-Dm/oYkNRevXBBP1+xOgZm3/QjRLQBjk58mXt9N/sPAY=";
    swift-corelibs-libdispatch = "sha256-7UxacHkvbyt51I1WT2wWR1GDrHdknlnYWF9yF8GusQc=";
    swift-corelibs-xctest = "sha256-68OKhvLKwXPZNvuFkcZsqyeVE4YlLXp5+sHfns3EGKM=";
    swift-docc = "sha256-wRHy4yeq+LAUU7dDPc3kUT1BP9ZONl1qmfrYffuR5tQ=";
    swift-docc-render-artifact = "sha256-l5BHqQG47XurMfCASW0t2dfMe9rnXwmij4/qTLJJxes=";
    swift-driver = "sha256-XilPErlnLI7JOnEQM3zEieyo+0/7q2hYfHfnDBtP7qE=";
    swift-experimental-string-processing = "sha256-ENnaw/1UN9PnVLTZujtpfGs5d1e3Z+5Z6EjiwM/8alU=";
    swift-format = "sha256-YkOsFWaQJU786L9OB/n9jOL5G303cz0q62dw3yFWkA0=";
    # Since Swift 6, Foundation is a thin shim over the Swift-native
    # swift-foundation, which in turn bundles ICU via swift-foundation-icu.
    swift-foundation = "sha256-sXlA1n7SmgneUxsS7+/xNwbIOyGvLmofNXxrIG1Pq9w=";
    swift-foundation-icu = "sha256-+Syca40t4KYTs6Y0qgfntziUebEmHdq1tNNbLau4bwc=";
    swift-package-manager = "sha256-34mm8hYEvYuvmtkEBQDzluJSHsiwzmGWuO3ZgWnFjzg=";
    swift-syntax = "sha256-zr+2MlGncEu1bEQwUUxlySDx4XOyK+LnX1SRbtm9ERc=";
    swift-testing = "sha256-lXeFJcKRzoRpUYLrQT+5MITb36hSH/dXjBm4w0RispI=";
  };

  # Create fetch derivations.
  sources = lib.mapAttrs (
    repo: hash:
    fetchFromGitHub {
      owner = "swiftlang";
      inherit repo;
      rev = "swift-${version}-RELEASE";
      name = "${repo}-${version}-src";
      hash = hashes.${repo};
    }
  ) hashes;

in
sources // { inherit version; }
