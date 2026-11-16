# libam.sh - common library for amutils
# (C) 2026 Atarwn Gard <atarwn@qwaderton.org>
# inspired by autils by emmett1
# MIT License

AMU_ROOT=${AMU_ROOT:-/}
AMU_PKGDB=${AMU_ROOT%/}/var/lib/spm/db

AMU_CONF=${AMU_CONF:-/etc/amu.conf}
[ -z "$AMU_NOCONF" ] && [ -f "$AMU_CONF" ] && . "$AMU_CONF"

AMU_PACKAGE_DIR_SET=${AMU_PACKAGE_DIR+x}
AMU_SOURCE_DIR_SET=${AMU_SOURCE_DIR+x}
[ -z "$AMU_PACKAGE_DIR_SET" ] && AMU_PACKAGE_DIR=$PWD
[ -z "$AMU_SOURCE_DIR_SET" ] && AMU_SOURCE_DIR=$PWD
AMU_WORK_DIR=${AMU_WORK_DIR:-$PWD}
AMU_SHA=${AMU_SHA:-b3sum}
AMU_BIN=${AMU_BIN:-amu-bin}
AMU_RESOLV=${AMU_RESOLV:-amu-resolv}
AMU_TRIGGER=${AMU_TRIGGER:-amu-trigger}

amu_needsha() {
	command -v "$AMU_SHA" >/dev/null || amu_die "$AMU_SHA not found. Set AMU_SHA to an available checksum tool."
}

amu_msg() {
	printf '%s\n' "[${AMU_PROG:-amu}] $*" >&2
}

amu_die() {
	[ "$1" ] && printf '%s\n' "error: $1" >&2
	exit 1
}

amu_needroot() {
	[ "$(id -u)" = 0 ] || amu_die "this operation requires root access"
}

amu_prompt() {
	[ "$AMU_NOPROMPT" ] && return 0
	amu_msg "press ENTER to continue, Ctrl+C to abort"
	read -r _amu_null
}

amu_list_has() {
	_amu_l=
	for _amu_i in $1; do
		_amu_l="$_amu_l $_amu_i"
	done
	case "$_amu_l " in
		*" $2 "*) return 0 ;;
	esac
	return 1
}

amu_is_installed() {
	[ -s "$AMU_PKGDB/$1" ]
}

amu_installed_ver() {
	head -n1 "$AMU_PKGDB/$1" 2>/dev/null
}

amu_installed_list() {
	ls -1 "$AMU_PKGDB" 2>/dev/null
}

amu_solve_alias() {
	[ "$AMU_ALIAS" ] || { printf '%s\n' "$@"; return; }
	while [ "$1" ]; do
		_amu_a=
		for _amu_p in $AMU_ALIAS; do
			case $_amu_p in
				"$1":*) _amu_a=${_amu_p#*:} ;;
			esac
		done
		printf '%s\n' "${_amu_a:-$1}"
		shift
	done
}

amu_recipe_dir() {
	[ "$AMU_REPO" ] || amu_die "AMU_REPO is not set"
	for _amu_r in $AMU_REPO; do
		if [ -f "$_amu_r/$1/abuild" ]; then
			printf '%s\n' "$_amu_r/$1"
			return 0
		fi
	done
	return 1
}

amu_all_recipes() {
	[ "$AMU_REPO" ] || amu_die "AMU_REPO is not set"
	for _amu_r in $AMU_REPO; do
		[ -d "$_amu_r" ] || continue
		for _amu_d in "$_amu_r"/*/; do
			[ -f "$_amu_d/abuild" ] && printf '%s\n' "${_amu_d%/}"
		done
	done
}

amu_recipe_meta() {
	_amu_d=$(amu_recipe_dir "$1") || return 1
	( . "$_amu_d/abuild" 2>/dev/null && printf '%s %s %s\n' "$name" "$version" "$release" )
}

amu_recipe_deps() {
	_amu_d=$(amu_recipe_dir "$1") || return 1
	_amu_deps=
	[ -s "$_amu_d/depends" ] && _amu_deps=$(grep -Ev '^(#|$)' "$_amu_d/depends" | awk '{print $1}')
	if [ "$2" ] && [ -s "$_amu_d/makedepends" ]; then
		_amu_deps="$_amu_deps $(grep -Ev '^(#|$)' "$_amu_d/makedepends" | awk '{print $1}')"
	fi
	[ "$_amu_deps" ] && amu_solve_alias $_amu_deps
}

amu_recipe_field() {
	_amu_d=$(amu_recipe_dir "$1") || return 1
	[ -f "$_amu_d/info" ] || return 1
	sed -n "s/^$2:[[:space:]]*//p" "$_amu_d/info" | head -n1
}

