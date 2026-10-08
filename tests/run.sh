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

# Note: src/rosaria is a submodule declared in .gitmodules, but the UNTARGETED
# `git submodule update --init` is still not used here: initialise the declared
# submodule by path, as above. (The historical src/waypoints gitlink - the one
# that used to make the untargeted command abort - is gone: it is now in-tree
# content written as a DECLARED RECONSTRUCTION. See section 8.)
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

# --- 8. the waypoints package: a DECLARED RECONSTRUCTION -------------------
# src/waypoints used to be a gitlink (index mode 160000) pointing at commit
# 115553cfa8c2ace122414ac5a9b235cd2e225693, and that code does not exist in any
# known remote - the ORIGINAL is lost for good. It is now plain in-tree content,
# written from the clues that survived this repository and declared as a
# reconstruction (src/waypoints/README.md).
#
# What these checks prove: the package is complete, the node it ships is the one
# guide.txt runs, it is executable, and its Python parses. What they CANNOT
# prove: that it runs, that a workspace builds (there is no ROS here), or that
# the interface is the original one - the topics are inferred, not recovered.
wp=src/waypoints

# 8a. the gitlink is gone: the path must be in-tree content now
wpmode=$(git ls-tree HEAD src/waypoints 2>/dev/null | awk '{print $1}' | head -1)
if [ "$wpmode" = "160000" ]; then
	fail "waypoints-still-gitlink" "$wp is still a gitlink (mode 160000): its code lives elsewhere and a clean clone brings an empty directory"
elif [ -n "$wpmode" ]; then
	pass "waypoints-in-tree" "$wp is tracked as in-tree content (mode $wpmode), not as a gitlink"
else
	fail "waypoints-in-tree" "$wp is not tracked in the index at all"
fi

# 8b. the node name is read FROM guide.txt, never hard-coded in this suite
wpnode=$(sed -n 's/.*rosrun[[:space:]][[:space:]]*waypoints[[:space:]][[:space:]]*\([^[:space:]]\{1,\}\).*/\1/p' guide.txt 2>/dev/null | head -1 | tr -d '\r')
if [ -z "$wpnode" ]; then
	fail "waypoints-guide-node" "guide.txt no longer shows 'rosrun waypoints <node>'; this suite lost its anchor"
else
	pass "waypoints-guide-node" "guide.txt runs 'rosrun waypoints $wpnode'"
fi

# 8c. package.xml + CMakeLists.txt (section 1 covers tracked packages in
# general; this repeats it for waypoints so the reconstruction is checked even
# if that general check is ever loosened)
if [ -f "$wp/package.xml" ]; then
	wpname=$(sed -n 's:.*<name>[[:space:]]*\([^<]*\)</name>.*:\1:p' "$wp/package.xml" | head -1 | tr -d ' \t\r')
	if [ "$wpname" = "waypoints" ]; then
		pass "waypoints-package-xml" "$wp/package.xml declares <name>waypoints</name>"
	else
		fail "waypoints-package-xml" "$wp/package.xml declares <name>${wpname:-<nothing>}</name>, expected 'waypoints' (the name in guide.txt)"
	fi
else
	fail "waypoints-package-xml" "$wp has no package.xml"
fi
if [ -f "$wp/CMakeLists.txt" ]; then
	pass "waypoints-cmakelists" "$wp/CMakeLists.txt exists"
else
	fail "waypoints-cmakelists" "$wp has no CMakeLists.txt"
fi

# 8d. the executable guide.txt names, executable and self-consistent
wpnode_path=""
if [ -n "$wpnode" ]; then
	for cand in "$wp/scripts/$wpnode" "$wp/bin/$wpnode" "$wp/$wpnode"; do
		if [ -f "$cand" ]; then wpnode_path="$cand"; break; fi
	done
fi
pyfiles=""
if [ -n "$wpnode_path" ]; then
	pass "waypoints-node-present" "the node guide.txt runs is at $wpnode_path"
	nodemode=$(git ls-files -s -- "$wpnode_path" | awk '{print $1}' | head -1)
	if [ "$nodemode" = "100755" ] && [ -x "$wpnode_path" ]; then
		pass "waypoints-node-executable" "$wpnode_path is executable (index mode 100755 and +x on disk), so rosrun can find it"
	else
		fail "waypoints-node-executable" "$wpnode_path has index mode ${nodemode:-<untracked>} and is$( [ -x "$wpnode_path" ] || printf ' not') +x; rosrun needs an executable"
	fi
	if head -1 -- "$wpnode_path" 2>/dev/null | grep -q '^#!.*python'; then
		pyfiles="$pyfiles $wpnode_path"
		if grep -q "init_node(['\"]$wpnode['\"]" "$wpnode_path"; then
			pass "waypoints-node-name" "$wpnode_path initialises the node as '$wpnode', the name guide.txt runs"
		else
			fail "waypoints-node-name" "$wpnode_path does not call init_node('$wpnode')"
		fi
	elif grep -q "ros::init([^;]*[\"']$wpnode[\"']" "$wpnode_path" 2>/dev/null; then
		pass "waypoints-node-name" "$wpnode_path initialises the node as '$wpnode', the name guide.txt runs"
	else
		fail "waypoints-node-name" "$wpnode_path initialises no node named '$wpnode' (neither init_node nor ros::init)"
	fi
