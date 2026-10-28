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
    # Preserve the Nix host .pc search path before target mode replaces it.
    export OS2EMX_HOST_PKG_CONFIG_PATH="''${PKG_CONFIG_PATH:-}"
    export OS2EMX_PREFIX="/data/os2emx"
    export OS2EMX_SYSROOT="$OS2EMX_PREFIX/i686-pc-os2-emx"
    export OS2EMX_TARGET="i686-pc-os2-emx"
    export OS2EMX_BUILD_ROOT="/data/build-nix"
    export OS2EMX_INSTALL_ROOT="/data/os2emx"
    export OS2EMX_TOOLCHAIN_SOURCE_ROOT="/data/cross-os2emx"
    export OS2EMX_CMAKE_TOOLCHAIN_FILE="$OS2EMX_TOOLCHAIN_SOURCE_ROOT/cmake/os2emx-default.cmake"

    # Linux tools must win PATH resolution; only the target compiler/OMF tools
    # are appended. Native host builds use OS2EMX_BUILD_MODE=host.
    export OS2EMX_BUILD_TOOLS="$OS2EMX_PREFIX/bin"
    export OS2EMX_TARGET_BIN="$OS2EMX_SYSROOT/bin"
    export OS2EMX_HOST_CMAKE="$OS2EMX_PREFIX/bin/cmake"
    export OS2EMX_HOST_MAKE="$OS2EMX_PREFIX/bin/make"
    export OS2EMX_HOST_PKG_CONFIG="$OS2EMX_PREFIX/bin/pkg-config"
    export PATH="$OS2EMX_PREFIX/bin:$OS2EMX_SYSROOT/bin:$PATH"
    export CMAKE_GENERATOR=Ninja
    export CMAKE_BUILD_PARALLEL_LEVEL=2
    export CMAKE_MAKE_PROGRAM=$OS2EMX_HOST_CMAKE

    export OS2EMX_CC="$OS2EMX_PREFIX/bin/$OS2EMX_TARGET-gcc"
    export OS2EMX_CXX="$OS2EMX_PREFIX/bin/$OS2EMX_TARGET-g++"
    export OS2EMX_AR="$OS2EMX_PREFIX/$OS2EMX_TARGET/bin/emxomfar"
    export OS2EMX_RANLIB=:
    export OS2EMX_STRIP="$OS2EMX_PREFIX/bin/emxomfstrip"

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

    echo "OS/2 EMX build shell ready"
    echo "  mode:    $OS2EMX_BUILD_MODE"
    echo "  target:  $OS2EMX_TARGET"
    echo "  prefix:  $OS2EMX_PREFIX"
    echo "  sysroot: $OS2EMX_SYSROOT"
    echo "  target install root: $OS2EMX_INSTALL_ROOT"
    echo "  host install root: $OS2EMX_HOST_INSTALL_ROOT"
    echo "  build:   $OS2EMX_BUILD_ROOT"
  '';
}
