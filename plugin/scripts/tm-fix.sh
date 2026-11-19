#!/bin/bash
# tm-fix — measure why Time Machine backups keep failing on this Mac, and look the
# result up in a knowledge base of known problems.
#
#   tm-fix.sh probe                 print what can be measured, one signal=value per line
#   tm-fix.sh match [SIGNALS_FILE]  known problems these signals fit (id, evidence status,
#                                   origin, title; tab separated). Without a file it runs
#                                   the probe. Exit 3: no match.
#   tm-fix.sh list                  every known problem
#   tm-fix.sh show ID               one problem: symptoms, cause, fixes, what does not work
#   tm-fix.sh validate              check problems.json and the personal additions
#   tm-fix.sh failing-paths         paths that the backup log names in the two failures
#                                   tied to single files: "name_too_long" (first six
#                                   components) and "copy_failed" (the whole path).
#                                   A path with a shell metacharacter or a control
#                                   character is printed as unsafe_<kind>, escaped with
#                                   printf %q; sizes does the same in its kind column
#   tm-fix.sh sizes [MIN_GB]        size and exclusion state of the places listed in
#                                   ../data/candidates.tsv that hold at least MIN_GB
#                                   (default 1): size_gb, excluded, kind, path, reason
#
# Every subcommand reads; none changes a setting, deletes a file or starts a backup.
# Adding exclusions and starting a backup are decided in the timemachine-fix skill.
#
# Nothing here parses text that changes with the system language. Settings come from
# property lists (plutil, tmutil -X), sizes from df -k and du -k, and the log is matched
# on identifiers that backupd writes in English whatever the language: error codes,
# BACKUP_FAILED_* names and the developer messages listed in log_counts.
#
# probe reads `log show` for the last TM_FIX_LOG_HOURS hours (default 24). On a busy
# Mac that takes from several seconds to about a minute.
#
# The knowledge base is ../data/problems.json. A person's own additions go in
# ~/.config/mac-timemachine-fix/problems.local.json; see README.md.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
KB="${TM_FIX_KB:-$HERE/../data/problems.json}"
LOCAL_KB="${TM_FIX_LOCAL_KB:-$HOME/.config/mac-timemachine-fix/problems.local.json}"
CANDIDATES="${TM_FIX_CANDIDATES:-$HERE/../data/candidates.tsv}"
KBJS="$HERE/kb.js"

PREFS="${TM_FIX_PREFS:-/Library/Preferences/com.apple.TimeMachine.plist}"
SOURCE="${TM_FIX_SOURCE:-/System/Volumes/Data}"
LOG_HOURS="${TM_FIX_LOG_HOURS:-24}"
SNAPSHOT_PREFIX='/Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb/'

TMPD=""
cleanup() { [ -n "$TMPD" ] && rm -rf "$TMPD"; }
trap cleanup EXIT
tmpdir() { [ -n "$TMPD" ] || TMPD="$(mktemp -d)"; }

# plist_get FILE KEYPATH: the raw value, or nothing when the key is missing
plist_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# iso_to_epoch 2026-07-28T15:35:18Z
iso_to_epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null; }

# free_pct PATH: free space in whole percent, from df -k
free_pct() {
  df -k "$1" 2>/dev/null | awk 'NR==2 && $2>0 { printf "%d\n", ($4*100)/$2 }'
}

destinfo_file() {
  if [ -n "${TM_FIX_DESTINFO:-}" ]; then echo "$TM_FIX_DESTINFO"; return; fi
  tmpdir
  tmutil destinationinfo -X > "$TMPD/destinfo.xml" 2>/dev/null
  echo "$TMPD/destinfo.xml"
}

snapshots_text() {
  if [ -n "${TM_FIX_LOCAL_SNAPSHOTS:-}" ]; then cat "$TM_FIX_LOCAL_SNAPSHOTS" 2>/dev/null; return; fi
  tmutil listlocalsnapshotdates / 2>/dev/null
}

