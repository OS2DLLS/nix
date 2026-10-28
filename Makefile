# One-command Linux-to-OS/2 build. All toolchain paths and compiler flags are
# taken from shell.nix; the per-project build trees stay below OS2EMX_BUILD_ROOT.
.DEFAULT_GOAL := all
.NOTPARALLEL:

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# This Makefile is run from the already-entered /data/shell.nix environment.
# Host-only stages clear target compiler flags; no nested nix-shell is started.
HOST_ENV = env -u CMAKE_TOOLCHAIN_FILE -u CC -u CXX -u AR -u ARFLAGS -u RANLIB -u STRIP -u CFLAGS -u CXXFLAGS -u LDFLAGS -u LIBS -u PKG_CONFIG_SYSROOT_DIR -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_PATH -u PKG_CONFIG_ALLOW_SYSTEM_CFLAGS -u PKG_CONFIG_ALLOW_SYSTEM_LIBS -u OPENSSL_ROOT_DIR OS2EMX_BUILD_MODE=host

.PHONY: all preflight host-preflight cross-os2emx libc-os2 libcx openssl qt-host qt-base qt-serialport libb2

all: preflight cross-os2emx libc-os2 libcx openssl libb2 qt-host qt-base qt-serialport

preflight:
	@test "$(OS2EMX_BUILD_MODE)" = target
	@test -n "$(OS2EMX_PREFIX)"
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
	@test -n "$(OS2EMX_INSTALL_ROOT)"
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

# Build/install LIBCx into the active target sysroot before its consumers.
libcx: libc-os2
	OS2EMX_BUILD_MODE=target $(MAKE) -C "$(ROOT)/libcx" -j2 all install

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

# Qt's native build selects system libb2; build and test that host dependency
# separately from the OS/2 target, which uses Qt's bundled BLAKE2 implementation.
libb2: host-preflight
	@set -eu; b="$(OS2EMX_BUILD_ROOT)/libb2-host"; p="$(OS2EMX_INSTALL_ROOT)/libb2-host"; \
	  $(HOST_ENV) cmake -S "$(ROOT)/libb2" -B "$$b" \
	    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$$p" -DCMAKE_INSTALL_LIBDIR=lib \
	    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON -DLIBB2_ENABLE_OPENMP=OFF \
	    -DCMAKE_POSITION_INDEPENDENT_CODE=ON; \
	  $(HOST_ENV) cmake --build "$$b" --parallel 2; \
	  for test in blake2s-test blake2b-test blake2sp-test blake2bp-test; do $(HOST_ENV) "$$b/$$test"; done; \
	  $(HOST_ENV) cmake --install "$$b"; \
	  test -s "$$p/lib/libb2.a"; test -s "$$p/include/blake2.h"; \
	  test -s "$$p/lib/pkgconfig/libb2.pc"; \
	  $(HOST_ENV) PKG_CONFIG_PATH="$$p/lib/pkgconfig" "$(OS2EMX_HOST_PKG_CONFIG)" --modversion libb2

# Native Qt tools are built and installed separately from the OS/2 Qt target.
qt-host: libb2
	@set -eu; b="$(OS2EMX_BUILD_ROOT)/qt6-base-host-libb2-ninja"; p="$(OS2EMX_INSTALL_ROOT)/qt6-host"; l="$(OS2EMX_INSTALL_ROOT)/libb2-host"; \
	  $(HOST_ENV) PKG_CONFIG_PATH="$$l/lib/pkgconfig" cmake -S "$(ROOT)/qt6-base-os2" -B "$$b" \
	    -DCMAKE_INSTALL_PREFIX="$$p" -DCMAKE_BUILD_TYPE=Release \
	    -DPKG_CONFIG_EXECUTABLE="$(OS2EMX_HOST_PKG_CONFIG)" -DINPUT_libb2=system \
	    -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_BENCHMARKS=OFF; \
	  $(HOST_ENV) cmake --build "$$b" --parallel 2; \
	  $(HOST_ENV) cmake --install "$$b"; \
	  test -x "$$p/bin/moc"; test -x "$$p/bin/rcc"; test -x "$$p/bin/uic"

# QtSetup.cmake derives the OS/2 install prefix from OS2EMX_INSTALL_ROOT; do
# not override CMAKE_INSTALL_PREFIX here, so the default is exercised.
qt-base: openssl qt-host
	@set -eu; b="$(OS2EMX_BUILD_ROOT)/qt6-base-os2-ninja"; p="$(OS2EMX_INSTALL_ROOT)/qt6-os2-install"; h="$(OS2EMX_INSTALL_ROOT)/qt6-host"; \
	  cmake -S "$(ROOT)/qt6-base-os2" -B "$$b" \
	    -DCMAKE_TOOLCHAIN_FILE="$(ROOT)/qt6-base-os2/cmake/qt6-os2.cmake" \
	    -DQT_HOST_PATH="$$h" -DOPENSSL_ROOT_DIR="$(OS2EMX_SYSROOT)" \
	    -DINPUT_openssl=runtime -DCMAKE_BUILD_TYPE=Release; \
	  cmake --build "$$b" --parallel 2; cmake --install "$$b"; \
	  test -s "$$p/bin/Qt6Core.dll"; test -s "$$p/bin/Qt6Network.dll"

# Build the module against the installed OS/2 Qt package and Linux host tools.
qt-serialport: qt-base
	@set -eu; p="$(OS2EMX_INSTALL_ROOT)/qt6-os2-install"; h="$(OS2EMX_INSTALL_ROOT)/qt6-host"; b="$(OS2EMX_BUILD_ROOT)/qt6-serialport-os2"; t="$$p/lib/cmake/Qt6/qt.toolchain.cmake"; \
	  test -f "$$t"; \
	  cmake -S "$(ROOT)/qt6-serialport-os2" -B "$$b" \
	    -DCMAKE_TOOLCHAIN_FILE="$$t" -DQT_HOST_PATH="$$h" \
	    -DOS2EMX_PREFIX="$(OS2EMX_PREFIX)" -DOS2EMX_TARGET="$(OS2EMX_TARGET)" \
	    -DCMAKE_INSTALL_PREFIX="$$p" \
	    -DQt6_DIR="$$p/lib/cmake/Qt6" -DQt6Core_DIR="$$p/lib/cmake/Qt6Core" \
	    -DQt6CoreTools_DIR="$$h/lib/cmake/Qt6CoreTools" \
	    -DQt6GuiTools_DIR="$$h/lib/cmake/Qt6GuiTools" \
	    -DQt6WidgetsTools_DIR="$$h/lib/cmake/Qt6WidgetsTools" \
	    -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF; \
	  cmake --build "$$b" --parallel 2; cmake --install "$$b"; \
	  test -s "$$p/bin/Qt6SP.dll"