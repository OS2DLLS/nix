# One-command Linux-to-OS/2 build. All toolchain paths and compiler flags are
# taken from shell.nix; the per-project build trees stay below OS2EMX_BUILD_ROOT.
.DEFAULT_GOAL := all
.NOTPARALLEL:

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# This Makefile is run from the already-entered /data/shell.nix environment.
# Host-only stages clear target compiler flags; no nested nix-shell is started.
HOST_ENV = env -u CMAKE_TOOLCHAIN_FILE -u CC -u CXX -u AR -u ARFLAGS -u RANLIB -u STRIP -u CFLAGS -u CXXFLAGS -u LDFLAGS -u LIBS -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH -u PKG_CONFIG_ALLOW_SYSTEM_CFLAGS -u PKG_CONFIG_ALLOW_SYSTEM_LIBS -u OPENSSL_ROOT_DIR OS2EMX_BUILD_MODE=host PKG_CONFIG_PATH="$(OS2EMX_HOST_PKG_CONFIG_PATH)"

.PHONY: all preflight host-preflight cross-os2emx libc-os2 libcx openssl qt-host qt-base qt-serialport libb2-os2 libolm

all: preflight cross-os2emx libc-os2 libcx libb2-os2 openssl qt-host qt-base qt-serialport libolm

preflight:
	@test "$(OS2EMX_BUILD_MODE)" = target
	@test -n "$(OS2EMX_PREFIX)"
	@test -n "$(OS2EMX_INSTALL_ROOT)"
	@test -n "$(OS2EMX_SYSROOT)"
	@test -n "$(OS2EMX_BUILD_ROOT)"
	@test -x "$(OS2EMX_CC)"
	@test -x "$(OS2EMX_CXX)"
	@test -x "$(OS2EMX_AR)"
	@test -f "$(OS2EMX_SYSROOT)/include/stdlib.h"
	@test -f "$(ROOT)/cross-os2emx/Makefile"
	@test -f "$(ROOT)/libc-os2/src/emx/Makefile.cross"
	@test -f "$(ROOT)/libcx/Makefile"
	@test -f "$(ROOT)/libb2/CMakeLists.txt"
	@test -f "$(ROOT)/openssl-os2/Configure"
	@test -f "$(ROOT)/qt6-base-os2/CMakeLists.txt"
	@test -f "$(ROOT)/qt6-serialport-os2/CMakeLists.txt"

# Host-only Qt/libb2 stages must not require the OS/2 target toolchain.
host-preflight:
	@test -n "$(OS2EMX_BUILD_ROOT)"
	@test -n "$(OS2EMX_HOST_INSTALL_ROOT)"
	@test -x "$(OS2EMX_HOST_CMAKE)"
	@test -x "$(OS2EMX_HOST_MAKE)"
	@test -x "$(OS2EMX_HOST_PKG_CONFIG)"

# The outer nix-shell defaults to target mode. Use a clean host environment for
# the native cross-toolchain bootstrap and Linux Qt host tools.
cross-os2emx: preflight
	$(HOST_ENV) $(MAKE) -C "$(ROOT)/cross-os2emx" -j2 PREFIX="$(OS2EMX_PREFIX)" PREFIXROOT="$(HOME)" OS2EMX_BUILD_ROOT="$(OS2EMX_BUILD_ROOT)"

