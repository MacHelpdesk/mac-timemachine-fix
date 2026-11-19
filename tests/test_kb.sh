#!/bin/bash
# test_kb — the knowledge base validates, and signals match the problems they should.

set -u
cd "$(dirname "$0")/.." || exit 2
TOOL=plugin/scripts/tm-fix.sh
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
export TM_FIX_LOCAL_KB="$TMPD/none.json"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

ids() { cut -f1 | sort | tr '\n' ' '; }

/bin/bash "$TOOL" validate >/dev/null 2>&1 && ok || bad "shipped knowledge base does not validate"

# every problem in list has an id, a status, an origin and a title
n="$(/bin/bash "$TOOL" list | awk -F'\t' 'NF==4' | wc -l | tr -d ' ')"
[ "$n" -ge 6 ] && ok || bad "list printed $n well-formed lines"

# a Mac that has not finished a backup for months
cat > "$TMPD/stale" <<'EOF'
destination=configured
destination_mounted=yes
auto_backup=on
last_result=22
days_since_last_backup=82
reference_snapshot=missing
interrupted_backups=3
destination_free_pct=1
source_free_pct=3
log_result=ok
log_name_too_long=2
log_copy_stage_failed=1
log_scan_failed=1
log_reference_missing=1
EOF
got="$(/bin/bash "$TOOL" match "$TMPD/stale" | ids)"
for want in reference-snapshot-lost name-too-long-in-scan copy-stage-source-error source-disk-nearly-full; do
  case " $got" in *" $want "*) ok ;; *) bad "stale signals did not match $want (got: $got)" ;; esac
done

# a healthy Mac matches nothing, exit 3
cat > "$TMPD/healthy" <<'EOF'
destination=configured
destination_mounted=yes
auto_backup=on
last_result=0
days_since_last_backup=0
reference_snapshot=present
interrupted_backups=0
destination_free_pct=40
source_free_pct=30
log_result=ok
log_name_too_long=0
log_copy_stage_failed=0
log_scan_failed=0
log_reference_missing=0
EOF
/bin/bash "$TOOL" match "$TMPD/healthy" >/dev/null; rc=$?
[ "$rc" -eq 3 ] && ok || bad "healthy signals: exit $rc, want 3"

# unknown never counts as a match
printf 'destination=configured\nreference_snapshot=unknown\ndays_since_last_backup=200\n' > "$TMPD/unknown"
got="$(/bin/bash "$TOOL" match "$TMPD/unknown" | ids)"
case " $got" in *" reference-snapshot-lost "*) bad "unknown reference snapshot matched" ;; *) ok ;; esac

# the drive is not connected
printf 'destination=configured\ndestination_mounted=no\n' > "$TMPD/unplugged"
got="$(/bin/bash "$TOOL" match "$TMPD/unplugged" | ids)"
case " $got" in *" destination-not-connected "*) ok ;; *) bad "unplugged did not match (got: $got)" ;; esac

# show prints the boundaries and the never list
out="$(/bin/bash "$TOOL" show reference-snapshot-lost)"
printf '%s' "$out" | grep -q '任何情況都不做' && ok || bad "show has no never list"
printf '%s' "$out" | grep -q 'class: ask' && ok || bad "show has no ask fix"

# a bad personal entry is rejected by validate and left out of list
cat > "$TMPD/bad.json" <<'EOF'
{ "schema_version": 1, "problems": [ { "id": "Bad Id", "title": "x", "symptoms": ["x"],
  "match": { "all": [ { "signal": "no_such_signal", "op": "equals", "value": "x" } ] },
  "cause": "x", "fixes": [ { "id": "f", "action": "x", "class": "maybe", "evidence": "verified" } ],
  "evidence": { "status": "verified" } } ] }
EOF
TM_FIX_LOCAL_KB="$TMPD/bad.json" /bin/bash "$TOOL" validate >/dev/null 2>&1 && bad "bad local entry validated" || ok
n="$(TM_FIX_LOCAL_KB="$TMPD/bad.json" /bin/bash "$TOOL" list 2>/dev/null | grep -c local)"
[ "$n" -eq 0 ] && ok || bad "bad local entry was listed"

# candidates.tsv: three tab-separated fields, a known kind, no blank reason
bad_lines="$(grep -vE '^(#|$)' plugin/data/candidates.tsv | awk -F'\t' 'NF!=3 || ($2!="regenerable" && $2!="personal" && $2!="system") || $3==""')"
[ -z "$bad_lines" ] && ok || bad "malformed candidates.tsv lines: $bad_lines"

echo "test_kb: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
