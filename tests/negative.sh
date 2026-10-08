#!/usr/bin/env bash
#
# tests/negative.sh - proves that tests/run.sh has teeth.
#
# Each case copies the working tree into a temporary directory, breaks exactly
# one thing THERE, and asserts that tests/run.sh then fails with the expected
# check id. Nothing in the real repository is modified: every mutation happens
# in the throwaway copy (one of them even commits there, to turn src/waypoints
# back into a gitlink).
#
# Usage: tests/negative.sh
# Exit status: 0 = every case behaved as expected.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true
if [ -z "${ROOT:-}" ]; then
	printf 'tests/negative.sh: not inside a git work tree\n' >&2
	exit 2
fi
cd "$ROOT" || exit 2

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fails=0

# --- mutations, each executed with the throwaway copy as cwd ---------------

mut_none() { :; }

# make src/rosaria an undeclared gitlink again (its .gitmodules section gone)
mut_drop_rosaria_entry() {
	awk '
		/^\[submodule "src\/rosaria"\]/ { skip = 1; next }
		/^\[/ { skip = 0 }
		!skip { print }
	' .gitmodules > .gitmodules.new
	mv .gitmodules.new .gitmodules
}

# no .gitmodules at all
mut_hide_gitmodules() { mv .gitmodules .gitmodules.hidden; }

# an entry that matches no gitlink
mut_add_orphan_entry() {
	{
		printf '\n[submodule "src/does-not-exist"]\n'
		printf '\tpath = src/does-not-exist\n'
		printf '\turl = https://example.invalid/does-not-exist.git\n'
	} >> .gitmodules
}

# a declared package that lost a required file
mut_break_package() { mv src/robot/CMakeLists.txt src/robot/CMakeLists.txt.hidden; }

# --- the waypoints package (the declared reconstruction) -------------------

# the node that guide.txt runs is gone
mut_drop_waypoints_node() { rm -f src/waypoints/scripts/waypoints_server; }

# the package lost its package.xml
mut_drop_waypoints_package_xml() { mv src/waypoints/package.xml src/waypoints/package.xml.hidden; }

# the node is not executable any more, so rosrun would not run it
mut_waypoints_node_not_executable() { chmod -x src/waypoints/scripts/waypoints_server; }

# the node no longer initialises itself under the name guide.txt runs
mut_waypoints_node_renamed() {
	sed -i "s/init_node('waypoints_server')/init_node('something_else')/" \
		src/waypoints/scripts/waypoints_server
}

# the node stops being valid Python
mut_waypoints_syntax_error() {
	printf '\ndef broken(:\n' >> src/waypoints/scripts/waypoints_server
}

# the reconstruction stops declaring itself
mut_waypoints_no_declaration() { rm -f src/waypoints/README.md; }

# the fix is undone: src/waypoints goes back to being a gitlink with no content
mut_waypoints_back_to_gitlink() {
	rm -rf src/waypoints
	git rm -r --cached --quiet src/waypoints >/dev/null 2>&1
	git update-index --add --cacheinfo \
		160000,115553cfa8c2ace122414ac5a9b235cd2e225693,src/waypoints
	git -c user.name=negative -c user.email=negative@invalid commit \
		--quiet -m "back to a gitlink" >/dev/null 2>&1
}

# --- runner ---------------------------------------------------------------

case_expect() {
	local label=$1 expect=$2
	local dir="$TMP/$label"
	mkdir -p "$dir"
	cp -a "$ROOT/." "$dir/"
	( cd "$dir" && "$label" )

	local out rc
	out=$(cd "$dir" && tests/run.sh 2>&1)
	rc=$?

	printf -- '--- %s ---\n' "$label"
	if [ "$expect" = "PASS" ]; then
		if [ "$rc" -eq 0 ]; then
			printf '  PASS  run.sh exited 0 as expected\n'
		else
			printf '  FAIL  run.sh exited %s, expected 0\n' "$rc"
			printf '%s\n' "$out" | sed 's/^/        /'
			fails=$((fails + 1))
		fi
		return 0
	fi
	if [ "$rc" -eq 0 ]; then
		printf '  FAIL  run.sh exited 0, but [%s] was expected to fail\n' "$expect"
		fails=$((fails + 1))
	elif printf '%s\n' "$out" | grep -q "FAIL \[$expect\]"; then
		printf '  PASS  run.sh failed with [%s] (exit %s)\n' "$expect" "$rc"
	else
		printf '  FAIL  run.sh failed, but without the expected id [%s]\n' "$expect"
		printf '%s\n' "$out" | sed 's/^/        /'
		fails=$((fails + 1))
	fi
	return 0
}

echo "== negative tests for tests/run.sh =="
echo

# The positive control runs first: on an untouched copy the suite must be green,
# so any failure below really is caused by the mutation and not by a broken suite.
case_expect mut_none PASS
case_expect mut_drop_rosaria_entry gitlink-undeclared
case_expect mut_hide_gitmodules gitmodules-missing
case_expect mut_add_orphan_entry gitmodules-orphan
case_expect mut_break_package cmakelists-missing
case_expect mut_drop_waypoints_node waypoints-node-present
case_expect mut_drop_waypoints_package_xml waypoints-package-xml
case_expect mut_waypoints_node_not_executable waypoints-node-executable
case_expect mut_waypoints_node_renamed waypoints-node-name
case_expect mut_waypoints_syntax_error waypoints-python-syntax
case_expect mut_waypoints_no_declaration waypoints-declared
case_expect mut_waypoints_back_to_gitlink waypoints-still-gitlink

echo
if [ "$fails" -eq 0 ]; then
	echo "ALL NEGATIVE CASES BEHAVED AS EXPECTED"
	exit 0
fi
printf '%s negative case(s) did not behave as expected\n' "$fails"
exit 1