# The Linux cross-buildable part of libc-os2 is src/emx/Makefile.cross. The
# cross-os2emx aggregate also builds these helper tools; this explicit step
# keeps libc-os2 visible in the top-level dependency graph and reuses its build.
libc-os2: cross-os2emx
	OS2EMX_BUILD_MODE=target $(MAKE) -C "$(ROOT)/libc-os2/src/emx" -f Makefile.cross -j2 \
	  build EMXDIR="$(ROOT)/libc-os2/src/emx" BINUTILSDIR="$(ROOT)/binutils-os2" \
	  BINUTILSBUILDDIR="$(OS2EMX_BUILD_ROOT)/cross-os2emx/binutils" \
	  OUTDIR="$(OS2EMX_BUILD_ROOT)/cross-os2emx/emxtools/$(OS2EMX_TARGET)" \
	  OS2EMX_BUILD_ROOT="$(OS2EMX_BUILD_ROOT)" OS2EMX_PREFIX="$(OS2EMX_PREFIX)" \
	  PREFIXROOT="$(HOME)" PREFIX="$(OS2EMX_PREFIX)"
	OS2EMX_BUILD_MODE=target $(MAKE) -C "$(ROOT)/libc-os2/src/emx" -f Makefile.cross -j2 \
	  install EMXDIR="$(ROOT)/libc-os2/src/emx" BINUTILSDIR="$(ROOT)/binutils-os2" \
	  BINUTILSBUILDDIR="$(OS2EMX_BUILD_ROOT)/cross-os2emx/binutils" \
	  OUTDIR="$(OS2EMX_BUILD_ROOT)/cross-os2emx/emxtools/$(OS2EMX_TARGET)" \
	  OS2EMX_BUILD_ROOT="$(OS2EMX_BUILD_ROOT)" OS2EMX_PREFIX="$(OS2EMX_PREFIX)" \
	  PREFIXROOT="$(HOME)" PREFIX="$(OS2EMX_PREFIX)" DESTDIR=
	@test -x "$(OS2EMX_PREFIX)/bin/emximp"

# Build/install LIBCx into the active target sysroot before its consumers.
libcx: libc-os2
	OS2EMX_BUILD_MODE=target $(MAKE) -C "$(ROOT)/libcx" -j2 all install
	OS2EMX_BUILD_MODE=target $(MAKE) -C "$(ROOT)/libcx" -j2 install-prefix \
	  OS2EMX_INSTALL_ROOT="$(OS2EMX_INSTALL_ROOT)"
	@test -s "$(OS2EMX_INSTALL_ROOT)/lib/libcx0.dll"
	@test -s "$(OS2EMX_INSTALL_ROOT)/lib/libcx0.lib"

# The target libb2 package is distinct from the native libb2 needed by qt-host.
# Keep the target archive and headers in the common OS/2 prefix.
libb2-os2: cross-os2emx
	  cmake -S "$(ROOT)/libb2" -B "$$b" -G Ninja \
	    -DCMAKE_TOOLCHAIN_FILE="$(ROOT)/libb2/cmake/os2emx-toolchain.cmake" \
	    -DCMAKE_INSTALL_PREFIX="$(OS2EMX_INSTALL_ROOT)" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DLIBB2_ENABLE_OPENMP=OFF; \
	  cmake --build "$(OS2EMX_BUILD_ROOT)/libb2-os2" --parallel 2
	  cmake --install "$(OS2EMX_BUILD_ROOT)/libb2-os2"
	  test -s "$(OS2EMX_INSTALL_ROOT)p/lib/b2.lib"; test -s "$(OS2EMX_INSTALL_ROOT)/include/blake2.h";
	  test -s "$(OS2EMX_INSTALL_ROOT)p/lib/pkgconfig/libb2.pc";
	  "$(OS2EMX_AR)" t "$(OS2EMX_INSTALL_ROOT)/lib/b2.lib" >/dev/null

# OpenSSL's checked-in OS2-EMX Configure target is built out-of-tree and staged
# under the target sysroot, as documented in openssl-os2/NOTES-OS2.md.
openssl: libcx
	@set -eu; \
	  export OS2EMX_OPENSSL_SOURCE="$(ROOT)/openssl-os2"; \
	  export OS2EMX_OPENSSL_BUILD_ROOT="$(OS2EMX_BUILD_ROOT)/openssl-os2"; \
	  export OS2EMX_PTHREAD_ROOT="$(OS2EMX_SYSROOT)"; \
	  mkdir -p "$$OS2EMX_OPENSSL_BUILD_ROOT"; \
	  cd "$$OS2EMX_OPENSSL_BUILD_ROOT"; \
	  perl "$$OS2EMX_OPENSSL_SOURCE/Configure" OS2-EMX --prefix=/usr --openssldir=/etc/ssl; \
	  $(MAKE) -j2 AR="$(OS2EMX_AR)" ARFLAGS="-p512 -qc" \
	    RANLIB="$(OS2EMX_RANLIB)" DESTDIR="$(OS2EMX_SYSROOT)" install_sw; \
	  test -s "$(OS2EMX_SYSROOT)/lib/ssl3.dll"; \
	  test -s "$(OS2EMX_SYSROOT)/lib/crypto3.dll"; \
	  file "$(OS2EMX_SYSROOT)/lib/ssl3.dll" "$(OS2EMX_SYSROOT)/lib/crypto3.dll"

