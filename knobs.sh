# The recipe's TUNE knob as gr8's options, sourced by entrypoint.sh and bin/gr8 so every `gr8 glm53` command sees the
# same settings. Every tier below is backed by rows measured on four DGX Sparks (README.md); a tier with no measured
# rows says so.
#
#   TUNE=quality (the default): the shipped bit275 width manifest at CONC=4 (the concurrency dial below), fp8 KV,
#             MTP + DFlash2 drafting. Exact output: temp-0 replies identical across boots (gr8 checks this itself).
#   TUNE=context: home + KV_FORMAT=int4 and CAP=513536 (gr8's measured int4 KV trade, gr8 docs/KV4.md: decode
#             -2.3..-3.3 %, prefill +5.8 %, temp-0 output moves marginally). Not yet measured on four Sparks.
#   TUNE=agents: quality's settings with SHARE_LIMIT=16384, for agents (long prompts that come back turn after turn).
#             Every rank holds a session's first SHARE_LIMIT tokens and a quarter of the rest, so at quality's
#             CAP=485376 a rank has 2,088 pages and four 60-70K-token agents stay in the pool together (1,857 of 2,088
#             pages): each warm turn is a prefix hit. Exact output, as quality: a hit keeps whole 4,096-row cells, the
#             same bytes as a cold prefill. The cost: a request over 16,384 tokens (prompt + max_tokens) decodes alone
#             instead of sharing decode steps (over 32,768 at quality). Measured 2026-11-09 on four DGX Sparks, same
#             image and release: four agents x 6 turns at ~60K tokens, warm-turn TTFT p50 5.9 s and p90 8.4 and 10.0 s
#             on two boots, no agent evicted; RigMark p50 code/prose/structured 56.4/36.1/61.9 tok/s, C4 87.6, C8 108.3;
#             needles at 64K and 128K 10/10; quality panel 12/12; 11.8-12.1 GiB free a rank after the pool.
#
#   TUNE=agents-fast: OPT-IN, never the default. TUNE=agents + GR8_REUSE_ALIGN=0 (an EXTRA_ENV word): a prefix hit keeps
#             the whole matched prefix instead of whole 4,096-row cells, so a warm turn prefills only its new tokens.
#             The price: a hit is not bit-exact against a cold prefill (gr8 SETTINGS.md), so a warm turn can get other
#             temp-0 text than the same request sent cold; this file prints that warning on every boot and command.
#             Measured 2026-11-09 on this rig: agent replay (four agents x 6 turns at ~60K tokens) warm-turn TTFT p50
#             3.4 s and p90 5.2 s, 11.7-12.3 tok/s an agent, on the boot with clean clocks (TUNE=agents: 5.9 s and
#             8.4-10.0 s, 9.7-11.6 tok/s), every warm turn a hit on all four boots; needles at 64K and 128K 10/10,
#             and 10/10 again with each document re-asked as a pool hit; quality panel 12/12 on two boots, and 12/12
#             with each task re-asked as a pool hit; four two-turn chats (~5,300-token prompts) re-sent cold: 2 of the
#             4 replies (64 tokens each) differ from the warm ones, 59 and 69 characters in (3 of 4 on a second boot).
#
# A VARIANT, SESS, CAP, SHARE_LIMIT or KV_FORMAT set on its own keeps its value. EXTRA_ENV already in the environment
# is kept, after anything this file adds (TUNE=agents-fast's GR8_REUSE_ALIGN=0; the speed slot's words when measured).
#
#   MENTAT=0 (default): the four boxes from PEERS (their LAN addresses, head first) and, if set, IPS and IPS2 (each
#             box's fabric address on the first and second ConnectX root, in PEERS order). Nothing is announced.
#   MENTAT=1: find the other boxes through the host's mentat daemon (gr8's MENTAT=localhost) and announce the API in
#             the mentat cluster, in group GROUP (gr8-glm53-4x by default, so the cluster never joins another one).
# Settings layers (scripts/config.sh): the exported environment > scripts/local.sh > .env > the defaults below.
# Inside the container compose already exported .env's lines, so the layers only ever widen what a host-side
# scripts/local.sh can set; an exported variable always wins.
_c=$(dirname "${BASH_SOURCE[0]}")/scripts/config.sh
[ -f "$_c" ] && . "$_c"
unset _c
AGENTS_FAST_WARNING="WARNING: TUNE=agents-fast sets GR8_REUSE_ALIGN=0: not bit-exact against a cold prefill (gr8 \
SETTINGS.md). A warm turn can get other temp-0 text than the same request sent cold. TUNE=agents keeps exact output."