amu_source_name() {
	_amu_s=${1%::noextract}
	case $_amu_s in
		*::*) printf '%s\n' "${_amu_s%%::*}" ;;
		http://*|https://*|ftp://*) printf '%s\n' "${_amu_s##*/}" ;;
	esac
}

# print what -R would remove: unneeded deps first, then targets
amu_removal_plan() {
	_amu_closure=$("$AMU_RESOLV" -D "$@") || return 1
	_amu_remove=
	for _amu_p in "$@"; do
		amu_is_installed "$_amu_p" || {
			amu_msg "package '$_amu_p' is not installed. skipping."
			continue
		}
		_amu_ok=1
		for _amu_d in $("$AMU_RESOLV" -j "$_amu_p"); do
			[ "$_amu_d" = "$_amu_p" ] && continue
			amu_is_installed "$_amu_d" || continue
			amu_list_has "$_amu_closure" "$_amu_d" && continue
			amu_msg "package '$_amu_p' is required by installed package '$_amu_d'. skipping."
			_amu_ok=0
			break
		done
		[ "$_amu_ok" = 1 ] && _amu_remove="$_amu_remove $_amu_p"
	done
	_amu_deps=
	for _amu_c in $_amu_closure; do
		amu_list_has "$_amu_remove" "$_amu_c" && continue
		amu_is_installed "$_amu_c" || continue
		_amu_needed=0
		for _amu_d in $("$AMU_RESOLV" -j "$_amu_c"); do
			[ "$_amu_d" = "$_amu_c" ] && continue
			amu_is_installed "$_amu_d" || continue
			amu_list_has "$_amu_closure" "$_amu_d" && continue
			_amu_needed=1
			break
		done
		[ "$_amu_needed" = 0 ] && _amu_deps="$_amu_deps $_amu_c"
	done
	printf '%s\n' $_amu_deps $_amu_remove | grep -v '^$'
}

amu_cmd_purge() {
	_amu_doit=
	_amu_pkgs=
	for _amu_a; do
		case $_amu_a in
			--do-it) _amu_doit=1 ;;
			-h) printf 'usage: amu purge [--do-it] <pkg...>\n'; return 0 ;;
			*) _amu_pkgs="$_amu_pkgs $_amu_a" ;;
		esac
	done
	[ "$_amu_pkgs" ] || { amu_msg "no package specified"; return 1; }
	if [ "$_amu_doit" ]; then
		exec "$AMU_BIN" -R $_amu_pkgs
	fi
	_amu_plan=$(amu_removal_plan $_amu_pkgs) || return 1
	if [ "$_amu_plan" ]; then
		printf '%s\n' "$_amu_plan"
	else
		amu_msg "nothing to remove."
	fi
}

amu_cmd_orphan() {
	for _amu_i in $(amu_installed_list); do
		amu_recipe_dir "$_amu_i" >/dev/null 2>&1 || continue
		_amu_orphan=1
		for _amu_p in $("$AMU_RESOLV" -j "$_amu_i"); do
			if amu_is_installed "$_amu_p"; then
				_amu_orphan=0
				break
			fi
		done
		[ "$_amu_orphan" = 1 ] && printf '%s\n' "$_amu_i"
	done
}

amu_cmd_foreign() {
	for _amu_i in $(amu_installed_list); do
		amu_recipe_dir "$_amu_i" >/dev/null 2>&1 || printf '%s\n' "$_amu_i"
	done
}