# QtSetup.cmake derives the OS/2 install prefix from OS2EMX_INSTALL_ROOT; use
# a fresh build tree so the default is exercised rather than a stale cache.
qt6: 
	cmake -S "$(ROOT)/qt6-base-os2" -B "$(OS2EMX_BUILD_ROOT)/build-qt6" \
	  -DCMAKE_TOOLCHAIN_FILE="$(ROOT)/qt6-base-os2/cmake/qt6-os2.cmake" -DQT_HOST_PATH="$(OS2EMX_INSTALL_ROOT)" \
	  -DOPENSSL_ROOT_DIR="$(OS2EMX_SYSROOT)" \
	  -DOS2EMX_PREFIX="$(OS2EMX_PREFIX)" -DOS2EMX_TARGET="$(OS2EMX_TARGET)" \
	  -DINPUT_openssl=runtime -DCMAKE_BUILD_TYPE=Release
	cmake --build $(OS2EMX_BUILD_ROOT)/build-qt6 --parallel 2; cmake --install "$(OS2EMX_BUILD_ROOT)/build-qt6";
	
	

# Build the module against the installed OS/2 Qt package and Linux host tools.
qt-serialport: qt6
	  cmake -S "$(ROOT)/qt6-serialport-os2" -B "$(OS2EMX_BUILD_ROOT)/qt6-serial" \
	    -DCMAKE_TOOLCHAIN_FILE="$(ROOT)/qt6-base-os2/cmake/qt6-os2.cmake" -DQT_HOST_PATH="$(OS2EMX_INSTALL_ROOT)" \
	    -DOS2EMX_PREFIX="$(OS2EMX_PREFIX)" -DOS2EMX_TARGET="$(OS2EMX_TARGET)" \
	    -DCMAKE_INSTALL_PREFIX="$(OS2EMX_INSTALL_ROOT)" \
	    -DQt6_DIR="$(OS2EMX_INSTALL_ROOT)/lib/cmake/Qt6" -DQt6Core_DIR="$(OS2EMX_INSTALL_ROOT)/lib/cmake/Qt6Core" \
	    -DQt6CoreTools_DIR="$(OS2EMX_INSTALL_ROOT)/lib/cmake/Qt6CoreTools" \
	    -DQt6GuiTools_DIR="$(OS2EMX_INSTALL_ROOT)/lib/cmake/Qt6GuiTools" \
	    -DQt6WidgetsTools_DIR="$(OS2EMX_INSTALL_ROOT)/lib/cmake/Qt6WidgetsTools" \
	    -DQt6BuildInternals_DIR="$(OS2EMX_INSTALL_ROOT)/lib/cmake/Qt6BuildInternals" \
	    -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF
	  cmake --build "$(OS2EMX_BUILD_ROOT)/qt6-serial" --parallel 2; cmake --install "$(OS2EMX_BUILD_ROOT)/qt6-serial"
	  test -s "$(OS2EMX_PREFIX)/lib/Qt6SP.dll"

libolm:
	cmake -S "$(ROOT)/libolm" -B "$(OS2EMX_BUILD_ROOT)/libolm-os2" \
	  -DCMAKE_TOOLCHAIN_FILE="$(OS2EMX_CMAKE_TOOLCHAIN_FILE)" \
	  -DCMAKE_INSTALL_PREFIX="$(OS2EMX_INSTALL_ROOT)" \
	  -DOLM_TESTS=OFF -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release	
	cmake --build "$(OS2EMX_BUILD_ROOT)/libolm-os2" --target olm --parallel 2
	cmake --install "$(OS2EMX_BUILD_ROOT)/libolm-os2"
	test -s "$(OS2EMX_PREFIX)/lib/olm.dll"
