{
  lib,
  stdenv,
  fetchFromGitLab,
  windows,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "lmdb";
  version = "1.0.0";

  src = fetchFromGitLab {
    domain = "git.openldap.org";
    owner = "openldap";
    repo = "openldap";
    rev = "LMDB_${finalAttrs.version}";
    hash = "sha256-/KiSTH0Gi27u3N79Aqy2y1asZlSwPc0iPDV8ns2Nbfo=";
  };

  postUnpack = "sourceRoot=\${sourceRoot}/libraries/liblmdb";

  patches = [
    ./hardcoded-compiler.patch
    ./bin-ext.patch
  ];
  patchFlags = [ "-p3" ];

  # Don't attempt the .so if static, as it would fail.
  postPatch = lib.optionalString stdenv.hostPlatform.isStatic ''
    sed 's/^ILIBS\>.*/ILIBS = liblmdb.a/' -i Makefile
  '';

  outputs = [
    "bin"
    "out"
    "dev"
  ];

  buildInputs = lib.optional stdenv.hostPlatform.isWindows windows.pthreads;

  makeFlags = [
    "prefix=$(out)"
    "CC=${stdenv.cc.targetPrefix}cc"
    "AR=${stdenv.cc.targetPrefix}ar"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "LDFLAGS=-Wl,-install_name,$(out)/lib/liblmdb$(SOFULL)"
    "SOEXT=.dylib"
    "SOFULL=.$(LIBVER)$(SOEXT)"
    "VERSION_OPT=-Wl,-current_version,$(VEREXT)"
  ]
  ++ lib.optionals stdenv.hostPlatform.isWindows [
    "SOEXT=.dll"
    "BINEXT=.exe"
  ];

  doCheck = true;
  checkTarget = "test";

  postInstall = ''
    moveToOutput bin "$bin"
  ''
  # add lmdb.pc (dynamic only)
  + ''
    mkdir -p "$dev/lib/pkgconfig"
    cat > "$dev/lib/pkgconfig/lmdb.pc" <<EOF
    Name: lmdb
    Description: ${finalAttrs.meta.description}
    Version: ${finalAttrs.version}

    Cflags: -I$dev/include
    Libs: -L$out/lib -llmdb
    EOF

    # Expected by Rust libraries.
    ln -s lmdb.pc "$dev/lib/pkgconfig/liblmdb.pc"
  ''
  # The Makefile does the wrong thing when following Darwin dylib naming conventions.
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    rm "$out/lib/liblmdb.1.dylib"
    cp liblmdb.1.dylib "$out/lib/liblmdb.1.dylib"
    ln -s liblmdb.1.dylib "$out/lib/liblmdb.dylib"
  '';

  meta = {
    description = "Lightning memory-mapped database";
    longDescription = ''
      LMDB is an ultra-fast, ultra-compact key-value embedded data store
      developed by Symas for the OpenLDAP Project. It uses memory-mapped files,
      so it has the read performance of a pure in-memory database while still
      offering the persistence of standard disk-based databases, and is only
      limited to the size of the virtual address space.
    '';
    homepage = "https://symas.com/lmdb/";
    changelog = "https://git.openldap.org/openldap/openldap/-/blob/LMDB_${finalAttrs.version}/libraries/liblmdb/CHANGES";
    maintainers = with lib.maintainers; [
      jb55
      vcunat
    ];
    license = lib.licenses.openldap;
    platforms = lib.platforms.all;
  };
})