else
	fail "waypoints-node-present" "no executable named '${wpnode:-<unknown>}' under $wp (scripts/, bin/ or the package root)"
fi

# 8e. every Python file in the package parses (python3 -m py_compile, with the
# .pyc thrown away in a temp dir so the tree stays clean), or - if the package
# is C++ - it has the obvious ROS structure. Neither proves it BUILDS.
while IFS= read -r f; do
	[ -f "$f" ] || continue
	case "$f" in
		*.py) pyfiles="$pyfiles $f" ;;
	esac
done < <(git ls-files -- "$wp")
pyfiles=$(printf '%s\n' $pyfiles | sort -u | tr '\n' ' ')
if [ -n "${pyfiles// /}" ]; then
	if command -v python3 >/dev/null 2>&1; then
		pycdir=$(mktemp -d)
		badpy=""
		for f in $pyfiles; do
			if ! python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
					"$f" "$pycdir/out.pyc" >/dev/null 2>&1; then
				badpy="$badpy $f"
			fi
		done
		rm -rf "$pycdir"
		if [ -z "$badpy" ]; then
			pass "waypoints-python-syntax" "python3 -m py_compile accepts:$pyfiles"
		else
			fail "waypoints-python-syntax" "python3 -m py_compile rejects:$badpy"
		fi
	else
		note "waypoints-python-syntax" "python3 is not available, syntax check skipped"
	fi
else
	cppfiles=$(git ls-files -- "$wp" | grep -E '\.(cpp|cc|cxx)$' | tr '\n' ' ')
	if [ -n "${cppfiles// /}" ]; then
		badcpp=""
		for f in $cppfiles; do
			if ! grep -q '#include *<ros/ros.h>' "$f" || ! grep -q 'int *main' "$f"; then
				badcpp="$badcpp $f"
			fi
		done
		if [ -z "$badcpp" ]; then
			pass "waypoints-cpp-structure" "every C++ source includes <ros/ros.h> and defines main():$cppfiles"
		else
			fail "waypoints-cpp-structure" "C++ source without the obvious ROS structure:$badcpp"
		fi
	else
		fail "waypoints-node-source" "$wp has no Python file and no C++ source"
	fi
fi

# 8f. the reconstruction must declare itself and name the sha it replaces
if [ -f "$wp/README.md" ]; then
	if grep -qi 'reconstruct' "$wp/README.md"; then
		pass "waypoints-declared" "$wp/README.md calls the package a reconstruction"
	else
		fail "waypoints-declared" "$wp/README.md does not call the package a reconstruction"
	fi
	sha=115553cfa8c2ace122414ac5a9b235cd2e225693
	if grep -q "$sha" "$wp/README.md" && grep -q "$sha" "$wp/package.xml"; then
		pass "waypoints-declares-lost-sha" "the lost gitlink commit $sha is named in $wp/README.md and $wp/package.xml"
	else
		fail "waypoints-declares-lost-sha" "the lost gitlink commit $sha is not named in both $wp/README.md and $wp/package.xml"
	fi
else
	fail "waypoints-declared" "$wp has no README.md declaring the package a reconstruction"
fi
if grep -q 'src/waypoints/README.md' README.md 2>/dev/null; then
	pass "waypoints-repo-readme" "the repository README points at src/waypoints/README.md"
else
	fail "waypoints-repo-readme" "the repository README does not point at src/waypoints/README.md"
fi

# 8g. and git itself must no longer complain about a gitlink with no mapping:
# this is the check that the empty-directory-in-a-clean-clone problem is gone
if git submodule status >/dev/null 2>&1; then
	pass "submodule-status-clean" "'git submodule status' succeeds: no gitlink in the index lacks a .gitmodules mapping"
else
	fail "submodule-status-clean" "'git submodule status' still fails: $(git submodule status 2>&1 | tr '\n' ' ' | tr -s ' ')"
fi
echo

if [ "$failed" -eq 0 ]; then
	echo "ALL CHECKS PASSED"
	exit 0
fi
echo "SOME CHECKS FAILED"
exit 1