# The concurrency dial: CONC=1|2|4|8 sets SESS and lets
# CAP follow the largest CAP a boot at that SESS measured holding the serving floor (9 GiB free at ready,
# never under 8 under load). A CAP you set keeps your value; one above the measured value warns on stderr.
# A pair with no measured row falls back to SESS=CONC and this TUNE's CAP, with a stderr line. The table is
# conc.tsv (ATTIC=0 rows: the stock memory layout; ATTIC=1 rows: spark-attic lending); an uncommitted conc.local.tsv
# adds your own rig's rows when present.
# ./glm53 conc prints the table for the current VARIANT.
# The dial defaults to CONC=4 (the serving choice):
# with CONC unset and SESS unset, SESS=4 and CAP follows the measured bit275 row. A tier that sets SESS
# itself (context: 8) or an explicit SESS keeps its value — the dial does not run for it.
if [ -z "${CONC:-}" ] && [ -z "${SESS:-}" ] && [ "${TUNE:-quality}" != context ]; then
  CONC=4
fi
if [ -n "${CONC:-}" ] || [ -n "${ATTIC:-}" ]; then
  # a CAP in the environment is the user's own; the TUNE case below only fills the default when it is unset
  conc_user_cap=""
  [ -n "${CAP:-}" ] && conc_user_cap=1
  . "$(dirname "${BASH_SOURCE[0]}")/conc_lookup.sh"
  case "${ATTIC:-0}" in
    0|1) ;;
    *) echo "ATTIC=${ATTIC}: want 0 (off, the default) or 1 (the memory-reserve layer lends; needs an image with the client)" >&2; exit 2 ;;
  esac
  # ATTIC=1 needs an image with the memory-reserve client (the pinned upstream image has none): refuse here,
  # before any boot, with the fix named (the recipe cannot build that image for you; it is a local build)
  if [ "${ATTIC:-0}" = 1 ]; then
    conc_attic_image_ok "${GR8_IMAGE:-ghcr.io/kindlingai/gr8:sha-e231adb}" \
      || { echo "ATTIC=1 needs an image with the memory-reserve client (GR8_IMAGE=${GR8_IMAGE:-ghcr.io/kindlingai/gr8:sha-e231adb} has none; e.g. GR8_IMAGE=gr8:e231adb-attic, a gr8 build with the attic client), and compose.attic.yaml on the boot" >&2; exit 2; }
    attic_words="GR8_ATTIC_SOCK=/run/spark-attic/attic.sock GR8_ATTIC_KEY_FILE=/run/gr8-attic/key"
  fi
  conc_apply "$CONC" "${VARIANT:-bit275}" "${CAP:-485376}" "$conc_user_cap" "${ATTIC:-0}" || exit 2
  unset CONC conc_user_cap
fi

case "${TUNE:-quality}" in
  quality)
    # the recipe default is the bit275 width manifest (it ships in manifests/ and
    # VARIANT=bit275 resolves to it); SESS/CAP/CONC follow the concurrency dial below
    VARIANT=${VARIANT:-bit275} ;;
  context)
    VARIANT=${VARIANT:-home} SESS=${SESS:-8} CAP=${CAP:-513536} KV_FORMAT=${KV_FORMAT:-int4} ;;
  agents|agents-fast)
    VARIANT=${VARIANT:-home} SESS=${SESS:-8} CAP=${CAP:-485376} SHARE_LIMIT=${SHARE_LIMIT:-16384} ;;
  *) echo "TUNE=$TUNE: want quality (the default), context, agents or agents-fast (README.md, \"Pick what to prioritize\")" >&2; exit 2 ;;
esac