# log_file: a file with the backupd log, or nothing when it could not be read
log_file() {
  if [ -n "${TM_FIX_LOG:-}" ]; then
    [ -r "$TM_FIX_LOG" ] && echo "$TM_FIX_LOG"
    return
  fi
  tmpdir
  if /usr/bin/log show --style compact --predicate 'process == "backupd"' \
       --last "${LOG_HOURS}h" > "$TMPD/backupd.log" 2>/dev/null; then
    echo "$TMPD/backupd.log"
  fi
}

count() { grep -cE "$1" "$2" 2>/dev/null; true; }

probe() {
  local info mount n auto last ref now snaps i last_epoch ref_epoch ref_name lf
  info="$(destinfo_file)"
  n="$(plist_get "$info" Destinations)"
  if [ -z "$n" ] || [ "$n" = "0" ]; then
    echo "destination=none"
  else
    echo "destination=configured"
    mount="$(plist_get "$info" Destinations.0.MountPoint)"
    if [ -n "$mount" ] && [ -d "$mount" ]; then
      echo "destination_mounted=yes"
      i=0
      for d in "$mount"/*.interrupted; do [ -d "$d" ] && i=$((i+1)); done
      echo "interrupted_backups=$i"
      [ -n "$(free_pct "$mount")" ] && echo "destination_free_pct=$(free_pct "$mount")"
    else
      echo "destination_mounted=no"
    fi
  fi

  auto="$(plist_get "$PREFS" AutoBackup)"
  case "$auto" in
    true|1) echo "auto_backup=on" ;;
    false|0) echo "auto_backup=off" ;;
  esac

  last="$(plist_get "$PREFS" Destinations.0.RESULT)"
  [ -n "$last" ] && echo "last_result=$last"

  now="${TM_FIX_NOW:-$(date +%s)}"
  snaps="$(plist_get "$PREFS" Destinations.0.SnapshotDates)"
  if [ -n "$snaps" ] && [ "$snaps" -gt 0 ] 2>/dev/null; then
    last_epoch="$(iso_to_epoch "$(plist_get "$PREFS" "Destinations.0.SnapshotDates.$((snaps-1))")")"
    if [ -n "$last_epoch" ]; then
      i=$(( (now - last_epoch) / 86400 ))
      [ "$i" -lt 0 ] && i=0
      echo "days_since_last_backup=$i"
    fi
  fi

  # The reference snapshot is named after the local time of its date: 04:10:30Z is
  # com.apple.TimeMachine.2025-03-10-121030.local on a Mac set to UTC+8.
  ref_epoch="$(iso_to_epoch "$(plist_get "$PREFS" Destinations.0.ReferenceLocalSnapshotDate)")"
  if [ -z "$ref_epoch" ]; then
    echo "reference_snapshot=unknown"
  else
    ref_name="$(date -r "$ref_epoch" +%Y-%m-%d-%H%M%S)"
    if snapshots_text | grep -qxF "$ref_name"; then
      echo "reference_snapshot=present"
    else
      echo "reference_snapshot=missing"
    fi
  fi

  [ -n "$(free_pct "$SOURCE")" ] && echo "source_free_pct=$(free_pct "$SOURCE")"

  lf="$(log_file)"
  if [ -z "$lf" ]; then
    echo "log_result=failed"
    return 0
  fi
  echo "log_result=ok"
  echo "log_name_too_long=$(count 'Failed to enumerate path.*NSPOSIXErrorDomain Code=63' "$lf")"
  echo "log_copy_stage_failed=$(count 'BACKUP_FAILED_COPY_STAGE' "$lf")"
  echo "log_scan_failed=$(count 'Failed to collect events.*consistencyScan' "$lf")"
  echo "log_reference_missing=$(count 'does not have an expected snapshot for timestamp' "$lf")"
}

# strip the local snapshot mount prefix: .../Backups.backupdb/<machine>/<date>/Data/x -> /x
strip_snapshot() { sed -E "s#^${SNAPSHOT_PREFIX}[^/]+/[^/]+/[^/]+##"; }

# emit KIND PATH: one tab-separated line. A path holding a shell metacharacter or a
# control character is printed as unsafe_KIND with printf %q, so that nobody copies
# it into a command line as it is. Folder names come from whoever created them.
emit() {
  case "$2" in
    *[\$\`\;\|\&\<\>\\\"\'\!\*\?\[\]\(\)\{\}]*|*[[:cntrl:]]*)
      printf 'unsafe_%s\t%q\n' "$1" "$2" ;;
    *) printf '%s\t%s\n' "$1" "$2" ;;
  esac
}

failing_paths() {
  local lf kind path
  lf="$(log_file)"
  [ -n "$lf" ] || { echo "cannot read the backupd log" >&2; return 1; }
  {
    grep -E 'Failed to enumerate path.*NSPOSIXErrorDomain Code=63' "$lf" \
      | sed -E "s/.*Failed to enumerate path '([^']*)'.*/\\1/" | strip_snapshot \
      | awk -F/ '{ out=""; for (i=2; i<=7 && i<=NF; i++) out=out "/" $i; print "name_too_long\t" out }'
    grep -E 'Backing up from source:' "$lf" \
      | sed -E "s/.*Backing up from source: '([^']*)'.*/\\1/" | strip_snapshot \
      | awk '{ print "copy_failed\t" $0 }'
  } | sort -u | while IFS='	' read -r kind path; do emit "$kind" "$path"; done
}

