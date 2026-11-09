#!/usr/bin/env bash
# VistaRevive - Phase 7 benchmarks: real RAM use and start times on THIS laptop.
# Run as your normal user inside the desktop, with other apps closed.
#
#   bash 07-benchmark.sh idle                    desktop RAM at idle (target < 300 MB)
#   bash 07-benchmark.sh browser firefox-esr     1 tab, then 5 tabs
#   bash 07-benchmark.sh browser falkon          same, for comparison (07-apps.sh --with-falkon)
#   bash 07-benchmark.sh office                  LibreOffice vs AbiWord/Gnumeric
#
# Results are appended to ~/vistarevive-benchmarks.md
# Memory is measured as PSS (shared libraries split fairly between processes),
# the most honest "how much does this app cost" number Linux offers.
set -uo pipefail

OUT="$HOME/vistarevive-benchmarks.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ -n "${DISPLAY:-}" ]] || { echo "Run this inside the desktop (needs DISPLAY)."; exit 1; }

meminfo() { awk -v k="$1" '$1==k":" {print int($2/1024)}' /proc/meminfo; }
used_mb() { echo $(( $(meminfo MemTotal) - $(meminfo MemAvailable) )); }
swap_mb() { echo $(( $(meminfo SwapTotal) - $(meminfo SwapFree) )); }

descendants() {
  local p=$1; echo "$p"
  local c; for c in $(pgrep -P "$p" 2>/dev/null); do descendants "$c"; done
}
pss_tree_mb() {
  local total=0 p v
  for p in $(descendants "$1"); do
    v=$(awk '/^Pss:/ {print $2}' "/proc/$p/smaps_rollup" 2>/dev/null)
    total=$(( total + ${v:-0} ))
  done
  echo $(( total / 1024 ))
}
wait_quiet() {  # wait N seconds with a countdown
  local n=$1
  while (( n > 0 )); do printf '\r  waiting %3ss ' "$n"; sleep 1; n=$((n-1)); done; printf '\r%20s\r' ''
}
header() {
  if [[ ! -f "$OUT" ]]; then
    { echo "# VistaRevive benchmarks"; echo; } > "$OUT"
  fi
  {
    echo "## $1 — $(date '+%Y-%m-%d %H:%M')"
    echo "RAM: $(meminfo MemTotal) MB · $(vistarevive-aero status 2>/dev/null || echo 'Aero: ?') · GPU: $(. /etc/vistarevive/hardware.conf 2>/dev/null; echo "${GPU:-?}")"
    echo
  } >> "$OUT"
}

# ---------------------------------------------------------------------------
bench_idle() {
  header "Idle desktop"
  echo "Measuring idle desktop (sit still for 60 s)..."
  sync; wait_quiet 60
  local top
  top=$(ps -u "$USER" -o pid=,comm= | while read -r pid comm; do
          v=$(awk '/^Pss:/ {print $2}' "/proc/$pid/smaps_rollup" 2>/dev/null)
          echo "$(( ${v:-0} / 1024 )) $comm"
        done | sort -rn | head -n 10)
  {
    echo "| Measure | Value |"; echo "|---|---|"
    echo "| System RAM used | $(used_mb) MB (target < 300) |"
    echo "| Swap used | $(swap_mb) MB |"
    echo
    echo "Top user processes (PSS MB):"; echo '```'; echo "$top"; echo '```'; echo
  } >> "$OUT"
  tail -n 20 "$OUT"
}

# ---------------------------------------------------------------------------
browser_cmd() {  # browser_cmd NAME PROFILE_DIR URL... -> prints argv, one per line
  local b=$1 prof=$2; shift 2
  case "$b" in
    firefox-esr|firefox) printf '%s\n' "$b" --no-remote --profile "$prof" "$@" ;;
    falkon)              printf '%s\n' falkon --no-remote --private-browsing "$@" ;;
    chromium)            printf '%s\n' chromium --user-data-dir="$prof" --no-first-run "$@" ;;
    *) echo "unsupported"; return 1 ;;
  esac
}

run_browser() {  # run_browser NAME WAIT LABEL URL...
  local b=$1 wait=$2 label=$3; shift 3
  local prof="$TMP/profile-$label"; mkdir -p "$prof"
  local before; before=$(used_mb)
  mapfile -t argv < <(browser_cmd "$b" "$prof" "$@")
  local t0; t0=$(date +%s)
  "${argv[@]}" >/dev/null 2>&1 &
  local pid=$!
  wait_quiet "$wait"
  local pss; pss=$(pss_tree_mb "$pid")
  local after; after=$(used_mb)
  echo "| $label | $pss MB | $(( after - before )) MB | $(used_mb) MB | $(swap_mb) MB |" >> "$OUT"
  kill "$pid" 2>/dev/null; sleep 3
  pkill -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null
  sleep 5
}

