abuild recipe guidance
======================

recipe tree
-----------
name            - directory name, must be same as 'name' variable in abuild
 |- abuild      - package recipe (required)
 |- preinstall  - pre installation script (optional)
 |- postinstall - post installation script (optional)
 |- depends     - runtime dependencies, one package per line (optional)
 |- makedepends - build-time dependencies, one package per line (optional)
 |- info        - package metadata (optional)
 |- .shasum     - source checksums, auto generated if not exist ('amu -g')
 \- .files      - package file list, generated after packaging ('amu -k')

building package
----------------

- run 'amu' inside package recipe directory.
   or
- run 'amu -i <package name>' if package recipe is created inside
  AMU_REPO directory ('amu-src -p <package name>' prints the path).

installing package
------------------

- run 'amu -i' or 'amu -i <package name>'.
   or
- run 'amu-bin -i <path to prebuilt package file>' directly (pre/postinstall
  scripts and system triggers still run through amu-bin; this is the
  low-level path, 'amu trigger' can refresh caches afterwards if needed).

abuild variables
----------------

required:

name        - package name, must match the recipe directory name
version     - upstream version number
release     - increment number, reset to 1 on version change
source      - source tarballs (may be empty for meta packages)

source formats:

* <url>                 - regular source tarball url
* <tarball>::<url>      - custom local name for a remote url
* <url>::noextract      - download but do not unpack
* <filename>            - local file inside the recipe directory

optional:

sv              - runit service files installed into /etc/sv
build_opt       - extra flags for the auto-detected build system
build_type      - force a build system (meson_build, muon_build,
                  configure_build, cmake_build, python_build,
                  perlmodule_build, makefile_build)
build_dir       - subdirectory to enter before building
skip_patch      - do not auto-apply *.patch/*.diff from source
patch_opt       - patch options (default -p1)
keep_static     - keep *.a archives
keep_libtool    - keep *.la files
keep_locale     - keep locale files
keep_doc        - keep documentation
no_strip        - do not strip binaries
safely_rebuildable - on version-unchanged rebuilds, run rebuild()
                     instead of a full rebuild

build hooks:

build()      - replaces the auto-detected build system entirely
prebuild()   - runs before the auto-detected build system
postbuild()  - runs after it

Inside hooks, $SRC is the extraction directory and $PKG the fakeroot
staging directory. DESTDIR-style variables (DESTDIR, DEST_DIR,
INSTALLROOT, install_root, INSTALL_ROOT) are pre-exported to $PKG.

example:

name=mypkg
version=1.2.3
release=1
source="https://example.com/$name-$version.tar.gz"

build() {
	./configure --prefix=/usr
	make
	make DESTDIR=$PKG install
}