# is_excluded PATH: yes or no, from tmutil isexcluded -X
is_excluded() {
  local v
  v="$(tmutil isexcluded -X "$1" 2>/dev/null | plutil -extract 0.IsExcluded raw -o - - 2>/dev/null)"
  case "$v" in 1|true) echo yes ;; 0|false) echo no ;; *) echo unknown ;; esac
}

sizes() {
  local min="${1:-1}" pattern kind reason p kb gb ex k q oldifs
  [ -r "$CANDIDATES" ] || { echo "cannot read $CANDIDATES" >&2; return 1; }
  oldifs="$IFS"
  while IFS='	' read -r pattern kind reason; do
    case "$pattern" in ''|'#'*) continue ;; esac
    case "$pattern" in '~'*) pattern="$HOME${pattern#\~}" ;; esac
    IFS='
'
    for p in $pattern; do
      IFS="$oldifs"
      [ -e "$p" ] || continue
      kb="$(du -sxk "$p" 2>/dev/null | tail -1 | cut -f1)"
      [ -n "$kb" ] || continue
      gb=$((kb / 1048576))
      [ "$gb" -ge "$min" ] || continue
      ex="$(is_excluded "$p")"
      emit "$kind" "$p" | while IFS='	' read -r k q; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$gb" "$ex" "$k" "$q" "$reason"
      done
    done
    IFS="$oldifs"
  done < "$CANDIDATES" | sort -t '	' -k1,1nr
}

kb() { osascript -l JavaScript "$KBJS" "$@"; }

case "${1:-}" in
  probe) probe ;;
  match)
    tmpdir
    if [ -n "${2:-}" ]; then cp "$2" "$TMPD/signals"; else probe > "$TMPD/signals"; fi
    kb match "$KB" "$LOCAL_KB" "$TMPD/signals" > "$TMPD/matched" || exit 1
    cat "$TMPD/matched"
    [ -s "$TMPD/matched" ] || exit 3
    ;;
  list) kb list "$KB" "$LOCAL_KB" ;;
  show) [ -n "${2:-}" ] || { echo "usage: $0 show ID" >&2; exit 64; }; kb show "$KB" "$LOCAL_KB" "$2" ;;
  validate) kb validate "$KB" "$LOCAL_KB" ;;
  failing-paths) failing_paths ;;
  sizes) sizes "${2:-1}" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
