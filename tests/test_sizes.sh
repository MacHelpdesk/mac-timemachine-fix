#!/bin/bash
# test_sizes — sizes expands ~ and globs with spaces, filters by MIN_GB and sorts.
#
# It calls the real `tmutil isexcluded -X`, which only reads, on temporary folders.

set -u
cd "$(dirname "$0")/.." || exit 2
TOOL=plugin/scripts/tm-fix.sh
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

mkdir -p "$TMPD/fakehome/.cache" "$TMPD/shared/Alpha Library" "$TMPD/shared/Beta Library" "$TMPD/shared/Other" "$TMPD/shared/\$(x) Library"
printf 'x' > "$TMPD/fakehome/.cache/f"
cat > "$TMPD/candidates.tsv" <<EOF
# comment
~/.cache	regenerable	cache
$TMPD/shared/* Library	regenerable	sample libraries
$TMPD/missing	personal	not there
EOF

out="$(HOME="$TMPD/fakehome" TM_FIX_CANDIDATES="$TMPD/candidates.tsv" /bin/bash "$TOOL" sizes 0)"
n="$(printf '%s\n' "$out" | grep -c .)"
[ "$n" -eq 4 ] && ok || bad "want 4 lines, got $n: $out"
printf '%s\n' "$out" | grep -c '	unsafe_regenerable	' | grep -qx 1 && ok || bad "want exactly one unsafe line: $out"
printf '%s\n' "$out" | grep -qF '	regenerable	'"$TMPD/shared/Beta Library" && ok || bad "a later glob match was marked unsafe: $out"
printf '%s\n' "$out" | grep -qF "	$TMPD/fakehome/.cache	" && ok || bad "~ was not expanded: $out"
printf '%s\n' "$out" | grep -qF "	$TMPD/shared/Alpha Library	" && ok || bad "glob with a space did not match: $out"
printf '%s\n' "$out" | grep -qF "Other" && bad "glob matched a folder without the suffix" || ok
# Folders under $TMPDIR are excluded by Time Machine itself, so the "not excluded"
# case needs a folder outside it: one inside this checkout, removed at exit.
PLAIN="$(mktemp -d "$PWD/.sizes-test.XXXXXX")"
trap 'rm -rf "$TMPD" "$PLAIN"' EXIT
printf '%s\tpersonal\tplain folder\n' "$PLAIN" > "$TMPD/plain.tsv"
plain="$(TM_FIX_CANDIDATES="$TMPD/plain.tsv" /bin/bash "$TOOL" sizes 0)"
printf '%s\n' "$plain" | grep -qF "	no	personal	$PLAIN	" && ok || bad "a folder outside TMPDIR should read as not excluded: $plain"
printf '%s\n' "$out" | awk -F'\t' 'NF!=5 || ($2!="yes" && $2!="no" && $2!="unknown") {e=1} END {exit e}' && ok || bad "bad columns: $out"

out="$(HOME="$TMPD/fakehome" TM_FIX_CANDIDATES="$TMPD/candidates.tsv" /bin/bash "$TOOL" sizes 1)"
[ -z "$out" ] && ok || bad "MIN_GB 1 should drop tiny folders: $out"

echo "test_sizes: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