amu_cmd_mdpurge() {
	_amu_doit= _amu_pkgs=
	for _amu_a; do
		case $_amu_a in
			--do-it) _amu_doit=1 ;;
			-h) printf 'usage: amu mdpurge [--do-it] [pkg...]\n'; return 0 ;;
			*) _amu_pkgs="$_amu_pkgs $_amu_a" ;;
		esac
	done
	_amu_mdeps=
	if [ "$_amu_pkgs" ]; then
		for _amu_p in $_amu_pkgs; do
			amu_is_installed "$_amu_p" || continue
			_amu_d=$(amu_recipe_dir "$_amu_p" 2>/dev/null) || continue
			[ -s "$_amu_d/makedepends" ] || continue
			_amu_mdeps="$_amu_mdeps $(grep -Ev '^(#|$)' "$_amu_d/makedepends" | awk '{print $1}')"
		done
	else
		for _amu_p in $(amu_installed_list); do
			_amu_d=$(amu_recipe_dir "$_amu_p" 2>/dev/null) || continue
			[ -s "$_amu_d/makedepends" ] || continue
			_amu_mdeps="$_amu_mdeps $(grep -Ev '^(#|$)' "$_amu_d/makedepends" | awk '{print $1}')"
		done
	fi
	for _amu_m in $(printf '%s\n' $_amu_mdeps | sort -u); do
		[ "$_amu_m" ] || continue
		amu_is_installed "$_amu_m" || continue
		_amu_err=
		for _amu_d in $("$AMU_RESOLV" -j "$_amu_m"); do
			if amu_is_installed "$_amu_d"; then
				_amu_err=1
				break
			fi
		done
		[ "$_amu_err" ] && continue
		if [ "$_amu_doit" ]; then
			"$AMU_BIN" -r "$_amu_m"
		else
			printf '%s\n' "$_amu_m"
		fi
	done
}

amu_cmd_clean() {
	_amu_pkgs=1 _amu_srcs=1
	for _amu_a; do
		case $_amu_a in
			-p) _amu_srcs=0 ;;
			-s) _amu_pkgs=0 ;;
			-h) printf 'usage: amu clean [-p|-s] | xargs rm -v\n'; return 0 ;;
		esac
	done
	_amu_keep_pkg=$(for _amu_d in $(amu_all_recipes); do
		name= version= release=
		. "$_amu_d/abuild" 2>/dev/null
		[ "$name" ] && [ "$version" ] && [ "$release" ] && printf '%s\n' "$name#$version-$release.spm"
	done)
	_amu_keep_src=$(for _amu_d in $(amu_all_recipes); do
		source=
		. "$_amu_d/abuild" 2>/dev/null
		for _amu_s in $source; do
			amu_source_name "$_amu_s"
		done
	done)
	if [ "$_amu_pkgs" = 1 ]; then
		if [ "$AMU_PACKAGE_DIR_SET" ]; then
			for _amu_f in "$AMU_PACKAGE_DIR"/*.spm; do
				[ -f "$_amu_f" ] || continue
				amu_list_has "$_amu_keep_pkg" "${_amu_f##*/}" && continue
				printf '%s\n' "$_amu_f"
			done
		else
			for _amu_d in $(amu_all_recipes); do
				name= version= release=
				. "$_amu_d/abuild" 2>/dev/null
				_amu_cur="$name#$version-$release.spm"
				for _amu_f in "$_amu_d"/*.spm; do
					[ -f "$_amu_f" ] || continue
					[ "${_amu_f##*/}" = "$_amu_cur" ] && continue
					printf '%s\n' "$_amu_f"
				done
			done
		fi
	fi
	if [ "$_amu_srcs" = 1 ]; then
		if [ "$AMU_SOURCE_DIR_SET" ]; then
			for _amu_f in "$AMU_SOURCE_DIR"/*; do
				[ -f "$_amu_f" ] || continue
				amu_list_has "$_amu_keep_src" "${_amu_f##*/}" && continue
				printf '%s\n' "$_amu_f"
			done
		else
			for _amu_d in $(amu_all_recipes); do
				source=
				. "$_amu_d/abuild" 2>/dev/null
				_amu_keep=
				for _amu_s in $source; do
					_amu_keep="$_amu_keep $(amu_source_name "$_amu_s")"
				done
				for _amu_f in "$_amu_d"/*; do
					[ -f "$_amu_f" ] || continue
					case ${_amu_f##*/} in
						abuild|depends|makedepends|preinstall|postinstall|info|*.spm|.shasum|.files) continue ;;
					esac
					amu_list_has "$_amu_keep" "${_amu_f##*/}" && continue
					printf '%s\n' "$_amu_f"
				done
			done
		fi
	fi
}

