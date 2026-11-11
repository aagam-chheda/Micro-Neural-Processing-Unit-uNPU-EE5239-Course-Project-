#!/usr/bin/env bash
# Quick read of a Design Compiler run written by syn/dc_run.tcl (task 035).
#
# Usage (from the repo root; works from a csh login shell too, this is bash):
#   bash scripts/dc_summary.sh unpu_pe
#   bash scripts/dc_summary.sh unpu_top
#
# Reads syn/out/<design>/ : dc.log, rpt/*.rpt and <design>.v. Prints:
#   - count of Error: and Warning: lines, and each distinct message ID with
#     its count (so nothing hides in a long log)
#   - unresolved-reference messages and any line containing "latch"
#   - anything "unconstrained" from check_timing
#   - worst setup slack per path group (from rpt/timing.rpt)
#   - total cell count and area (from rpt/area.rpt)
#   - every netlist instance whose reference matches a don't-use pattern
#     (patterns taken from the single list in syn/dc_setup.tcl; expected 0)
# A missing file is printed as MISSING and is never treated as OK.
#
# Exit status: 0 only if nothing needs attention (no MISSING file, no Error:,
# no latch line, no unresolved reference, no unconstrained line, no negative
# slack, no don't-use hit); 1 otherwise. It is a summary, not a judge: read the
# lines it prints.
#
# Environment (for testing on a sample directory):
#   SYN_OUT   override the syn/out base directory (default <repo>/syn/out)

DESIGN="${1:-}"
case "$DESIGN" in
  unpu_pe|unpu_top) ;;
  *) echo "usage: bash scripts/dc_summary.sh unpu_pe|unpu_top" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SYN_OUT:-$ROOT/syn/out}/$DESIGN"
LOG="$OUT/dc.log"
RPT="$OUT/rpt"
NET="$OUT/$DESIGN.v"
SETUP="$ROOT/syn/dc_setup.tcl"

attention=0
flag() { attention=1; }
have() {  # have <file> : print MISSING and flag if the file is absent
  if [ ! -f "$1" ]; then echo "MISSING: $1"; flag; return 1; fi
  return 0
}

echo "== dc_summary: $DESIGN  ($OUT)"

# ---- Log: errors, warnings, IDs ---------------------------------------------
echo
echo "-- dc.log"
if have "$LOG"; then
  n_err=$(grep -c '^Error:' "$LOG")
  n_warn=$(grep -c '^Warning:' "$LOG")
  echo "Error:   lines = $n_err"
  echo "Warning: lines = $n_warn"
  [ "$n_err" -gt 0 ] && flag
  echo "Distinct message IDs (count  kind  ID):"
  for kind in Error Warning; do
    grep "^$kind:" "$LOG" | grep -oE '\([A-Z][A-Z0-9]*-[0-9]+\)' | sort | uniq -c \
      | sed -E "s/^ *([0-9]+) \((.*)\)$/  \1  $kind  \2/"
    n_noid=$(grep "^$kind:" "$LOG" | grep -vcE '\([A-Z][A-Z0-9]*-[0-9]+\)')
    [ "$n_noid" -gt 0 ] && echo "  $n_noid  $kind  (no message ID)"
  done
  echo "Error lines (first 20):"
  grep -n '^Error:' "$LOG" | head -20 | sed 's/^/  /'
  [ "$n_err" -eq 0 ] && echo "  (none)"

  echo
  echo "Unresolved references:"
  if grep -in 'unable to resolve reference' "$LOG" | sed 's/^/  /' | grep .; then flag; else echo "  (none)"; fi

  echo
  echo "Lines containing 'latch' (case-insensitive):"
  if grep -in 'latch' "$LOG" | sed 's/^/  /' | grep .; then flag; else echo "  (none)"; fi
fi

# ---- check_timing ------------------------------------------------------------
echo
echo "-- rpt/check_timing.rpt"
if have "$RPT/check_timing.rpt"; then
  echo "Lines mentioning unconstrained / not constrained:"
  if grep -inE 'unconstrained|not constrained' "$RPT/check_timing.rpt" | sed 's/^/  /' | grep .; then flag; else echo "  (none)"; fi
fi

# ---- Worst setup slack per path group ---------------------------------------
echo
echo "-- rpt/timing.rpt (worst setup slack per path group)"
if have "$RPT/timing.rpt"; then
  slacks=$(awk '
    /^ *Path Group:/ { g = $3 }
    /^ *slack \(/    { v = $NF + 0; if (!(g in w) || v < w[g]) w[g] = v; seen = 1 }
    END { for (k in w) printf "%s %s\n", k, w[k] }' "$RPT/timing.rpt" | sort)
  if [ -z "$slacks" ]; then
    echo "  no slack lines found in the report"; flag
  else
    echo "$slacks" | while read -r g s; do echo "  group $g : worst slack $s"; done
    echo "$slacks" | awk '$2 < 0 { bad = 1 } END { exit bad ? 1 : 0 }' || { echo "  NEGATIVE SLACK present"; flag; }
  fi
fi

# ---- Cells and area ----------------------------------------------------------
echo
echo "-- rpt/area.rpt"
if have "$RPT/area.rpt"; then
  grep -E 'Number of (cells|combinational cells|sequential cells|buf/inv|references)|Total cell area|Total area' "$RPT/area.rpt" | sed 's/^/  /'
  grep -qE 'Total cell area' "$RPT/area.rpt" || { echo "  no 'Total cell area' line found"; flag; }
fi

# ---- Don't-use cells in the netlist -----------------------------------------
echo
echo "-- $DESIGN.v : don't-use cell instances"
if have "$NET" && have "$SETUP"; then
  # The one shared list: the DONT_USE_PATTERNS line in syn/dc_setup.tcl.
  pats=$(sed -nE 's/^set DONT_USE_PATTERNS \{([^}]*)\}.*$/\1/p' "$SETUP")
  if [ -z "$pats" ]; then
    echo "  could not read DONT_USE_PATTERNS from $SETUP"; flag
  else
    echo "  patterns: $pats"
    hits=0
    for p in $pats; do
      re="${p//\*/[A-Za-z0-9_]*}"   # glob * -> regex
      # instance line: <ref> <inst> (   (instance name may be an escaped id)
      m=$(grep -nE "^[[:space:]]*$re[[:space:]]+[^[:space:]]+[[:space:]]*\(" "$NET")
      if [ -n "$m" ]; then
        echo "$m" | sed "s/^/  HIT($p): /"
        hits=$((hits + $(echo "$m" | wc -l)))
      fi
    done
    echo "  don't-use instances found: $hits (expected 0)"
    [ "$hits" -ne 0 ] && flag
  fi
fi

echo
if [ "$attention" -eq 0 ]; then
  echo "== $DESIGN: nothing needs attention (read the lines above anyway)"
  exit 0
else
  echo "== $DESIGN: NEEDS ATTENTION (see MISSING / Error / latch / unconstrained / slack / don't-use lines above)"
  exit 1
fi
