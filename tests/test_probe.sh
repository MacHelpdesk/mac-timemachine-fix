#!/bin/bash
# test_probe — probe and failing-paths read synthetic settings, snapshots and logs.
#
# Every input the probe reads from the system has an override (TM_FIX_*), so these
# tests never touch this Mac's Time Machine settings or its log.

set -u
cd "$(dirname "$0")/.." || exit 2
TOOL=plugin/scripts/tm-fix.sh
FX=tests/fixtures
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

# expect OUTPUT LINE: OUTPUT contains LINE as a whole line
expect()   { printf '%s\n' "$1" | grep -qxF "$2" && ok || bad "missing \"$2\" in: $(printf '%s' "$1" | tr '\n' ' ')"; }
expect_no(){ printf '%s\n' "$1" | grep -q "^$2=" && bad "unexpected $2 in: $(printf '%s' "$1" | tr '\n' ' ')" || ok; }
expect_num(){ printf '%s\n' "$1" | grep -qE "^$2=[0-9]+$" && ok || bad "$2 is not a number in: $(printf '%s' "$1" | tr '\n' ' ')"; }

DEST="$TMPD/dest"
mkdir -p "$DEST/2026-01-01-000000.interrupted" "$DEST/2026-01-02-000000.interrupted" "$DEST/2026-01-03-000000.inprogress"

destinfo() { # mounted | unmounted | none
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>'
    case "$1" in
      none) printf '<key>Destinations</key><array/>' ;;
      unmounted) printf '<key>Destinations</key><array><dict><key>Kind</key><string>Local</string><key>ID</key><string>00000000-0000-0000-0000-000000000000</string></dict></array>' ;;
      mounted) printf '<key>Destinations</key><array><dict><key>Kind</key><string>Local</string><key>ID</key><string>00000000-0000-0000-0000-000000000000</string><key>MountPoint</key><string>%s</string></dict></array>' "$DEST" ;;
    esac
    printf '</dict></plist>\n'
  } > "$TMPD/destinfo.xml"
}

run_probe() { # prefs snapshots log
  TZ=Asia/Taipei \
  TM_FIX_PREFS="$FX/$1" \
  TM_FIX_DESTINFO="$TMPD/destinfo.xml" \
  TM_FIX_LOCAL_SNAPSHOTS="$FX/$2" \
  TM_FIX_LOG="$FX/$3" \
  TM_FIX_SOURCE="$TMPD" \
  TM_FIX_NOW=1748736000 \
  /bin/bash "$TOOL" probe
}
# TM_FIX_NOW 1748736000 = 2025-06-01T00:00:00Z

# 1. last success months ago, reference snapshot gone, three kinds of failure in the log
destinfo mounted
out="$(run_probe prefs_stale.plist snapshots_without_reference.txt log_failures.txt)"
expect "$out" "destination=configured"
expect "$out" "destination_mounted=yes"
expect "$out" "auto_backup=on"
expect "$out" "last_result=22"
expect "$out" "days_since_last_backup=82"
expect "$out" "reference_snapshot=missing"
expect "$out" "interrupted_backups=2"
expect_num "$out" destination_free_pct
expect_num "$out" source_free_pct
expect "$out" "log_result=ok"
expect "$out" "log_name_too_long=3"
expect "$out" "log_copy_stage_failed=1"
expect "$out" "log_scan_failed=1"
expect "$out" "log_reference_missing=1"

# 2. the reference snapshot is still on the disk (local time name)
out="$(run_probe prefs_stale.plist snapshots_with_reference.txt log_clean.txt)"
expect "$out" "reference_snapshot=present"
expect "$out" "log_name_too_long=0"
expect "$out" "log_copy_stage_failed=0"

# 3. healthy: backed up today, clean log
out="$(run_probe prefs_recent.plist snapshots_recent.txt log_clean.txt)"
expect "$out" "days_since_last_backup=0"
expect "$out" "last_result=0"

# 4. destination configured but not connected: no destination numbers
destinfo unmounted
out="$(run_probe prefs_recent.plist snapshots_recent.txt log_clean.txt)"
expect "$out" "destination=configured"
expect "$out" "destination_mounted=no"
expect_no "$out" interrupted_backups
expect_no "$out" destination_free_pct

# 5. no destination at all, never backed up
destinfo none
out="$(run_probe prefs_never.plist snapshots_recent.txt log_clean.txt)"
expect "$out" "destination=none"
expect_no "$out" days_since_last_backup
expect "$out" "reference_snapshot=unknown"

# 6. automatic backups switched off
destinfo mounted
out="$(run_probe prefs_autooff.plist snapshots_recent.txt log_clean.txt)"
expect "$out" "auto_backup=off"

# 7. the log cannot be read: counts are absent, not zero
out="$(TZ=Asia/Taipei TM_FIX_PREFS="$FX/prefs_stale.plist" TM_FIX_DESTINFO="$TMPD/destinfo.xml" \
  TM_FIX_LOCAL_SNAPSHOTS="$FX/snapshots_without_reference.txt" TM_FIX_LOG="$TMPD/missing.txt" \
  TM_FIX_SOURCE="$TMPD" TM_FIX_NOW=1748736000 /bin/bash "$TOOL" probe)"
expect "$out" "log_result=failed"
expect_no "$out" log_name_too_long

# 8. failing-paths: paths from the log, with the snapshot prefix taken off, one per line
out="$(TM_FIX_LOG="$FX/log_failures.txt" /bin/bash "$TOOL" failing-paths)"
expect "$out" "name_too_long	/private/tmp/probe/aaaaaaaaaaaaaaaa/aaaaaaaaaaaaaaaa"
expect "$out" "name_too_long	/private/tmp/deep/d/d/d"
expect "$out" "copy_failed	/private/var/folders/xx/yy/0/com.example.locked/cache.sqlite"
# a path with shell metacharacters is flagged and escaped, never printed as is
printf '%s\n' "$out" | grep -q '^unsafe_name_too_long	' && ok || bad "metacharacter path not flagged: $out"
printf '%s\n' "$out" | grep -qF '$(touch pwned)' && bad "metacharacter path printed unescaped" || ok

echo "test_probe: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