amu_cmd_deps() {
	if [ ! "$1" ] || [ "$2" ]; then
		printf 'usage: amu deps <pkg>\n' >&2
		return 1
	fi
	amu_is_installed "$1" || { amu_msg "package '$1' not installed"; return 1; }
	_amu_libs=
	for _amu_f in $("$AMU_BIN" -l "$1" | awk '/(sbin|bin|lib)\//'); do
		[ -x "${AMU_ROOT%/}/$_amu_f" ] || continue
		_amu_libs="$_amu_libs $(ldd "${AMU_ROOT%/}/$_amu_f" 2>/dev/null | awk '!/(ldd)|(linux-gate)|( dynamic)|(not found)/ {print $3}')"
	done
	_amu_pkgs=
	for _amu_i in $(for _amu_i in $_amu_libs; do realpath "$_amu_i" 2>/dev/null; done | sort -u); do
		_amu_o=$("$AMU_BIN" -O "^${_amu_i#/}" | head -n1 | awk '{print $1}')
		[ "$_amu_o" ] || continue
		amu_list_has "$1 gcc musl binutils glibc" "$_amu_o" && continue
		amu_list_has "$_amu_pkgs" "$_amu_o" || _amu_pkgs="$_amu_pkgs $_amu_o"
	done
	[ "$_amu_pkgs" ] && printf '%s\n' $_amu_pkgs
}

amu_cmd_redundantdeps() {
	_amu_fix=
	_amu_pkgs=
	for _amu_a; do
		case $_amu_a in
			-f) _amu_fix=1 ;;
			-h) printf 'usage: amu redundantdeps [-f] [pkg...]\n'; return 0 ;;
			*) _amu_pkgs="$_amu_pkgs $_amu_a" ;;
		esac
	done
	if [ ! "$_amu_pkgs" ]; then
		_amu_seen=
		for _amu_d in $(amu_all_recipes); do
			_amu_n=${_amu_d##*/}
			amu_list_has "$_amu_seen" "$_amu_n" && continue
			_amu_seen="$_amu_seen $_amu_n"
			_amu_pkgs="$_amu_pkgs $_amu_n"
		done
	fi
	for _amu_i in $_amu_pkgs; do
		_amu_deps=$("$AMU_RESOLV" -d "$_amu_i" 2>/dev/null)
		[ "$_amu_deps" ] || continue
		for _amu_d in $_amu_deps; do
			for _amu_dd in $_amu_deps; do
				[ "$_amu_dd" = "$_amu_d" ] && continue
				if "$AMU_RESOLV" -D "$_amu_d" 2>/dev/null | grep -qx "$_amu_dd"; then
					printf '[%s] %s (already pulled from %s)\n' "$_amu_i" "$_amu_dd" "$_amu_d"
					if [ "$_amu_fix" ]; then
						_amu_rd=$(amu_recipe_dir "$_amu_i") || continue
						sed -i "\|^$_amu_dd\$|d" "$_amu_rd/depends"
						amu_msg "$_amu_dd removed from $_amu_i depends"
						[ -s "$_amu_rd/depends" ] || rm -f "$_amu_rd/depends"
					fi
				fi
			done
		done
	done
}

