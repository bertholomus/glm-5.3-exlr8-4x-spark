#!/bin/bash
# conc_lookup.sh — the CONC knob's table lookup, sourced by knobs.sh (and usable by ./glm53 conc).
# One knob, CONC=1|2|4|8, sets SESS and lets CAP follow the largest CAP that a boot at that SESS
# measured holding the serving floor (ready >= 9 GiB free per box, never under 8 under load). A user-set CAP keeps its value; a CAP above the
# measured one for that CONC warns on stderr (not refused). A (VARIANT, CONC) pair with no measured
# row falls back to SESS=$CONC and the TUNE's CAP, with a stderr line. No fitted or interpolated CAP
# ships as a default. The table is conc.tsv (attic on and off rows); an optional uncommitted
# conc.local.tsv (your rig's own rows, git-ignored) is read first when it exists.
#
# conc.tsv format (tab-separated, '#' comments):
#   variant_key<TAB>conc<TAB>attic<TAB>sess<TAB>cap<TAB>pages_a_rank<TAB>tokens_per_session<TAB>date
# variant_key: the VARIANT value (home, bit325, ...) for shipped manifests, or sha256:<first 16 hex>
#              for a custom manifest path (its content hash — a file path means nothing on another box).
# attic: on|off — rows measured with the memory-reserve layer (spark-attic) lending, or without it.
#        ATTIC=1 selects the on rows (and the compose.attic.yaml overlay); default 0 = off rows.
# Row order: the FIRST row for a (variant_key, conc, attic) triple wins (put the best-measured first).

conc_rows_for() {  # conc_rows_for VARIANT_KEY ATTIC(on|off): that key's rows for the attic setting
  # always exits 0 (an empty result is a normal answer; the caller decides)
  local key=$1 attic=${2:-off} f mode
  [ "$attic" = 1 ] && mode=on || mode=off
  [ -f conc.tsv ] || return 0
  grep -v '^#' conc.tsv | grep -v '^[[:space:]]*$' \
    | awk -F'\t' -v k="$key" -v m="$mode" '$1 == k && $3 == m' || true
  return 0
}

conc_row_for() {  # conc_row_for VARIANT_KEY CONC ATTIC -> the first matching row, or nothing
  conc_rows_for "$1" "$3" | awk -F'\t' -v c="$2" '$2 == c' | head -1
}

conc_variant_key() {  # conc_variant_key VARIANT: name for shipped manifests, sha256:<16> for a path
  local v=$1
  case "$v" in
    */*) [ -f "$v" ] || { echo ""; return; }
         echo "sha256:$(sha256sum "$v" | cut -c1-16)" ;;
    bit275)  # the recipe's shipped manifest: resolve to the file so the hash key matches the boot
         [ -f "$(dirname "${BASH_SOURCE[0]}")/manifests/exlr8-manifest-bit275.json" ] \
           && echo "sha256:$(sha256sum "$(dirname "${BASH_SOURCE[0]}")/manifests/exlr8-manifest-bit275.json" | cut -c1-16)" \
           || echo "bit275" ;;
    *)   echo "$v" ;;
  esac
}

conc_apply() {  # conc_apply CONC VARIANT TUNE_CAP [USER_CAP 1|""] [ATTIC 0|1]: SESS/CAP per the rules; 0 ok, 2 bad
  local conc=$1 variant=$2 tune_cap=$3 user_cap=${4:-} attic=${5:-0} key row meas
  case "$conc" in
    1|2|4|8) ;;
    *) echo "CONC=$conc: want 1, 2, 4 or 8 (the concurrency dial: CONC sets SESS and grows the KV pool as the slots free; README.md, \"Pick what to prioritize\")" >&2; return 2 ;;
  esac
  case "$attic" in
    0|1) ;;
    *) echo "ATTIC=$attic: want 0 (off, the default) or 1 (the memory-reserve layer lends; needs an image with the client)" >&2; return 2 ;;
  esac
  key=$(conc_variant_key "$variant")
  row=""
  [ -n "$key" ] && row=$(conc_row_for "$key" "$conc" "$attic")
  SESS=$conc
  if [ -n "$user_cap" ]; then
    # the user's CAP keeps its value; warn when it is above the measured one for this CONC
    meas=$(printf '%s' "$row" | awk -F'\t' '{print $5}')
    if [ -n "$meas" ] && printf '%s' "$meas" | grep -qE '^[0-9]+$'; then
      [ "$CAP" -le "$meas" ] || echo "CAP=$CAP is above the measured $meas for CONC=$conc on this VARIANT: the serving floor (9 GiB free at ready, never under 8 under load) was verified only at $meas; $CAP is your call" >&2
    fi
  elif [ -n "$row" ] && printf '%s' "$row" | awk -F'\t' '{exit !($5 ~ /^[0-9]+$/)}'; then
    CAP=$(printf '%s' "$row" | awk -F'\t' '{print $5}')
  else
    CAP=$tune_cap
    echo "CAP not measured for this CONC on this VARIANT (key ${key:-unset}, attic $attic): keeping the TUNE's CAP=$CAP" >&2
  fi
  return 0
}

conc_attic_image_ok() {  # conc_attic_image_ok [GR8_IMAGE]: 0 when the image names an attic-client build
  local img=${1:-}
  case "$img" in
    *attic*) return 0 ;;
    *) return 1 ;;
  esac
}
