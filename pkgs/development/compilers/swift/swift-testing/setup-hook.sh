# shellcheck shell=bash

# swift-testing follows the layout a Swift toolchain uses, which puts its
# modules and its macro plugin in subdirectories of the ones the Swift wrapper's
# own hook scans (`lib/swift/<os>` and `lib/swift/host/plugins`). Add them for
# any build input that has them, so `import Testing` and `#expect` work without
# every consumer spelling the paths out.
swiftTesting_addFlags () {
    if [[ -d "$1/@moduleSubdir@" ]]; then
        export NIX_SWIFTFLAGS_COMPILE+=" -I $1/@moduleSubdir@"
    fi
    if [[ -d "$1/@libSubdir@" ]]; then
        export NIX_LDFLAGS+=" -L $1/@libSubdir@"
    fi
    if [[ -d "$1/@pluginSubdir@" ]]; then
        export NIX_SWIFTFLAGS_COMPILE+=" -plugin-path $1/@pluginSubdir@"
    fi
}

addEnvHooks "$targetOffset" swiftTesting_addFlags
