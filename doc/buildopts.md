# default build options used by amu-src when no build() is defined
# build systems are auto-detected in this order:
#   meson.build -> muon_build
#   configure   -> configure_build
#   CMakeLists.txt -> cmake_build
#   setup.py    -> python_build
#   Makefile.PL -> perlmodule_build
#   Makefile/makefile/GNUmakefile -> makefile_build

1 - muon_build (meson.build):
	meson setup \
		-Dprefix=/usr \
		-Dlibdir=/usr/lib \
		-Dincludedir=/usr/include \
		-Ddatadir=/usr/share \
		-Dmandir=/usr/share/man \
		-Dinfodir=/usr/share/info \
		-Dlocaledir=/usr/share/locale \
		-Dsysconfdir=/etc \
		-Dlocalstatedir=/var \
		-Dsharedstatedir=/var/lib \
		-Dbuildtype=plain \
		-Dauto_features=auto \
		-Dwrap_mode=nodownload \
		-Ddefault_library=shared \
		-Db_lto=true \
		-Db_pie=true \
		$build_opt \
		build
	samu -C build
	DESTDIR=$PKG muon -C build install -d "$PKG"

2 - configure_build:
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--infodir=/usr/share/info \
		--mandir=/usr/share/man \
		$build_opt
	make
	make DESTDIR=$PKG install

3 - cmake_build:
	mkdir -p cmakebuild
	cd cmakebuild
	cmake \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_SYSCONFDIR=/etc \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DFETCHCONTENT_FULLY_DISCONNECTED=ON \
		-DCMAKE_C_FLAGS_RELEASE="$CFLAGS" \
		-DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" \
		$build_opt \
		-B build ..
	if build.ninja exists:
		ninja
		DESTDIR=$PKG ninja install
	else:
		cmake --build build
		DESTDIR=$PKG cmake --install build

4 - python_build:
	python3 setup.py build
	python3 setup.py install --prefix=/usr --root=$PKG --optimize=1 $build_opt

5 - perlmodule_build:
	perl Makefile.PL
	make
	make DESTDIR=$PKG install

6 - makefile_build:
	make \
		PREFIX=/usr \
		prefix=/usr \
		SYSCONFDIR=/etc \
		sysconfdir=/etc \
		MANDIR=/usr/share/man \
		mandir=/usr/share/man \
		LIBDIR=/usr/lib \
		PKGCONFIGDIR=/usr/lib/pkgconfig
	make \
		PREFIX=/usr \
		prefix=/usr \
		SYSCONFDIR=/etc \
		sysconfdir=/etc \
		MANDIR=/usr/share/man \
		mandir=/usr/share/man \
		LIBDIR=/usr/lib \
		PKGCONFIGDIR=/usr/lib/pkgconfig \
		DESTDIR=$PKG install
