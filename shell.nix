{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "os2emx-crossbuild";

  packages = with pkgs; [
    # Linux host build tools
    gcc
    binutils
    gnumake
    git
    gnutar
    gzip
    unzip
    wget
    cmake
    ninja
    pkg-config
    which
    autoconf
    automake
    libtool
    m4
    bison
    flex
    texinfo
    perl
    python3
    gettext
    coreutils
    findutils
    gnused
    gawk

    # Host-side development libraries/tools used by libolm and Qt builds
    sqlite
    sqlite.dev
    zlib
    zlib.dev
    gmp
    gmp.dev
    mpfr
    mpfr.dev
    libmpc
    isl
    libxml2
    libxml2.dev
    expat
    expat.dev
    ncurses
    ncurses.dev
    libiconv
    libidn2
    libidn2.dev
    libunistring
    libunistring.dev
    # glibc headers are appended with -idirafter in shellHook; listing glibc
    # here injects them as -isystem and breaks C++ include_next.

    # Optional Qt6 host dependencies used by the surrounding project
    qt6.qtbase
    qt6.qtbase.dev
    qt6.qttools
    qt6.qttools.dev
    qt6.qtserialport
    qt6.qtserialport.dev
    qt6.qtdeclarative
    qt6.qtdeclarative.dev
    qt6.qt5compat
    qt6.qt5compat.dev
  ];

  shellHook = ''
    export OS2EMX_PREFIX="/data/os2emx"
    export OS2EMX_SYSROOT="$OS2EMX_PREFIX/i686-pc-os2-emx"
    export OS2EMX_TARGET="i686-pc-os2-emx"
    export OS2EMX_BUILD_ROOT="/data/build-nix"
    export OS2EMX_CMAKE_TOOLCHAIN_FILE="/data/build-nix/libolm-os2-toolchain.cmake"

    # Keep target tools ahead of host tools, but keep the build-nix host
    # wrappers available for GCC/bootstrap work.
    export OS2EMX_BUILD_TOOLS="$OS2EMX_PREFIX/bin"
    export PATH="$OS2EMX_BUILD_TOOLS:$OS2EMX_BUILD_ROOT/bin:$PATH"

    # Keep Nix wrapper flags for Linux host builds (including dev headers and
    # libraries). The OS/2 compiler is invoked explicitly and is not a Nix wrapper.
    unset AR_FOR_TARGET AS_FOR_TARGET CC_FOR_TARGET CXX_FOR_TARGET LD_FOR_TARGET
    unset CXX_INCLUDES NIX_CC_FOR_TARGET
    unset NIX_CFLAGS_COMPILE_FOR_TARGET NIX_LDFLAGS_FOR_TARGET
    unset NIX_BINTOOLS_FOR_TARGET LD_LIBRARY_PATH

    # Preserve the Nix host include flags and put glibc headers after GCC's
    # internal headers so C++ #include_next <stdlib.h> resolves correctly.
    export NIX_CFLAGS_COMPILE="$(python3 -c 'import os, shlex; a=shlex.split(os.environ.get("NIX_CFLAGS_COMPILE", "")); p="${pkgs.glibc.dev}/include"; print(" ".join(x for i,x in enumerate(a) if not (x=="-isystem" and i+1<len(a) and a[i+1]==p) and not (x==p and i>0 and a[i-1]=="-isystem")))') -idirafter ${pkgs.glibc.dev}/include"

    export OS2EMX_CC="$OS2EMX_PREFIX/bin/$OS2EMX_TARGET-gcc"
    export OS2EMX_CXX="$OS2EMX_PREFIX/bin/$OS2EMX_TARGET-g++"
    export OS2EMX_AR="$OS2EMX_PREFIX/bin/emxomfar"
    export OS2EMX_RANLIB=:
    export OS2EMX_STRIP="$OS2EMX_PREFIX/bin/emxomfstrip"
    
    # Official OpenSSL OS/2 port source/build paths. Do not set the global
    # OPENSSL_ROOT_DIR: it could contaminate Linux host-tool configurations.
    export OS2EMX_OPENSSL_SOURCE="/data/openssl-os2-3.6.5"
    export OS2EMX_OPENSSL_BUILD_ROOT="/data/build-nix/openssl-3.6.5-os2"
    # Older Netlabs binary fallback (not the Qt-compatible current port).
    export OS2EMX_OPENSSL_FALLBACK_ROOT="/data/openssl-os2-netlabs-3.4.1/usr"
    export OS2EMX_OPENSSL_FALLBACK_INCLUDE="$OS2EMX_OPENSSL_FALLBACK_ROOT/include"
    export OS2EMX_OPENSSL_FALLBACK_LIB="$OS2EMX_OPENSSL_FALLBACK_ROOT/lib"

    if [ ! -x "$OS2EMX_CC" ] || [ ! -x "$OS2EMX_CXX" ]; then
      echo "ERROR: OS/2 EMX compiler not found below $OS2EMX_PREFIX" >&2
      return 1
    fi
    if [ ! -f "$OS2EMX_SYSROOT/include/stdlib.h" ]; then
      echo "ERROR: OS/2 EMX sysroot is incomplete: $OS2EMX_SYSROOT" >&2
      return 1
    fi
    if [ ! -x "$OS2EMX_AR" ] || [ ! -x "$OS2EMX_PREFIX/bin/emxomfld" ]; then
      echo "ERROR: EMX OMF archiver/linker is missing below $OS2EMX_PREFIX" >&2
      return 1
    fi

    echo "OS/2 EMX cross shell ready"
    echo "  target:  $OS2EMX_TARGET"
    echo "  prefix:  $OS2EMX_PREFIX"
    echo "  sysroot: $OS2EMX_SYSROOT"
    echo "  cmake:   $OS2EMX_CMAKE_TOOLCHAIN_FILE"
    echo "  build:   $OS2EMX_BUILD_ROOT"
  '';
}
