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

    # Common host-side development dependencies for cross-build workflows
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

    # Optional host Qt development modules
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
    export OS2EMX_INSTALL_ROOT="/data"
    export OS2EMX_TOOLCHAIN_SOURCE_ROOT="/data/cross-os2emx"
    export OS2EMX_CMAKE_TOOLCHAIN_FILE="$OS2EMX_TOOLCHAIN_SOURCE_ROOT/cmake/os2emx-default.cmake"

    # Linux tools must win PATH resolution; only the target compiler/OMF tools
    # are appended. Native host builds use OS2EMX_BUILD_MODE=host.
    export OS2EMX_BUILD_TOOLS="$OS2EMX_PREFIX/bin"
    export OS2EMX_TARGET_BIN="$OS2EMX_SYSROOT/bin"
    export OS2EMX_HOST_CMAKE="${pkgs.cmake}/bin/cmake"
    export OS2EMX_HOST_MAKE="${pkgs.gnumake}/bin/make"
    export OS2EMX_HOST_PKG_CONFIG="${pkgs.pkg-config}/bin/pkg-config"
    export PATH="${pkgs.cmake}/bin:${pkgs.gnumake}/bin:${pkgs.ninja}/bin:${pkgs.pkg-config}/bin:$PATH"
    export CMAKE_GENERATOR=Ninja
    export CMAKE_BUILD_PARALLEL_LEVEL=2

    if [ -z "$OS2EMX_BUILD_MODE" ]; then
      OS2EMX_BUILD_MODE=target
    fi
    export OS2EMX_BUILD_MODE

    if [ "$OS2EMX_BUILD_MODE" = target ] && [ -d "$OS2EMX_BUILD_ROOT/bin" ]; then
      export PATH="$OS2EMX_BUILD_ROOT/bin:$PATH"
    fi
    export PATH="$PATH:$OS2EMX_BUILD_TOOLS:$OS2EMX_TARGET_BIN"

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

    case "$OS2EMX_BUILD_MODE" in
      target)
        export CMAKE_TOOLCHAIN_FILE="$OS2EMX_CMAKE_TOOLCHAIN_FILE"
        export CC="$OS2EMX_CC"
        export CXX="$OS2EMX_CXX"
        export AR="$OS2EMX_AR"
        export ARFLAGS=rc
        export RANLIB=:
        export STRIP="$OS2EMX_STRIP"
        export CFLAGS="-Zomf -Zsym -Zmap -O2 -idirafter $OS2EMX_SYSROOT/include/os2tk45"
        export CXXFLAGS="$CFLAGS"
        export LDFLAGS="-Zomf -Zsym -Zmap -Zcrtdll"
        export LIBS="-lcx -Zcrtdll"
        export PKG_CONFIG="$OS2EMX_HOST_PKG_CONFIG"
        export PKG_CONFIG_SYSROOT_DIR="$OS2EMX_SYSROOT"
        export PKG_CONFIG_LIBDIR="$OS2EMX_SYSROOT/lib/pkgconfig:$OS2EMX_SYSROOT/share/pkgconfig"
        export PKG_CONFIG_PATH=""
        export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
        export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
        unset OPENSSL_ROOT_DIR
        ;;
      host)
        unset CMAKE_TOOLCHAIN_FILE CC CXX AR ARFLAGS RANLIB STRIP CFLAGS CXXFLAGS LDFLAGS LIBS
        unset PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
        unset OPENSSL_ROOT_DIR
        export PKG_CONFIG="$OS2EMX_HOST_PKG_CONFIG"
        ;;
      *)
        echo "ERROR: OS2EMX_BUILD_MODE must be 'target' or 'host' (got '$OS2EMX_BUILD_MODE')" >&2
        return 1
        ;;
    esac

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
    if [ "$OS2EMX_BUILD_MODE" = target ] && [ ! -f "$OS2EMX_CMAKE_TOOLCHAIN_FILE" ]; then
      echo "ERROR: default CMake cross toolchain is missing: $OS2EMX_CMAKE_TOOLCHAIN_FILE" >&2
      return 1
    fi

    echo "OS/2 EMX build shell ready"
    echo "  mode:    $OS2EMX_BUILD_MODE"
    echo "  target:  $OS2EMX_TARGET"
    echo "  prefix:  $OS2EMX_PREFIX"
    echo "  sysroot: $OS2EMX_SYSROOT"
    if [ -n "$CMAKE_TOOLCHAIN_FILE" ]; then
      echo "  cmake:   $CMAKE_TOOLCHAIN_FILE"
    else
      echo "  cmake:   host/native"
    fi
    echo "  install root: $OS2EMX_INSTALL_ROOT"
    echo "  build:   $OS2EMX_BUILD_ROOT"
  '';
}