amu_cmd_genabuild() {
	_amu_url=$1
	_amu_name=$2
	if [ ! "$_amu_url" ] || [ "$_amu_url" = '-h' ]; then
		printf 'usage: amu genabuild <url> [name]\n'
		return 1
	fi
	if [ ! "$_amu_name" ]; then
		_amu_name=$(printf '%s\n' "$_amu_url" | rev | cut -d / -f1 | cut -d - -f2- | rev | tr '[:upper:]' '[:lower:]')
		_amu_version=$(printf '%s\n' "$_amu_url" | rev | cut -d / -f1 | cut -d - -f1 | rev | sed 's/\.tar.*//;s/^v//')
		case $_amu_url in
			*.pythonhosted.*|*/pypi.org/*) _amu_name="python-$_amu_name" ;;
			*.metacpan.*|*.cpan.*) _amu_name="perl-$_amu_name" ;;
			*/refs/tags/*)
				_amu_gh=${_amu_url%/archive*}
				_amu_name=${_amu_gh##*/}
				_amu_vs=${_amu_url##*/}
				_amu_vs=${_amu_vs%.tar.*}
				_amu_version=${_amu_vs#v}
				_amu_url=$_amu_gh/archive/$_amu_vs/$_amu_name-${_amu_url##*/} ;;
		esac
	else
		_amu_version=$(printf '%s\n' "$_amu_url" | rev | cut -d / -f1 | cut -d - -f1 | rev | sed 's/\.tar.*//;s/^v//')
	fi
	_amu_name=$(printf '%s\n' "$_amu_name" | tr '[:upper:]' '[:lower:]')
	if [ -d "$_amu_name" ]; then
		grep ^version= "$_amu_name/abuild" 2>/dev/null
		printf 'port for %s exist\n' "$_amu_name"
		return 1
	fi
	_amu_url=$(printf '%s\n' "$_amu_url" | sed "s,$_amu_name,\${name},g;s,$_amu_version,\${version},g")
	case $_amu_version in
		*.*.*) _amu_v=${_amu_version%.*}
			_amu_url=$(printf '%s\n' "$_amu_url" | sed "s,$_amu_v,\${version%.*},g") ;;
	esac
	mkdir -p "$_amu_name"
	printf 'name=%s\nversion=%s\nrelease=1\nsource="%s"\n' \
		"$_amu_name" "$_amu_version" "$_amu_url" > "$_amu_name/abuild"
	cat > "$_amu_name/info" << EOF
description:
homepage:
license:
maintainer: Atarwn Gard <atarwn@qwaderton.org>
EOF
	cat "$_amu_name/abuild"
}

amu_cmd_revdep() {
	_amu_verbose=
	for _amu_a; do
		case $_amu_a in
			-v) _amu_verbose=1 ;;
			-h) printf 'usage: amu revdep [-v]\n'; return 0 ;;
		esac
	done
	_amu_search="/bin /usr/bin /sbin /usr/sbin /lib /usr/lib /usr/libexec"
	[ -d /etc/revdep.d ] && [ "$(ls -1 /etc/revdep.d 2>/dev/null)" ] && {
		for _amu_l in $(cat /etc/revdep.d/*); do
			LD_LIBRARY_PATH="$_amu_l:$LD_LIBRARY_PATH"
		done
		export LD_LIBRARY_PATH
	}
	_amu_tmp=$(mktemp) || return 1
	trap 'rm -f "$_amu_tmp"; printf "\033[0K"; exit 1' 1 2 3 15
	find $_amu_search -type f \( -perm -u+x -o -perm -g+x -o -perm -o+x -o -name '*.so' -o -name '*.so.*' \) -print 2>/dev/null | sort -u > "$_amu_tmp"
	_amu_total=$(wc -l < "$_amu_tmp" | awk '{print $1}')
	_amu_count=0
	_amu_reported=
	while IFS= read -r _amu_line; do
		_amu_count=$((_amu_count + 1))
		_amu_lib=${_amu_line##*/}
		if [ "$_amu_verbose" ]; then
			printf ' %d%% %s\033[0K\r' $((100 * _amu_count / _amu_total)) "$_amu_lib"
		fi
		case $(file -b "$_amu_line") in
			*ELF*)
				if [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /usr/lib/ld-musl-x86_64.so.1 ]; then
					_amu_missing=$(ldd "$_amu_line" 2>&1 | grep "Error loading shared library" | awk '{print $5}' | sed 's/://' | sort -u)
				else
					_amu_missing=$(ldd "$_amu_line" 2>&1 | grep "not found" | awk '{print $1}' | sort -u)
				fi
				for _amu_i in $_amu_missing; do
					objdump -p "$_amu_line" | grep NEEDED | awk '{print $2}' | grep -Fqx "$_amu_i" || continue
					_amu_own=$("$AMU_BIN" -O "^${_amu_line#/}" | head -n1 | awk '{print $1}')
					[ "$_amu_own" ] || continue
					if [ "$_amu_verbose" ]; then
						printf ' %s: %s (requires %s)\n' "$_amu_own" "$_amu_line" "$_amu_i"
					elif ! amu_list_has "$_amu_reported" "$_amu_own"; then
						printf '%s\n' "$_amu_own"
						_amu_reported="$_amu_reported $_amu_own"
					fi
				done ;;
		esac
	done < "$_amu_tmp"
	printf '\033[0K'
	rm -f "$_amu_tmp"
	trap - 1 2 3 15
}
