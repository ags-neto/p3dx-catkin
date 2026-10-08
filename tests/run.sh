#!/usr/bin/env bash
#
# tests/run.sh - integrity checks for a clean clone of p3dx-catkin.
#
# These checks verify what CAN be verified without ROS: that a fresh clone
# brings real code instead of empty submodule directories, that every package
# recorded in the index is complete, and that every in-tree <depend> points at
# a package that actually exists.
#
# What this does NOT prove: that the workspace builds. There is no ROS in the
# environment where these checks were written, so catkin_make was never run.
#
# Usage, from a clean clone:
#     git clone <url> p3dx-catkin
#     cd p3dx-catkin
#     git submodule update --init -- src/rosaria
#     tests/run.sh
#
# Exit status: 0 = every check passed; non-zero = at least one check failed.

# Note: src/waypoints is a gitlink with no .gitmodules mapping (see
# tests/known-gaps.txt), and that makes the UNTARGETED `git submodule
# update --init` abort. Initialise the declared submodule by path, as above.
#
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true
if [ -z "${ROOT:-}" ]; then
	printf 'tests/run.sh: not inside a git work tree\n' >&2
	exit 2
fi
cd "$ROOT" || exit 2

failed=0
pass() { printf 'PASS [%s] %s\n' "$1" "$2"; }
fail() { printf 'FAIL [%s] %s\n' "$1" "$2"; failed=1; }
note() { printf 'NOTE [%s] %s\n' "$1" "$2"; }

# has_word <needle> <space-separated words>
has_word() {
	case " ${2:-} " in
		*" $1 "*) return 0 ;;
		*) return 1 ;;
	esac
}

# Read a one-column list file, skipping blanks and # comments.
read_list() {
	[ -f "$1" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
			'' | '#'*) continue ;;
		esac
		printf '%s\n' "$line"
	done < "$1"
}

known=$(read_list tests/known-gaps.txt | tr '\n' ' ')

echo "== p3dx-catkin integrity checks =="
echo "root: $ROOT"
echo

# --- 1. every package directory in the index is complete -------------------
npkg=0
allnames=""
while IFS=$'\t' read -r meta path; do
	[ "${meta%% *}" = "040000" ] || continue
	npkg=$((npkg + 1))
	if [ ! -f "$path/package.xml" ]; then
		fail "package-xml-missing" "$path has no package.xml"
		continue
	fi
	if [ ! -f "$path/CMakeLists.txt" ]; then
		fail "cmakelists-missing" "$path has no CMakeLists.txt"
	fi
	declared_name=$(sed -n 's:.*<name>[[:space:]]*\([^<]*\)</name>.*:\1:p' "$path/package.xml" 2>/dev/null | head -1 | tr -d ' \t\r')
	if [ -z "$declared_name" ]; then
		fail "package-name-missing" "$path/package.xml declares no <name>"
	elif has_word "$declared_name" "$allnames"; then
		fail "package-name-duplicate" "the package name '$declared_name' is declared by more than one package.xml"
	fi
	# NB: in catkin the directory name need not equal the package name -
	# src/ros_astra_camera declares <name>astra_camera</name> - so the two are
	# deliberately NOT compared.
	allnames="$allnames $declared_name"
done < <(git ls-tree HEAD src/)

if [ "$npkg" -gt 0 ]; then
	pass "packages-complete" "$npkg package directories in the index have package.xml + CMakeLists.txt"
else
	fail "no-packages" "no package directories found under src/ in the index"
fi
echo

# --- 2. src/CMakeLists.txt is the catkin toplevel symlink ------------------
sl=$(git ls-tree HEAD src/CMakeLists.txt)
if [ -z "$sl" ]; then
	fail "toplevel-missing" "src/CMakeLists.txt is not tracked"
else
	slmode=${sl%% *}
	slsha=$(printf '%s' "$sl" | awk '{print $3}')
	if [ "$slmode" != "120000" ]; then
		fail "toplevel-not-symlink" "src/CMakeLists.txt is mode $slmode, expected 120000 (catkin toplevel symlink)"
	else
		sltarget=$(git cat-file blob "$slsha" 2>/dev/null)
		case "$sltarget" in
			*catkin/cmake/toplevel.cmake) pass "toplevel-symlink" "src/CMakeLists.txt -> $sltarget" ;;
			*) fail "toplevel-target" "src/CMakeLists.txt points at '$sltarget', expected catkin's toplevel.cmake" ;;
		esac
	fi
fi
echo

# --- 3. gitlinks vs .gitmodules -------------------------------------------
gitlinks=""
unmapped=""
while IFS=$'\t' read -r meta path; do
	[ "${meta%% *}" = "160000" ] || continue
	gitlinks="$gitlinks $path"
done < <(git ls-tree HEAD src/)
ngit=$(printf '%s' "$gitlinks" | wc -w)

declared=""
if [ -f .gitmodules ]; then
	declared=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
else
	fail "gitmodules-missing" ".gitmodules does not exist, but the index has gitlinks:$gitlinks"
fi

for p in $gitlinks; do
	if ! has_word "$p" "$declared"; then
		unmapped="$unmapped $p"
		if has_word "$p" "$known"; then
			note "gitlink-known-gap" "$p is a gitlink with no .gitmodules entry (known gap, see tests/known-gaps.txt)"
		else
			fail "gitlink-undeclared" "$p is a gitlink (mode 160000) with no .gitmodules entry"
		fi
	fi
