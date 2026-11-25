#!/bin/bash
# The CI no-GPU smoke: host-side checks only. Every check runs on plain files; nothing pulls, fetches or boots.
#   1. every shell script parses (bash -n)
#   2. .env.example parses as KEY=value lines, and carries the recipe defaults (UPDATE 2 EXTRA_ENV rule, the pinned
#      MODEL/DRAFTER, the attic-build GR8_IMAGE with the stock pin beside it); the v3 lane defaults ship uncommented:
#      the SSD KV store (KV_STORE + GR8_STOP_GRACE), BUSY=1, ATTIC=1 and the four serving knobs
#   3. knobs.sh dispatches TUNE=quality|context|agents|agents-fast (agents-fast warns on stderr), defaults
#      VARIANT=bit280 CONC=8, and refuses a bad TUNE and a wrong PEERS count
#   4. ./fetch --print prints the pinned MODEL and DRAFTER, and ./fetch --check exits 0 on the pins
#   5. compose.yaml and .github/workflows/ci.yml parse (python yaml / docker compose config if available)
#   6. ./glm53 (the host-side launcher) against tests/fake-docker: check-env refuses a plain GR8_* engine line, a
#      name set twice and a non-NAME=value line; check-config finds a set knob show-config does not show; up stops a
#      restart loop and prints the engine's error; down exits 0 on a box that is already down or looping
#
# STANDING RULE: no rm and no mv anywhere. The script never touches the recipe folder it runs from: on the first
# pass it copies the whole recipe (cp -r, except .git and prior smoke dirs) into a fresh scratch dir
# tests/.smoke-run-<timestamp>, then re-runs itself there. Checks 4 and 5 create their .env with cp inside that
# scratch dir and leave it in place (gitignored). Nothing is ever moved or removed.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)

if [ "${RECIPE_SMOKE_COPY:-}" != 1 ]; then
  scratch="$here/tests/.smoke-run-$(date +%Y%m%dT%H%M%S)"
  mkdir -p "$scratch"
  # cp -r the whole recipe, except .git and any prior smoke dirs; nothing is moved or removed, ever
  ( cd "$here" && tar -c -X "$here/tests/smoke-copy.exclude" --exclude .smoke-run-* . ) | ( cd "$scratch" && tar -x )
  exec env RECIPE_SMOKE_COPY=1 bash "$scratch/tests/ci-smoke.sh"
fi
cd "$here"
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. shell syntax
for f in knobs.sh entrypoint.sh bin/gr8 fetch glm53 tests/fake-docker tests/ci-smoke.sh; do
  [ -f "$f" ] || fail "$f: missing"
  bash -n "$f" || fail "$f: bash -n failed"
done
echo "ok: shell scripts parse"