bench_browser() {
  local b=${1:-firefox-esr}
  command -v "$b" >/dev/null || { echo "$b is not installed."; exit 1; }
  header "Browser: $b"
  {
    echo "| Test | Browser PSS | Added to system | System used | Swap used |"
    echo "|---|---|---|---|---|"
  } >> "$OUT"
  echo "Warm-up start (fills the disk cache, not recorded)..."
  run_browser "$b" 25 "warm-up" "https://en.wikipedia.org/wiki/Linux"
  sed -i '$d' "$OUT"   # drop the warm-up row
  echo "1 tab..."
  run_browser "$b" 30 "1 tab (Wikipedia)" "https://en.wikipedia.org/wiki/Linux"
  echo "5 tabs (Wikipedia, YouTube, Gmail, Google Docs, news)..."
  run_browser "$b" 90 "5 tabs" \
    "https://en.wikipedia.org/wiki/Linux" "https://www.youtube.com" \
    "https://mail.google.com" "https://docs.google.com/document/" "https://www.bbc.com/news"
  echo >> "$OUT"
  tail -n 8 "$OUT"
}

# ---------------------------------------------------------------------------
make_samples() {
  {
    printf '{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Liberation Serif;}}\\f0\\fs24\n'
    for i in $(seq 1 120); do
      printf '{\\b Section %s}\\par This is a sample paragraph for the VistaRevive office benchmark. ' "$i"
      printf 'It repeats a few times so the document is about twenty pages long. %.0s' 1 2 3 4
      printf '\\par\\par\n'
    done
    printf '}\n'
  } > "$TMP/bench-sample.rtf"
  {
    echo "Item,Region,Units,Price,Total"
    for i in $(seq 1 5000); do echo "Item $i,Region $((i % 7)),$((i % 50 + 1)),$((i % 13 + 2)).50,=C$((i+1))*D$((i+1))"; done
  } > "$TMP/bench-sample.csv"
}

run_office() {  # run_office LABEL FILE CMD...
  local label=$1 file=$2; shift 2
  command -v "$1" >/dev/null || { echo "| $label | not installed | | |" >> "$OUT"; return; }
  sync
  local t0; t0=$(date +%s.%N)
  "$@" "$file" >/dev/null 2>&1 &
  local pid=$!
  local name; name=$(basename "$file" | cut -d. -f1)
  local secs="timeout"
  if timeout 120 xdotool search --sync --onlyvisible --name "$name" >/dev/null 2>&1; then
    secs=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN {printf "%.1f s", b-a}')
  fi
  sleep 8
  local pss; pss=$(pss_tree_mb "$pid")
  echo "| $label | $secs | $pss MB | $(used_mb) MB |" >> "$OUT"
  pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; sleep 3
  pkill -x soffice.bin 2>/dev/null; sleep 3
}

bench_office() {
  command -v xdotool >/dev/null || { echo "Needs xdotool:  sudo apt install xdotool"; exit 1; }
  make_samples
  header "Office suites"
  {
    echo "Document: ~20-page RTF. Spreadsheet: 5000-row CSV with formulas."
    echo "Each app runs twice; the second (warm) run is what you feel day to day."
    echo
    echo "| Test | Time to window | App PSS | System used |"
    echo "|---|---|---|---|"
  } >> "$OUT"
  local pass
  for pass in cold warm; do
    run_office "LibreOffice Writer ($pass)" "$TMP/bench-sample.rtf" lowriter
    run_office "AbiWord ($pass)"            "$TMP/bench-sample.rtf" abiword
    run_office "LibreOffice Calc ($pass)"   "$TMP/bench-sample.csv" localc --infilter="CSV:44,34,76,1"
    run_office "Gnumeric ($pass)"           "$TMP/bench-sample.csv" gnumeric
  done
  echo >> "$OUT"
  tail -n 12 "$OUT"
  echo
  echo "Keep the winner with:  sudo bash 07-apps.sh --keep-office libreoffice   (or: lite)"
}

case "${1:-}" in
  idle)    bench_idle ;;
  browser) bench_browser "${2:-firefox-esr}" ;;
  office)  bench_office ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
echo "Results saved in $OUT"