done

for p in $declared; do
	if ! has_word "$p" "$gitlinks"; then
		fail "gitmodules-orphan" ".gitmodules declares '$p', which is not a gitlink in the index"
	fi
done

for p in $known; do
	if ! has_word "$p" "$gitlinks" || has_word "$p" "$declared"; then
		note "known-gap-stale" "tests/known-gaps.txt lists '$p', which is no longer a gap"
	fi
done

if [ -n "$unmapped" ]; then
	note "submodule-command-blocked" "unmapped gitlink(s):$unmapped - plain 'git submodule update --init' and 'git submodule status' abort; initialise the declared paths explicitly: git submodule update --init -- src/rosaria"
fi

echo "($ngit gitlink(s) in the index; $(printf '%s' "$declared" | wc -w) declared in .gitmodules)"
echo

# --- 4. the verified submodule resolves ------------------------------------
pin=$(git ls-tree HEAD src/rosaria 2>/dev/null | awk '{print $3}')
if [ -z "$pin" ]; then
	fail "rosaria-not-gitlink" "src/rosaria is not a gitlink in the index"
else
	if [ -f src/rosaria/package.xml ] && [ -f src/rosaria/CMakeLists.txt ]; then
		pass "rosaria-populated" "src/rosaria brings package.xml and CMakeLists.txt (not an empty directory)"
	else
		fail "rosaria-populated" "src/rosaria is empty - run: git submodule update --init -- src/rosaria"
	fi
	actual=""
	if [ -e src/rosaria/.git ]; then
		actual=$(git -C src/rosaria rev-parse HEAD 2>/dev/null)
	fi
	if [ -n "$actual" ]; then
		if [ "$actual" = "$pin" ]; then
			pass "rosaria-pin" "src/rosaria checked out at the pinned commit $pin"
		else
			fail "rosaria-pin" "src/rosaria is at $actual but the index pins $pin"
		fi
	else
		note "rosaria-pin" "src/rosaria has no git metadata, cannot compare against the pin $pin"
	fi
fi

# the declared URL is the one that was verified by hand
while read -r epath eurl; do
	case "$epath" in '' | '#'*) continue ;; esac
	got=$(git config -f .gitmodules --get "submodule.$epath.url" 2>/dev/null)
	if [ "$got" = "${eurl:-}" ]; then
		pass "submodule-url" "$epath is declared with the verified URL"
	else
		fail "submodule-url" "$epath is declared with '${got:-<nothing>}', expected '$eurl'"
	fi
done < <(read_list tests/expected-submodules.txt)
echo

# --- 5. in-tree <depend> entries point at packages that exist --------------
edges=0
broken=0
for d in src/*/; do
	[ -f "$d/package.xml" ] || continue
	pkg=$(basename "$d")
	for n in $(sed -n 's:.*<\(depend\|build_depend\|build_export_depend\|exec_depend\|run_depend\)>[[:space:]]*\([^<]*\)</.*:\2:p' "$d/package.xml" | tr -d ' \t\r'); do
		# only dependencies that name a directory inside this workspace
		[ -d "src/$n" ] || continue
		edges=$((edges + 1))
		if [ ! -f "src/$n/package.xml" ]; then
			broken=$((broken + 1))
			fail "dep-unresolved" "$pkg declares a dependency on '$n', but src/$n has no package.xml"
		fi
	done
done
if [ "$edges" -gt 0 ] && [ "$broken" -eq 0 ]; then
	pass "deps-in-tree" "$edges in-tree dependency edge(s) resolve to a real package"
fi

# guard against this check going vacuous: the edge that motivated all of this
if [ -f src/robot/package.xml ]; then
	if grep -q '<depend>rosaria</depend>' src/robot/package.xml; then
		pass "robot-depends-rosaria" "src/robot still declares <depend>rosaria</depend>"
	else
		fail "robot-depends-rosaria" "src/robot no longer declares <depend>rosaria</depend>; this check lost its purpose"
	fi
fi
echo

# --- 6. every package.xml is well-formed XML -------------------------------
if command -v python3 >/dev/null 2>&1; then
	badxml=$(python3 - <<'PYEOF'
import glob
import xml.etree.ElementTree as ET
for f in sorted(glob.glob('src/*/package.xml')):
    try:
        ET.parse(f)
    except Exception as exc:
        print('%s: %s' % (f, exc))
PYEOF
)
	if [ -n "$badxml" ]; then
		while IFS= read -r line; do fail "package-xml-invalid" "$line"; done <<EOS
$badxml
EOS
	else
		pass "package-xml-wellformed" "every src/*/package.xml parses as XML"
	fi
else
	note "package-xml-wellformed" "python3 is not available, XML check skipped"
fi
echo

# --- 7. every known gap is documented in the README -----------------------
for p in $known; do
	if grep -q "$(basename "$p")" README.md 2>/dev/null; then
		pass "gap-documented" "$p is documented in README.md"
	else
		fail "gap-undocumented" "$p is a known gap but README.md does not mention it"
	fi
done
echo

if [ "$failed" -eq 0 ]; then
	echo "ALL CHECKS PASSED"
	exit 0
fi
echo "SOME CHECKS FAILED"
exit 1