# 2. .env.example: KEY=value lines only (comments and blanks aside), and the recipe defaults present
while IFS= read -r line; do
  [ -z "$line" ] && continue
  [[ $line == \#* ]] && continue
  [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || fail ".env.example: not a KEY=value line: $line"
done < .env.example
grep -q '^GR8_MODEL=glm53$' .env.example || fail ".env.example: GR8_MODEL=glm53 missing"
grep -q '^MODEL=https://huggingface.co/kindlingai/glm-5.3-exlr8-k2-k3-k4@9e25c28a2e8808d8b2599d780521fd6af24e7558$' .env.example \
  || fail ".env.example: pinned MODEL (release v0.7) missing"
grep -q '^DRAFTER=https://huggingface.co/incoai/GLM-5.3-DFlash2@' .env.example || fail ".env.example: pinned DRAFTER missing"
# v3: the lane defaults ship uncommented: the SSD KV store on (keep=all), BUSY=1, ATTIC=1, the serving knobs
grep -q '^KV_STORE=ssd:/var/lib/gr8/home/kv,size=200G,persist=on,keep=all$' .env.example \
  || fail ".env.example: the v3 SSD KV_STORE default line missing (on by default in v3, keep=all)"
grep -q '^GR8_STOP_GRACE=150s$' .env.example \
  || fail ".env.example: the GR8_STOP_GRACE=150s default missing (ships with the store)"
grep -q '^BUSY=1$' .env.example || fail ".env.example: the BUSY=1 default missing (on by default in v3)"
grep -q '^ATTIC=1$' .env.example || fail ".env.example: the ATTIC=1 default missing (on by default in v3)"
grep -q '^KVB=fp8$' .env.example || fail ".env.example: the KVB=fp8 serving knob missing"
grep -q '^CP_ONECHAIN=1$' .env.example || fail ".env.example: the CP_ONECHAIN=1 serving knob missing"
grep -q '^S2_SHARED_WATERFILL=1$' .env.example || fail ".env.example: the S2_SHARED_WATERFILL=1 serving knob missing"
grep -q '^KV_WRITE_LIMIT=0.5$' .env.example || fail ".env.example: the KV_WRITE_LIMIT=0.5 serving knob missing"
grep -q '^GR8_IMAGE=gr8:v120-attic-a1a4$' .env.example \
  || fail ".env.example: the v3 default GR8_IMAGE (the attic build of the pinned stock image) missing"
grep -q '^#GR8_IMAGE=ghcr.io/kindlingai/gr8:v1.2.0@sha256:3de05aab8cda21fd5d6b4af89ccdba6ff5abdbd704729601fd348fa638ade9fd$' .env.example \
  || fail ".env.example: the commented stock pin (the ATTIC=0 image) missing"
grep -q '^EXTRA_ENV=GR8_GEN_CACHE=/var/lib/gr8/cache/gen GR8_QUIT_FAST=1 GR8_S2_DECODE_PF=4096 GR8_S2_DECODE_ROUNDS=2$' .env.example \
  || fail ".env.example: the v3 EXTRA_ENV serving words missing (UPDATE 2: GR8_* knobs ride EXTRA_ENV)"
echo "ok: .env.example parses and carries the recipe defaults (v3: the measured lane's defaults uncommented)"

# 3. knobs.sh: TUNE dispatch. Source it in a subshell and check what it exports. An EXTRA_ENV already in the
#    environment is kept verbatim (TUNE appends, never replaces — the UPDATE 2 routing rule).
src_knobs() {  # src_knobs VAR=value... -> prints exported VARIANT/SESS/CAP/KV_FORMAT/SHARE_LIMIT/EXTRA_ENV
  ( export "$@"; export PEERS=10.0.0.1,10.0.0.2,10.0.0.3,10.0.0.4
    . "$here/knobs.sh"
    echo "VARIANT=${VARIANT-} SESS=${SESS-} CAP=${CAP-} KV_FORMAT=${KV_FORMAT-} SHARE_LIMIT=${SHARE_LIMIT-} EXTRA_ENV=${EXTRA_ENV-}" )
}
out=$(src_knobs TUNE=context)
echo "$out" | grep -q 'CAP=513536 KV_FORMAT=int4' || fail "knobs.sh TUNE=context: got: $out"
out=$(src_knobs TUNE=quality SESS=8 CAP=485376)
echo "$out" | grep -q 'VARIANT=bit280 SESS=8 CAP=485376 KV_FORMAT=fp8 SHARE_LIMIT=16384' || fail "knobs.sh TUNE=quality SESS=8 CAP=485376: got: $out"
# KV_FORMAT is explicit in every tier (issue #1): fp8 for quality and agents, a user value kept
echo "$out" | grep -q 'KV_FORMAT=fp8 ' || fail "knobs.sh TUNE=quality: KV_FORMAT not fp8: $out"
out=$(src_knobs TUNE=agents)
echo "$out" | grep -q 'KV_FORMAT=fp8 ' || fail "knobs.sh TUNE=agents: KV_FORMAT not fp8: $out"
out=$(src_knobs TUNE=quality KV_FORMAT=int4)
echo "$out" | grep -q 'KV_FORMAT=int4 ' || fail "knobs.sh TUNE=quality KV_FORMAT=int4: user value not kept: $out"
err=$(src_knobs TUNE=agents SESS=8 CAP=485376 2>&1 >/dev/null)
[ -z "$err" ] || fail "knobs.sh TUNE=agents SESS=8 CAP=485376 prints: $err"
# agents-fast: agents + GR8_REUSE_ALIGN=0 on EXTRA_ENV (before what is there), and the exactness warning on stderr
out=$(src_knobs TUNE=agents-fast CAP=776704 2>/dev/null)
echo "$out" | grep -q 'VARIANT=home SESS=8 CAP=776704 KV_FORMAT=fp8 SHARE_LIMIT=16384 EXTRA_ENV=GR8_REUSE_ALIGN=0$' \
  || fail "knobs.sh TUNE=agents-fast (the CONC=8 dial has no home row, CAP falls back with a stderr line): got: $out"
out=$(src_knobs TUNE=agents-fast CAP=776704 EXTRA_ENV=GR8_GEN_CACHE=/x 2>/dev/null)
echo "$out" | grep -q 'EXTRA_ENV=GR8_REUSE_ALIGN=0 GR8_GEN_CACHE=/x$' || fail "knobs.sh TUNE=agents-fast: EXTRA_ENV: $out"
err=$(src_knobs TUNE=agents-fast 2>&1 >/dev/null)
echo "$err" | grep -q "not bit-exact against a cold prefill (gr8 SETTINGS.md)" \
  || fail "knobs.sh TUNE=agents-fast: no exactness warning on stderr: $err"
out=$(src_knobs TUNE=quality EXTRA_ENV=GR8_GEN_CACHE=/x)
echo "$out" | grep -q 'EXTRA_ENV=GR8_GEN_CACHE=/x' || fail "knobs.sh: existing EXTRA_ENV not kept: $out"
# CONC dial + ATTIC toggle CONC sets SESS and CAP follows the measured row
# (conc.tsv, attic column selects on/off); a user CAP is kept (over the measured one it warns); a pair
# with no row falls back to SESS=CONC + the TUNE CAP with a stderr line; a bad CONC exits 2; ATTIC=1 on
# the pinned image is refused (the image has no memory-reserve client). CONC unset = today's exports.
# Defaults: TUNE=quality (and any other tier) resolves VARIANT=bit275 (the shipped manifest) and the
# dial defaults to CONC=4; TUNE=speed is removed (knobs 1 and 2 were no gain)
out=$(src_knobs TUNE=agents SESS=4 CAP=776704)
echo "$out" | grep -q 'VARIANT=home SESS=4 CAP=776704' \
  || fail "knobs.sh TUNE=agents (the home-width tier keeps home): got: $out"
out=$(src_knobs TUNE=quality)
echo "$out" | grep -q 'VARIANT=bit280' || fail "knobs.sh TUNE=quality: not bit280: $out"
echo "$out" | grep -q 'KV_FORMAT=fp8' || fail "knobs.sh TUNE=quality: KV_FORMAT not explicit fp8: $out"
rc=0; err=$(src_knobs TUNE=speed 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "want quality" || fail "knobs.sh TUNE=speed: not refused: rc $rc: $err"
out=$(src_knobs TUNE=quality SESS=8 CAP=485376)
echo "$out" | grep -q 'SESS=8 CAP=485376' || fail "knobs.sh explicit SESS/CAP not kept: $out"
out=$(src_knobs TUNE=agents SESS=8 CAP=485376)
echo "$out" | grep -q 'KV_FORMAT=fp8' || fail "knobs.sh TUNE=agents: KV_FORMAT not explicit fp8: $out"
# the dial default: CONC=8 (bit280; the shipped .env sets ATTIC=1) resolves the measured attic row 1048576 (v3.2);
# attic off has no bit280 CONC=8 row, so the dial falls back to the TUNE CAP (776704) with a stderr line
out=$(src_knobs TUNE=quality ATTIC=1 GR8_IMAGE=gr8:v120-attic-a1a4)
echo "$out" | grep -q 'SESS=8 CAP=1048576' || fail "knobs.sh default CONC=8 ATTIC=1 dial: got: $out"
out=$(src_knobs TUNE=quality CONC=6 ATTIC=1 GR8_IMAGE=gr8:v120-attic-a1a4)
echo "$out" | grep -q 'SESS=6 CAP=776704' || fail "knobs.sh CONC=6 ATTIC=1 (the v3 row): got: $out"
err=$(src_knobs TUNE=quality 2>&1 >/dev/null)
echo "$err" | grep -q "CAP not measured for this CONC on this VARIANT" || fail "knobs.sh default dial attic off: no fallback stderr line: $err"
out=$(src_knobs TUNE=quality)
echo "$out" | grep -q 'SESS=8 CAP=776704' || fail "knobs.sh default CONC=8 dial (attic-off fallback CAP): got: $out"
# CONC unset + SESS set: the dial does not run
out=$(src_knobs TUNE=quality SESS=8 CAP=485376)
echo "$out" | grep -q 'SESS=8' || fail "knobs.sh explicit SESS keeps: $out"
# (the no-row fallback line: home has no measured rows in the real table)
err=$(src_knobs TUNE=agents SESS= CAP= VARIANT=home CONC=1 2>&1 >/dev/null)
echo "$err" | grep -q "CAP not measured for this CONC on this VARIANT" || fail "knobs.sh home no row: no fallback stderr line: $err"
out=$(src_knobs TUNE=agents SESS= CAP= VARIANT=home CONC=1 2>/dev/null)
echo "$out" | grep -q 'VARIANT=home SESS=1 CAP=776704' || fail "knobs.sh home CONC=1 no row (the v3 dial falls back to the TUNE CAP 776704): got: $out"
out=$(src_knobs TUNE=agents CONC=4 VARIANT=nonexistent-manifest.json 2>/dev/null)
echo "$out" | grep -q 'SESS=4 CAP=776704' || fail "knobs.sh CONC=4 missing manifest file (fallback TUNE CAP): got: $out"
out=$(src_knobs TUNE=agents CONC=4 CAP=700000)
echo "$out" | grep -q 'SESS=4 CAP=700000' || fail "knobs.sh CONC=4 user CAP kept: got: $out"
# rows with the attic column: a scratch conc.tsv inside this smoke copy (the repo file is never written)
printf 'home\t4\toff\t4\t776704\t3226\t131072\t2026-11-10\nhome\t4\ton\t4\t807168\t3345\t131072\t2026-11-10\n' > conc.tsv
out=$(src_knobs TUNE=agents SESS= CAP= CONC=4 VARIANT=home)
echo "$out" | grep -q 'VARIANT=home SESS=4 CAP=776704' || fail "knobs.sh CONC=4 attic-off row: got: $out"
out=$(src_knobs TUNE=agents SESS= CAP= CONC=4 VARIANT=home ATTIC=1 GR8_IMAGE=gr8:e231adb-attic)
echo "$out" | grep -q 'VARIANT=home SESS=4 CAP=807168' || fail "knobs.sh CONC=4 ATTIC=1 row: got: $out"
echo "$out" | grep -q 'EXTRA_ENV=GR8_ATTIC_SOCK=/run/spark-attic/attic.sock GR8_ATTIC_KEY_FILE=/run/gr8-attic/key$' \
  || fail "knobs.sh ATTIC=1: no attic EXTRA_ENV words: $out"
err=$(src_knobs TUNE=agents CONC=4 ATTIC=1 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "needs an image with the memory-reserve client" \
  || fail "knobs.sh ATTIC=1 pinned image: exit $rc: $err"
# the BUSY toggle (v3): the guard ships in the pinned stock image (gr8 PR #516, in ca7e874); BUSY=1 accepts
# it by digest with no docker needed, rides the guard words with the v3 recipe defaults (idle 60 / retry 60 /
# queue 8, gr8's own upstream pair, the measured lane's), keeps explicit values, refuses an image without the
# guard with the fix named, and BUSY=0 adds no words
out=$(src_knobs TUNE=quality BUSY=1 2>/dev/null)
echo "$out" | grep -q 'EXTRA_ENV=GR8_BUSY_GUARD=1 GR8_BUSY_IDLE_SECS=60 GR8_BUSY_RETRY_AFTER=60 GR8_BUSY_QUEUE_MAX=8$' \
  || fail "knobs.sh BUSY=1 stock pin: guard words or v3 defaults wrong: $out"
out=$(src_knobs TUNE=quality BUSY=1 BUSY_IDLE_SECS=45 BUSY_RETRY_AFTER=30 BUSY_QUEUE_MAX=4)
echo "$out" | grep -q 'GR8_BUSY_GUARD=1 GR8_BUSY_IDLE_SECS=45 GR8_BUSY_RETRY_AFTER=30 GR8_BUSY_QUEUE_MAX=4' \
  || fail "knobs.sh BUSY=1 explicit knobs: got: $out"
err=$(src_knobs TUNE=quality BUSY=1 GR8_IMAGE=ghcr.io/kindlingai/gr8:sha-e231adb 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "needs an image with the busy guard" \
  || fail "knobs.sh BUSY=1 old image without the guard: exit $rc: $err"
err=$(src_knobs TUNE=quality BUSY=2 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "want 0 (off) or 1" || fail "knobs.sh BUSY=2: exit $rc: $err"
out=$(src_knobs TUNE=quality BUSY=0 GR8_IMAGE=ghcr.io/kindlingai/gr8:sha-e231adb)
echo "$out" | grep -q 'EXTRA_ENV=GR8_BUSY' && fail "knobs.sh BUSY=0: busy words present: $out" || true
# the Retry-After/idle coherence (v3): RETRY >= IDLE is a WARNING, not a refusal — the v3 default pair IS 60/60
# (the measured lane's); the words still ride EXTRA_ENV and the reason names the v2.1 finding and the 120/20 pair
rc=0; err=$(src_knobs TUNE=quality BUSY=1 BUSY_IDLE_SECS=60 BUSY_RETRY_AFTER=60 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] && echo "$err" | grep -q "is not under BUSY_IDLE_SECS" \
  || fail "knobs.sh BUSY=1 60/60: no warning: rc $rc: $err"
rc=0; err=$(src_knobs TUNE=quality BUSY=1 BUSY_IDLE_SECS=45 BUSY_RETRY_AFTER=90 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] && echo "$err" | grep -q "is not under BUSY_IDLE_SECS" \
  || fail "knobs.sh BUSY=1 45/90: no warning: rc $rc: $err"
err=$(src_knobs TUNE=quality BUSY=1 BUSY_RETRY_AFTER=notanumber 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "want whole seconds" || fail "knobs.sh BUSY=1 non-numeric retry: exit $rc: $err"
# the docs name the shipped defaults (60/60/8) and the coherence rule
grep -q "BUSY_RETRY_AFTER 60" knobs.sh || fail "knobs.sh: BUSY_RETRY_AFTER default 60 missing"
grep -q "recipe 60 (gr8 upstream 60)" README.md || fail "README.md: BUSY_RETRY_AFTER default row not the recipe 60"
grep -q "BUSY_IDLE_SECS 60, BUSY_RETRY_AFTER 60" AGENTS.md || fail "AGENTS.md: the v3 BUSY defaults missing"
# v3.3: the README build of the default image names v1.2.0 and the two gr8 main commits, and the default
# tag matches .env.example in README and AGENTS; no placeholder is left in the docs
grep -q '^  git cherry-pick d4af92d5 77e82fef' README.md || fail "README.md: the v3.3 build step (#612 d4af92d5, #613 77e82fef) missing"
grep -q 'git checkout -b v120-attic-a1a4 ab2eb95f' README.md || fail "README.md: the v3.3 build base (gr8 v1.2.0 ab2eb95f) missing"
grep -q 'gr8:v120-attic-a1a4' AGENTS.md || fail "AGENTS.md: the v3.3 default image tag missing"
python3 -c 'import json,sys; v=json.load(open("kindling.json"))["version"]; sys.exit(0 if v==3.3 else 1)' \
  || fail "kindling.json: version is not 3.3"
if grep -nE 'PROOF_BOOT_LINE|\[TBD\]' README.md AGENTS.md kindling.json; then fail "docs: a placeholder is left"; fi
err=$(src_knobs TUNE=agents SESS= CAP= VARIANT=home CONC=4 CAP=900000 2>&1 >/dev/null)
echo "$err" | grep -q "is above the measured 776704" || fail "knobs.sh CONC=4 over-cap: no warning: $err"
out=$(src_knobs TUNE=agents SESS= CAP= VARIANT=home CONC=4 CAP=700000)
echo "$out" | grep -q 'VARIANT=home SESS=4 CAP=700000' || fail "knobs.sh CONC=4 user CAP under measured kept: got: $out"
err=$(src_knobs TUNE=agents CONC=3 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "want 1, 2, 4, 6 or 8" || fail "knobs.sh CONC=3: exit $rc: $err"
err=$(src_knobs TUNE=agents ATTIC=maybe 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "ATTIC=maybe: want 0" || fail "knobs.sh ATTIC=maybe: exit $rc: $err"
# a bad TUNE exits 2 naming the values
rc=0; err=$(src_knobs TUNE=fast 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "want quality" || fail "knobs.sh TUNE=fast: exit $rc: $err"
# a wrong PEERS count exits 2
rc=0; err=$(PEERS=10.0.0.1,10.0.0.2 bash -c '. "$1/knobs.sh"' _ "$here" 2>&1) || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q "want the four boxes" || fail "knobs.sh PEERS count: exit $rc: $err"
# the settings layers: scripts/local.sh feeds knobs.sh; an exported variable beats it
printf 'CONC=1\n' > scripts/local.sh
out=$(src_knobs TUNE=agents SESS= CAP= VARIANT=home 2>/dev/null)
echo "$out" | grep -q 'SESS=1 CAP=776704' || fail "knobs.sh scripts/local.sh CONC=1 (fallback TUNE CAP): got: $out"
out=$(CONC=4 src_knobs TUNE=agents SESS= CAP= VARIANT=home)
echo "$out" | grep -q 'SESS=4 CAP=776704' || fail "knobs.sh exported CONC beats local.sh: got: $out"
echo "ok: knobs.sh dispatches TUNE=quality|context|agents|agents-fast (with its warning), defaults VARIANT=bit280 CONC=6, refuses bad values, reads scripts/local.sh under the exported environment"

# v2.1 (issue #1, reported by Chuck @adapt-ai-systems): the built image carries everything the boot path reads.
# knobs.sh sources conc_lookup.sh next to itself; conc_lookup.sh reads conc.tsv and manifests/ next to itself
# (BASH_SOURCE) — every referenced path must be COPYed by the Dockerfile or the CONC dial silently dies in it.
copy_set=$(awk '/^COPY /{for(i=2;i<NF;i++) printf "%s\n", $i}' Dockerfile | sort -u)
need_copied() { printf '%s\n' "$copy_set" | grep -qx "$1" || fail "Dockerfile does not COPY $1 (the boot path reads it; issue #1)"; }
need_copied knobs.sh
need_copied entrypoint.sh
need_copied conc_lookup.sh
need_copied conc.tsv
need_copied manifests/
need_copied bin/gr8
# the completeness rule itself: every dirname-BASH_SOURCE reference in knobs.sh / conc_lookup.sh resolves
# inside the COPY set (a file maps to itself; anything under manifests/ maps to the manifests/ COPY)
for ref in $(grep -hoE 'dirname "\$\{BASH_SOURCE\[0\]\}\}/[A-Za-z0-9_./-]+' knobs.sh conc_lookup.sh \
              | sed 's|.*}}/||' | sort -u); do
  case "$ref" in
    conc_lookup.sh) need_copied conc_lookup.sh ;;
    manifests/*) printf '%s\n' "$copy_set" | grep -qx manifests/ || fail "Dockerfile does not COPY manifests/ ($ref; issue #1)" ;;
    *) printf '%s\n' "$copy_set" | grep -qx "$ref" || fail "Dockerfile does not COPY $ref (the boot path reads it; issue #1)" ;;
  esac
done
grep -q '\[ -f "\$tsv" \]' conc_lookup.sh || fail "conc_lookup.sh: the conc.tsv read is not BASH_SOURCE-relative (issue #1)"
echo "ok: the Dockerfile COPYs every file the boot path reads (issue #1)"

# 4. fetch --print / --check, on a scratch copy of .env.example (cp, never mv; the scratch .env stays in place)
pins=$(./fetch --print)
echo "$pins" | grep -q '^MODEL=https://huggingface.co/kindlingai/glm-5.3-exlr8-k2-k3-k4@9e25c28a2e8808d8b2599d780521fd6af24e7558$' \
  || fail "fetch --print: MODEL pin: $pins"
echo "$pins" | grep -q '^DRAFTER=https://huggingface.co/incoai/GLM-5.3-DFlash2@' || fail "fetch --print: DRAFTER pin: $pins"
cp .env.example .env
./fetch --check || fail "fetch --check: non-zero on the pinned .env"
printf 'MODEL=https://huggingface.co/kindlingai/glm-5.3-exlr8-k2-k3-k4@0000000000000000000000000000000000000000\n' >> .env
rc=0; ./fetch --check 2>/dev/null || rc=$?
[ "$rc" != 0 ] || fail "fetch --check: accepted an unpinned MODEL"
echo "ok: fetch --print prints the pins and --check rejects an off-pin MODEL (scratch .env left in place)"

# 5. compose.yaml parses (python3+yaml when available; docker compose config when docker is present)
if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
  python3 -c 'import yaml,sys; yaml.safe_load(open("compose.yaml")); yaml.safe_load(open(".github/workflows/ci.yml"))' \
    || fail "compose.yaml / ci.yml: not valid YAML"
  echo "ok: compose.yaml and ci.yml are valid YAML"
else
  echo "skip: YAML parse (no python3 yaml on this runner)"
fi
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  if docker compose config >/dev/null; then
    echo "ok: docker compose config accepts compose.yaml + .env.example"
  else
    fail "docker compose config failed"
  fi
else
  echo "skip: docker compose config (no docker on this runner)"
fi

# 6. ./glm53 against tests/fake-docker (no docker needed). Each .env variant is a new file made with cp/printf/sed in
#    this scratch copy; the fake logs every docker call to tests/fake-docker.log.
export DOCKER="$here/tests/fake-docker" FAKE_LOG="$here/tests/fake-docker.log" \
  FAKE_SHOW_CONFIG="$here/tests/fixtures/show-config.txt" FAKE_SUPERVISOR_DIR="$here/tests/fixtures/supervisor" \
  GLM53_WATCH_S=1 GLM53_POLL_S=1 GLM53_DOWN_WAIT_S=1
G="$here/glm53"
expect() {  # expect RC PATTERN WHAT -- [NAME=value...] COMMAND...: the exit code, and a line of the output
  local want=$1 pat=$2 what=$3 rc=0 out
  shift 4
  out=$(env "$@" 2>&1) || rc=$?
  [ "$rc" = "$want" ] && printf '%s\n' "$out" | grep -q -- "$pat" || fail "glm53 $what: exit $rc (want $want): $out"
}
cp .env.example tests/env-ok
cp .env.example tests/env-plain-gr8 && printf 'GR8_MOE_TOPK=6\n' >> tests/env-plain-gr8
cp .env.example tests/env-twice && printf 'EXTRA_ENV=GR8_S2_TIMELINE=50\n' >> tests/env-twice
printf 'not a NAME=value line\n' > tests/env-bad
cp .env.example tests/env-sess4 && printf 'SESS=4\n' >> tests/env-sess4
cp .env.example tests/env-typo && printf 'SESSS=8\n' >> tests/env-typo
sed 's|^EXTRA_ENV=.*|EXTRA_ENV=GR8_GEN_CACHE=/var/lib/gr8/cache/gen-cache GR8_L2PF=1|' .env.example > tests/env-extra
cp .env.example tests/env-fast && printf 'TUNE=agents-fast\n' >> tests/env-fast
expect 0 "^ok: tests/env-ok" "check-env (.env.example)" -- GLM53_ENV_FILE=tests/env-ok "$G" check-env
expect 0 "not bit-exact against a cold prefill (gr8 SETTINGS.md)" "check-env (TUNE=agents-fast warns)" -- \
  GLM53_ENV_FILE=tests/env-fast "$G" check-env
expect 2 "onto the one EXTRA_ENV line" "check-env (plain GR8_MOE_TOPK)" -- GLM53_ENV_FILE=tests/env-plain-gr8 "$G" check-env
expect 2 "EXTRA_ENV is set twice" "check-env (EXTRA_ENV twice)" -- GLM53_ENV_FILE=tests/env-twice "$G" check-env
expect 2 "not a NAME=value line" "check-env (bad line)" -- GLM53_ENV_FILE=tests/env-bad "$G" check-env
echo "ok: glm53 check-env refuses a plain GR8_* engine line, a name set twice and a non-NAME=value line; warns on agents-fast"
sc=tests/fixtures/show-config.txt
expect 0 "^ok: every knob" "check-config (.env.example)" -- GLM53_ENV_FILE=tests/env-ok "$G" check-config --from "$sc"
expect 3 "MISSING: SESS=4" "check-config (SESS=4, show-config 8)" -- GLM53_ENV_FILE=tests/env-sess4 "$G" check-config --from "$sc"
expect 3 "MISSING: SESSS=8" "check-config (a misspelled knob)" -- GLM53_ENV_FILE=tests/env-typo "$G" check-config --from "$sc"
expect 3 "MISSING: EXTRA_ENV word GR8_L2PF=1" "check-config (EXTRA_ENV word)" -- GLM53_ENV_FILE=tests/env-extra "$G" check-config --from "$sc"
echo "ok: glm53 check-config finds a set knob that show-config does not show (value, misspelling, EXTRA_ENV word)"
expect 4 "Flash-model option" "up (restart loop)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="restarting 1 2" "$G" up
grep -q "^docker update --restart=no glm53-4x-spark$" tests/fake-docker.log || fail "glm53 up: the restart loop was not stopped"
expect 0 "^ok: every knob" "up (healthy)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="running 0 0" "$G" up
expect 0 "^ok: every knob" "up (after a stopped loop)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="running 0 0" FAKE_POLICY=no "$G" up
grep -q "^docker compose -f compose.yaml -f compose.attic.yaml up -d --force-recreate$" tests/fake-docker.log \
  || fail "glm53 up: no --force-recreate after a stopped loop"
expect 2 "onto the one EXTRA_ENV line" "up (plain GR8_* line)" -- GLM53_ENV_FILE=tests/env-plain-gr8 FAKE_STATE="running 0 0" "$G" up
expect 0 "^ok: every knob" "up --build" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="running 0 0" "$G" up --build --no-watch
grep -q "^docker compose -f compose.yaml -f compose.attic.yaml up -d --build$" tests/fake-docker.log \
  || fail "glm53 up --build: no docker compose up -d --build"
expect 1 "unknown option" "up (bad option)" -- GLM53_ENV_FILE=tests/env-ok "$G" up --bulid
echo "ok: glm53 up stops a restart loop with the engine's error (exit 4), passes a healthy boot, recreates after a loop"
for st in absent "exited 0 0" "created 0 0"; do
  expect 0 "already down" "down ($st)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="$st" "$G" down
done
expect 0 "Flash-model option" "down (restart loop)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="restarting 5 2" "$G" down
expect 0 "" "down (running)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="running 0 0" "$G" down
expect 1 "down failed" "down (failed on a running box)" -- GLM53_ENV_FILE=tests/env-ok FAKE_STATE="running 0 0" FAKE_DOWN_RC=1 "$G" down
echo "ok: glm53 down exits 0 on a box that is down or looping, 1 when down fails on a running box"

# 7. DRY_RUN=1 on up: prints the plan, changes nothing (fake-docker.log does not grow)
DRY=$here/tests/.smoke-run-layers-$(date +%Y%m%dT%H%M%S)
mkdir -p "$DRY/scripts"
cp scripts/config.sh "$DRY/scripts/config.sh"
printf 'SETVAR=from-env-file\nEVIL=$(touch %s/marker)\n' "$DRY" > "$DRY/.env"
printf 'SETVAR=from-local-sh\n' > "$DRY/scripts/local.sh"
out=$(cd "$DRY" && env -u SETVAR bash -c '. ./scripts/config.sh && printf "%s" "$SETVAR"')
[ "$out" = "from-local-sh" ] || fail "config.sh local.sh over .env: got: $out"
out=$(cd "$DRY" && SETVAR=from-exported bash -c '. ./scripts/config.sh && printf "%s" "$SETVAR"')
[ "$out" = "from-exported" ] || fail "config.sh exported environment beats local.sh: got: $out"
mkdir -p "$DRY/bare/scripts"
cp scripts/config.sh "$DRY/bare/scripts/config.sh"
out=$(cd "$DRY/bare" && env -u SETVAR GLM53_ENV_FILE=/nonexistent bash -c '. ./scripts/config.sh && printf "%s" "${SETVAR-UNSET}"')
[ "$out" = "UNSET" ] || fail "config.sh missing .env and local.sh is quiet: got: $out"
[ -f "$DRY/marker" ] && fail "config.sh executed an .env line (EVIL=$(touch ...))" || true
out=$(cd "$DRY" && env -u SETVAR bash -c '. ./scripts/config.sh && printf "%s" "$EVIL"')
[ "$out" = '$(touch '"$DRY"'/marker)' ] || fail "config.sh .env literal parse: got: $out"
echo "ok: settings layers exported env > scripts/local.sh > .env > unset, .env parsed never executed"

n1=$(wc -l < tests/fake-docker.log)
expect 0 "DRY_RUN: ./glm53 up on this box would:" "up (dry run)" -- DRY_RUN=1 GLM53_ENV_FILE=tests/env-ok "$G" up
n2=$(wc -l < tests/fake-docker.log)
[ "$n1" = "$n2" ] || fail "glm53 up DRY_RUN=1 ran docker ($n1 -> $n2 fake-docker lines)"
out=$(DRY_RUN=1 GLM53_ENV_FILE=tests/env-ok "$G" up 2>&1) || true
echo "$out" | grep -q "docker compose -f compose.yaml -f compose.attic.yaml up -d" \
  || fail "up DRY_RUN: plan has no compose command (the v3 default .env sets ATTIC=1): $out"
echo "$out" | grep -q "nothing was changed" || fail "up DRY_RUN: no nothing-changed line: $out"
echo "ok: DRY_RUN=1 up prints the plan (settings, compose command, watch) and runs nothing"

# 8. install --this-box: .env from .env.example only when missing (never overwrites), DRY_RUN runs nothing.
#    (install runs ./fetch --check, which reads the default .env: section 4 left it off-pinned on purpose, so
#    restore a pinned one first — cp, never mv.)
cp .env.example .env
INSTALL_ENV=$here/tests/env-install-missing
irc=0
out=$(GR8_IMAGE= GR8_CACHE="$DRY" GLM53_ENV_FILE="$INSTALL_ENV" "$G" install --this-box 2>&1) || irc=$?
[ "$irc" = 0 ] || fail "install --this-box (no .env): exit $irc: $out"
cmp -s "$INSTALL_ENV" .env.example || fail "install did not copy .env.example to the missing .env verbatim"
before=$(md5sum tests/env-ok | cut -d" " -f1)
irc=0
out=$(GR8_IMAGE= GR8_CACHE="$DRY" GLM53_ENV_FILE=tests/env-ok "$G" install --this-box 2>&1) || irc=$?
[ "$irc" = 0 ] || fail "install --this-box (existing .env): exit $irc: $out"
after=$(md5sum tests/env-ok | cut -d" " -f1)
[ "$before" = "$after" ] || fail "install overwrote an existing .env"
n1=$(wc -l < tests/fake-docker.log)
irc=0
out=$(DRY_RUN=1 GR8_IMAGE= GR8_CACHE="$DRY" GLM53_ENV_FILE=tests/env-ok "$G" install --this-box 2>&1) || irc=$?
[ "$irc" = 0 ] || fail "install DRY_RUN: exit $irc: $out"
n2=$(wc -l < tests/fake-docker.log)
[ "$n1" = "$n2" ] || fail "install DRY_RUN ran docker"
echo "$out" | grep -q "DRY_RUN: check docker" || fail "install DRY_RUN: no plan: $out"
echo "ok: install --this-box writes .env from .env.example only when missing, never overwrites, DRY_RUN runs nothing"

echo "smoke OK"
