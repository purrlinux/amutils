# amutils

Qwaderton Linux utilities: a collection of POSIX shell (busybox sh)
tools for source-based package management, binary repositories and
dependency resolution.

Inspired by autils by emmett1. Reproduces [autils](https://codeberg.org/emmett1/autils)
for Qwaderton Linux.

## Overview

**amu** is the central command-line frontend. It is a pure command
router: based on the first option it delegates to one of the backend
tools and passes all remaining arguments through. It never invokes
`spm` directly.

| Backend | Role |
|---|---|
| `amu-src` | source builds from `abuild` recipes (makepkg role) |
| `amu-bin` | package manager: install/upgrade/remove, the **only** tool that operates on packages and the spm database |
| `amu-resolv` | single owner of the dependency graph |
| `amu-trigger` | post-install system cache/database triggers |

`amu-bin` and `amu-src` share one source of truth: the recipe
repositories synced by `reposync`. There is no package index (no
APKGBINDB): versions and dependencies are read from the recipes, and
binaries are fetched from `AMU_BINREPO` as
`name#version-release.spm` with optional `.spm.sha3` sidecar checksums.

Standalone system tools (no amu library dependency): `reposync`
(git repo sync driven by `REPOSYNC_*` env vars), `updateconf`
(interactive `.new` config merge), `genfstab` (fstab generator),
`qlchroot` (chroot with virtual filesystems mounted).

## Installation

```sh
make install
```

Installs tools into `/usr/bin`, the library into `/usr/lib/amu`,
man pages into `/usr/share/man/man8`, documentation into
`/usr/share/doc/amutils`. Override with `DESTDIR`, `PREFIX`, `BINDIR`,
`LIBDIR`, `MANDIR` or `DOCDIR`. Copy `doc/amu.conf.example` to
`/etc/amu.conf` and adjust.

## Quick start

```sh
# Build and install a package (from inside its recipe directory)
cd /path/to/repo/mypkg
amu -i

# Install by name (build from source if a recipe exists in AMU_REPO,
# otherwise download the binary from AMU_BINREPO)
amu -i firefox

# Search available packages
amu -s icon

# Full system upgrade
amu -U

# Remove a package and its unneeded dependencies
amu -R mypkg            # or: amu purge --do-it mypkg

# Find broken library links after an upgrade
amu revdep

# Merge .new config files after an upgrade
updateconf
```

## Tools

| Tool | Description |
|---|---|
| `amu` | command router/frontend + helper subcommands |
| `amu-src` | build packages from source, recipe utilities (`-w`/`-p`/`-g`/`-k`) |
| `amu-bin` | `-i` install, `-u` upgrade, `-r`/`-R` remove, `-U` system upgrade, `-Q`/`-l`/`-O` queries |
| `amu-resolv` | dependency graph queries (`-d`/`-dd`/`-D`/`-DD`/`-j`/`-jj`) |
| `amu-trigger` | post-install system cache/database triggers |
| `reposync` | git repo sync driven by `REPOSYNC_*` environment variables |
| `updateconf` | interactive `.new` config file merge tool |
| `genfstab` | generate fstab(5) from a mounted system |
| `qlchroot` | enter a chroot with /dev, /proc, /sys, /run bind-mounted |

## The abuild recipe

Unchanged from autils/Alice Linux; see `doc/recipe.md`. A minimal
recipe:

```sh
name=mypkg
version=1.2.3
release=1
source="https://example.com/$name-$version.tar.gz"
```

## License

MIT, see [LICENSE](./LICENSE).