# the one tier whose replies are not the exact model's: say so on every boot and command (stderr)
[ "${TUNE:-quality}" != agents-fast ] || echo "$AGENTS_FAST_WARNING" >&2
unset AGENTS_FAST_WARNING
export VARIANT SESS CAP
[ -z "${SHARE_LIMIT:-}" ] || export SHARE_LIMIT
[ -z "${KV_FORMAT:-}" ] || export KV_FORMAT
# BUSY=0|1 (default 0): the busy guard (gr8 docs/ENV.md GR8_BUSY_*). 1 = when granting a request would evict a
# retained run whose session is not idle (no request in flight and its last response ended under BUSY_IDLE_SECS
# ago, default 60), the head refuses it at once with HTTP 429 + Retry-After (BUSY_RETRY_AFTER, default 60) instead
# of evicting the run or queueing it in silence; BUSY_QUEUE_MAX (default 8) refuses arrivals past that queue depth.
# A turn that continues its own retained run is never refused. BUSY=1 needs GR8_IMAGE to name an image **with** the
# busy guard (a gr8 build of the busy-guard branch): the pinned ghcr.io/kindlingai/gr8:sha-e231adb has none and
# BUSY=1 is refused here, before any boot, with the fix named.
busy_words=""
case "${BUSY:-0}" in
  0) ;;
  1)
    case "${GR8_IMAGE:-}" in
      *busy*) ;;
      *) echo "BUSY=1 needs an image with the busy guard (GR8_IMAGE=${GR8_IMAGE:-ghcr.io/kindlingai/gr8:sha-e231adb} has none; e.g. GR8_IMAGE=gr8:busy-guard, a gr8 build with the busy guard), and GR8_BUSY_* ride EXTRA_ENV" >&2; exit 2 ;;
    esac
    busy_words="GR8_BUSY_GUARD=1"
    [ -n "${BUSY_IDLE_SECS:-}" ] && busy_words="$busy_words GR8_BUSY_IDLE_SECS=$BUSY_IDLE_SECS"
    [ -n "${BUSY_RETRY_AFTER:-}" ] && busy_words="$busy_words GR8_BUSY_RETRY_AFTER=$BUSY_RETRY_AFTER"
    [ -n "${BUSY_QUEUE_MAX:-}" ] && busy_words="$busy_words GR8_BUSY_QUEUE_MAX=$BUSY_QUEUE_MAX"
    unset BUSY_IDLE_SECS BUSY_RETRY_AFTER BUSY_QUEUE_MAX
    ;;
  *) echo "BUSY=${BUSY}: want 0 (off, the default) or 1 (the busy guard refuses what would evict a live session; needs an image with the guard)" >&2; exit 2 ;;
esac

# Tier words that are GR8_* engine variables ride EXTRA_ENV (UPDATE 2, Kindling 2026-11-07: a plain GR8_*=... line is
# dropped by the launcher). TUNE=agents-fast adds GR8_REUSE_ALIGN=0. An
# EXTRA_ENV already in the environment is kept verbatim, after the tier's words (no leading space added when the tier
# adds none).
tier_gr8_words=""
case "${TUNE:-quality}" in
  agents-fast) tier_gr8_words="GR8_REUSE_ALIGN=0" ;;
esac
export EXTRA_ENV="${busy_words:+$busy_words }${attic_words:+$attic_words }${tier_gr8_words:+$tier_gr8_words }${EXTRA_ENV:-}"
export EXTRA_ENV="${EXTRA_ENV% }"
unset tier_gr8_words attic_words busy_words
case "${MENTAT:-0}" in
  0) unset MENTAT
     n=$(tr , '\n' <<< "${PEERS:-}" | grep -c .) || true
     [ "$n" = 4 ] || { echo "PEERS=${PEERS:-}: want the four boxes' LAN addresses, head first, the same on every box (or MENTAT=1)" >&2; exit 2; } ;;
  1) unset PEERS; export MENTAT=localhost ;;
  localhost) unset PEERS ;;
  *) echo "MENTAT=$MENTAT: want 0 (the boxes in PEERS) or 1 (register with the mentat cluster)" >&2; exit 2 ;;
esac
