# GLM-5.3 (full) EXLR8 on four DGX Sparks
**If you are an agent booting this recipe for someone: read [AGENTS.md](AGENTS.md) first, then the Quickstart.**

[GLM-5.3](https://huggingface.co/zai-org/GLM-5.3) on four DGX Sparks (GB10, 128 GB each) at TP=4, served by
[gr8](https://github.com/kindlingai/gr8) from the kindlingai exlr8 release
[`glm-5.3-exlr8-k2-k3-k4`](https://huggingface.co/kindlingai/glm-5.3-exlr8-k2-k3-k4): our bit275 width manifest (about
2.75 bits per routed weight), a concurrency dial (`CONC=1|2|4|8`), optional spark-attic memory lending, fp8 KV,
MTP + DFlash2 drafting, and a persistent SSD KV store so a stop keeps open chats for the next boot.

**Default:** `VARIANT=bit275` at `CONC=4`. Every number in this README is our measurement on four DGX Sparks, or is
marked as someone else's. Nothing unmeasured is presented as measured; "What is not measured yet" lists the gaps.

## Measured: the `home` baseline (2026-11-07)

All numbers below are **our measurements, 2026-11-07**, on this recipe's stack: four DGX Sparks on a 200G switch,
gr8 image `ghcr.io/kindlingai/gr8:sha-e231adb` (digest `sha256:d920e26b3105f9f56f7766121394da1e37fb93d82e2176e20f8c1c2e64f4f174`),
gr8 commit `e231adb`, release `kindlingai/glm-5.3-exlr8-k2-k3-k4@9372b74d77e129ea063bc0934df1570fc3173469`, variant
`home`, gr8 TP=4 defaults (SESS=8, CAP=485376, fp8 KV, MTP + DFlash2). Three fresh boots (full down/up each); gr8
bench rows are one bench per boot, RigMark rows are the median of three RigMark invocations per boot (checkout
`770c310`, protocol 1.3.0, `reasoning_effort` low). These are the `home` manifest rows at SESS=8; the bit275 rows are in the
concurrency table below.

| row | value (mean of 3 boots) |
|---|---|
| decode, one stream: code / prose / structured | 65.5 / 39.0 / 77.8 tok/s |
| all streams together: 2 / 4 | 62.7 / 73.4 tok/s |
| prefill, cold, 8K prompt | 1,478.6 tok/s |
| longest request (CAP) | 485,376 tokens |
| sessions at once (SESS) | 8 |
| boot to `/health` ready | 101.9-104.9 s |
| smoke | 14/14 on each boot |
| temp-0 exactness | replies identical across all three boots (gr8's own check) |

RigMark single stream, effort low (medians, mean of the three boot medians):

| rigmark row | value |
|---|---|
| code p50 | 55.8 tok/s |
| prose p50 | 36.3 tok/s |
| structured p50 | 63.0 tok/s |
| C4 aggregate (4 concurrent streams) | 87.8 tok/s |

Reference points, **not this recipe's numbers**: gr8's published TP=4 bar for this model (gr8 docs/GLM-5.3.md,
2026-10-24) is decode 52.1 / 34.2 tok/s, C2/C4 54.0 / 69.0, prefill 8K cold 1,357 tok/s; a peer TensorFold TP=4 +
DFlash2 recipe reports RigMark p50 69.2 / 55.7 / 73.6 (single stream).

## The bit275 width manifest

The shipped `manifests/exlr8-manifest-bit275.json` (sha256 `96088cce...`) is derived from the manifests of
[kindlingai/glm-5.3-exlr8-k2-k3-k4](https://huggingface.co/kindlingai/glm-5.3-exlr8-k2-k3-k4) (the release this
recipe pins); the release and the base model are KindlingAI's, under **CC BY 4.0**
(https://creativecommons.org/licenses/by/4.0/), and the GLM-5.3 License still applies to the model weights.
The manifest re-uses the release trellis widths at a different layer split: the layer choice **extends the
shipped bit243/bit260 pattern — it is not a measured KL order**. **KL: pending** (no KL card yet).

## Pick what to prioritize

`TUNE` picks one of four sets of settings (`knobs.sh`; the `speed` slot was removed — its two measured knobs were
no gain). A `VARIANT`, `SESS`, `CAP`, `SHARE_LIMIT` or `KV_FORMAT` you set yourself keeps your value, and anything
already in `EXTRA_ENV` is kept after the tier's words. The default: `VARIANT=bit275` (the manifest ships in
`manifests/exlr8-manifest-bit275.json`) at `CONC=4` — the serving choice.

The concurrency dial: `CONC=1|2|4|8` picks how many requests decode at once and takes the KV cache the freed slots
give back — `CAP` follows the largest pool a boot at that `SESS` measured holding the serving floor (9 GiB free at
ready, never under 8 GiB under load). `./glm53 conc` prints this table for your `VARIANT`; a `CAP` you set always
wins (one above the measured value prints a warning on `./glm53 up`). Measured on bit275, SHARE_LIMIT 16384
(speed cells cite the attic-on boots: single-chat speed is the same with the reserve layer on or off):

| CONC | attic | CAP (tokens) | pages a rank | tokens per session | single-chat code/prose/structured | C4 | C8 | quality panel | measured |
|---|---|---|---|---|---|---|---|---|---|
| 8 | on | 617,984 | 2,606 | 30,720 | 60.7 / 38.3 / 65.5 | 94.8 | 115.2 | 12/12 | 2026-11-11 |
| 4 | on | 776,704 | 3,226 | 154,624 | 59.3 / 37.7 / 66.6 | 95.5 | 94.9 | 12/12 | 2026-11-10 |
| 2 | on | 845,056 | 3,493 | 395,264 | 59.9 / 38.2 / 67.2 | 70.9* | 71.6* | 12/12 | 2026-11-10 |
| 1 | on | 864,256 | 3,568 | 861,184 | as CONC 2-8 (same single-chat speed) | 51.4* | 51.4* | 12/12 | 2026-11-11 |
| 8 | off | 544,256 | 2,318 | 21,504 | as attic on | not measured | not measured | 12/12 | 2026-11-11 |
| 4 | off | 694,784 | 2,906 | 134,144 | as attic on | not measured | not measured | 12/12 | 2026-11-11 |
| 2 | off | 763,136 | 3,173 | 354,304 | as attic on | not measured | not measured | 12/12 | 2026-11-11 |
| 1 | off | 765,952 | 3,184 | 762,880 | as attic on | not measured | not measured | 12/12 | 2026-11-11 |

\* CONC 2 keeps 2 decode slots: its C4/C8 aggregate is the 4-chat/8-chat load on 2 slots (per chat 36.7/36.7),
not a bigger pool's throughput. CONC 1 had no speed run of its own: its cells cite the CONC 2-8 single-chat rows,
which are the same. Speed: RigMark single stream (code / prose / structured, tok/s) and C4/C8 aggregate tok/s.
Memory: every row held 9 GiB free per box at ready and never went under 8 GiB under load.

| `TUNE` | sets | you get | status |
|---|---|---|---|
| `quality` (default) | `VARIANT=bit275`, `CONC=4`; gr8's launcher defaults otherwise | The exact model's output (temp-0 identical across boots), 4 sessions, the CONC 4 pool (694,784 tokens; 776,704 with `ATTIC=1`). | **Measured** 2026-11-10/11 (the concurrency table) |
| `context` | `KV_FORMAT=int4`, `CAP=513536` | The int4 KV trade (gr8 docs/KV4.md: decode −2.3-3.3 %, prefill +5.8 %, temp-0 output moves marginally), a 513,536-token pool. | **Knobs set, not measured** on four Sparks |
| `agents` | quality's settings and `SHARE_LIMIT=16384` | For agents (long prompts that come back turn after turn). Every rank holds a session's first `SHARE_LIMIT` tokens and a quarter of the rest, so the same 485,376-token pool keeps four 60-70K-token agents at once (1,857 of 2,088 pages a rank) and each warm turn is a prefix hit. Exact output, as quality. The cost: a request over 16,384 tokens (prompt + max_tokens) decodes alone instead of sharing decode steps (over 32,768 at quality). | **Measured** 2026-11-09 (same image and commits): the table below |
| `agents-fast` (opt-in) | `TUNE=agents` and `GR8_REUSE_ALIGN=0` (on `EXTRA_ENV`) | A warm turn prefills only its new tokens: a prefix hit keeps the whole matched prefix instead of whole 4,096-row cells. **Not bit-exact against a cold prefill (gr8 SETTINGS.md)**: a warm turn can get other temp-0 text than the same request sent cold. `knobs.sh` prints that warning on every boot and command, and `./glm53 check-env` before the boot. | **Measured** 2026-11-09: the second table below. Opt-in only, never the default |

`TUNE=agents`, measured 2026-11-09 on this rig (our measurements; same image, commits and protocols as "Measured"; the
agent replay is four agents x 6 turns with ~60K-token prompts, staggered starts, temp 0):

| row | value |
|---|---|
| agent replay: warm-turn TTFT p50 / p90 | 5.9 s / 8.4 and 10.0 s (two boots); no agent evicted |
| RigMark p50 code / prose / structured (one boot) | 56.4 / 36.1 / 61.9 tok/s |
| RigMark C4 / C8 aggregate (one boot) | 87.6 / 108.3 tok/s |
| needles at 64K and 128K (5 depths each) | 10/10 (and 10/10 at SHARE_LIMIT 16384 with a larger pool, CAP 534528) |
| quality panel (12 Python tasks, temp 0) | 12/12 |
| free memory a rank after the KV pool | 11.8-12.1 GiB |

`TUNE=agents-fast`, measured 2026-11-09 on this rig (same agent replay; the needle and panel re-asks send the same
document or task again right after the first answer, so the second request is a prefix-pool hit):

| row | value |
|---|---|
| agent replay: warm-turn TTFT p50 / p90 | 3.4 s / 5.2 s on the boot with clean clocks (3.5-3.6 s / 4.7-4.8 s on three more boots whose windows were void by thermal throttle); every warm turn a hit, no agent evicted, on all four |
| agent decode, each of the four agents | 11.7-12.3 tok/s on the clean boot (9.7-11.6 with `TUNE=agents`) |
| needles at 64K and 128K (5 depths each) | 10/10, and 10/10 re-asked as a pool hit (all but the question's 31 tokens reused) |
| quality panel (12 Python tasks, temp 0) | 12/12 on two boots; 12/12 with each task re-asked as a pool hit |
| warm hit against a cold prefill: four two-turn chats (~5,300-token prompts), turn 2's 64-token reply re-done cold | 2 of 4 replies differ, 59 and 69 characters in; 3 of 4 on a second boot. The differences are other wording or other items, not broken text |

## Knobs

| knob | values | default |
|---|---|---|
| `PEERS` | the four boxes' 10G LAN addresses, comma-separated, head first, the same list on every box; the head serves port 8100 | none: required unless `MENTAT=1` |
| `IPS`, `IPS2` | each box's ConnectX address on PCIe root 1 and root 2, in `PEERS` order | none (recommended on a switch) |
| `SHAPE` | `ring`: four boxes cabled in a ring without a switch; list `PEERS` in cable order, leave out `IPS`/`IPS2` | unset (a switch) |
| `TP` | 4 | `4` |
| `TUNE` | `quality`, `context`, `agents`, `agents-fast` (opt-in, not bit-exact) | `quality` |
| `VARIANT` | `bit275` (shipped in `manifests/`), or the release's width manifests: `home` (measured), `bit325`, `bit338`, `up1`, `bit225`, `bit243`, `bit260`, `down1`, or a path to a custom exlr8-v2-manifest JSON | `bit275` (`home` for `context`/`agents`) |
| `SESS` | requests decoding at once, 1-8 | set by `CONC` (4) |
| `CONC` | `1`, `2`, `4`, `8`: the concurrency dial. Sets `SESS` and lets `CAP` follow the largest CAP a boot at that SESS measured holding the serving floor (9 GiB free at ready, never under 8 GiB under load) — fewer slots, more KV cache per session (`./glm53 conc` prints the measured table for your `VARIANT`, split by the `attic` column). A `CAP` you set keeps your value; one above the measured value warns (it is not refused). A pair with no measured row falls back to `SESS=CONC` and the `TUNE`'s `CAP`, with a stderr line | `4` |
| `ATTIC` | `1`: boot with the memory-reserve layer ([spark-attic](https://github.com/bertholomus/spark-attic)) lending each rank its display-carveout slice (`compose.attic.yaml` is added to the compose files, and the `CONC` rows with `attic on` apply). Needs `GR8_IMAGE` to name an image **with** the attic client — the pinned `ghcr.io/kindlingai/gr8:sha-e231adb` has none and `ATTIC=1` is refused with the fix named. The gr8 attic client is not in a published gr8 image yet: `ATTIC=1` needs a gr8 build that includes it | `0` |
| `CAP` | the KV pool in tokens, shared by the sessions, a multiple of 64 | by `TUNE` (485376; 513536 with int4 KV) |
| `SHARE_LIMIT` | requests up to this many tokens (prompt + max_tokens) share decode steps; every rank holds a session's first `SHARE_LIMIT` tokens and a share of the rest. A multiple of 64 from 4096 | by `TUNE` (gr8's 32768; 16384 with `TUNE=agents` and `agents-fast`) |
| `KV_STORE` | `ssd:<dir>,size=200G,persist=on,keep=sessions`: at an orderly stop the engine writes open chats to the SSD; the next boot restores their KV | the recipe default, in `.env.example` |
| `GR8_STOP_GRACE` | docker's stop grace, read by `compose.yaml` | `150s` with the SSD KV store, or docker kills the engine mid-store |
| `MENTAT` | `0`: the boxes in `PEERS`. `1`: find the boxes through the host's `mentat` daemon and register the API in group `GROUP` | `0` |
| `GR8_IMAGE` | the pinned image, read by `compose.yaml` | `ghcr.io/kindlingai/gr8:sha-e231adb` |
| `MODEL`, `DRAFTER` | the release and the drafter, each pinned to a Hugging Face commit | the commits measured above (`./fetch --print` prints them) |
| `EXTRA_ENV` | engine settings, `NAME=value` pairs separated by spaces | `GR8_GEN_CACHE=/var/lib/gr8/cache/gen-cache` |

**UPDATE 2 (Kindling, 2026-11-07, verified on this rig): `GR8_*` engine knobs reach the engine only through
`EXTRA_ENV`.** A plain `GR8_FOO=...` line in `.env` is dropped by the launcher (`-e GR8_MOE_TOPK=6` never appeared in
`engine.env`; `-e EXTRA_ENV=GR8_MOE_TOPK=6` did). Append new `GR8_*` knobs to the one `EXTRA_ENV` line,
space-separated, never replacing what is there. Short launcher names (`SESS`, `CAP`, `KV_FORMAT`, `DFLASH_K`, ...)
stay plain `.env` lines.

## Quickstart

First, on every box, fetch this box's part of the release and the drafter:

```bash
git clone <this recipe> && cd glm-5.3-exlr8-4x-spark
cp .env.example .env          # set PEERS, IPS and IPS2 (or MENTAT=1): the same file on every box
./fetch                       # MODEL and DRAFTER are pinned; ./fetch --check verifies the pins
```

Each box downloads only its own rank part (~85.6 GB at TP=4, variant `home`). The DFlash2 drafter's licence is
CC BY-NC-ND 4.0: it forbids sharing a converted copy, so each box downloads and converts its own rank part.

Then, on all four boxes within 10 minutes of each other (the boxes wait for each other for 600 s):

```bash
./glm53 up                    # docker compose up -d, with the launcher checks below (about 2 minutes a box)
docker compose logs -f        # ready when the supervisor prints that the cluster serves
```

On the head:

```bash
./glm53 status                # every box's state
./glm53 smoke                 # exits 0 when every case passes
curl -s localhost:8100/health # {"ready":true,...} when the API serves
```

The API is OpenAI-compatible on the head's port 8100, model name `glm-5.3`. To stop and start again (the SSD KV
store keeps open chats across the stop; `GR8_STOP_GRACE=150s` gives the store time to write):

```bash
./glm53 down                  # on any box: stops every box, containers exit 0 and stay down
./glm53 up                    # on every box, to boot again
```

### The launcher (`./glm53`)

`./glm53` is `docker compose` plus the checks gr8 does not do itself. Each one is a failure this rig hit on
2026-11-07/08:

- **A `GR8_*` engine variable on its own `.env` line is refused** (`./glm53 check-env`, exit 2). gr8's launcher drops
  such a line without a word, so the boot runs without the knob. The message says to move it onto the one
  `EXTRA_ENV` line. The launcher options `GR8_MODEL` and `GR8_WORK_DIR` and compose's `GR8_IMAGE`,
  `GR8_STOP_GRACE`, `GR8_CACHE` and `GR8_HOME` stay plain lines. A name set twice is refused too: the last line wins,
  so a second `EXTRA_ENV` line silently replaces the first.
- **After `up`, every knob `.env` sets must show in `gr8 glm53 show-config` with its value** (`./glm53 check-config`,
  exit 3), and each `EXTRA_ENV` word must show in its `EXTRA_ENV` or engine env. A misspelled or dropped knob fails
  loudly instead of booting the defaults.
- **A container that restarts within 120 s of `up` is stopped cleanly** (exit 4). A refused option (bad options exit
  2, or an engine variable this build refuses) otherwise restarts the container forever. The engine's own error
  from `out/supervisor.log` is printed (`./glm53 error` prints it at any time).
- **`./glm53 down` is safe to repeat.** A box that is already down exits 0 (`docker compose exec gr8 gr8 glm53 down`
  exits 1 there, and 137 on the head when its own container stops under it). A restart-looping box, where the exec
  fails with "container ... is restarting", is stopped and its error printed. Run `./glm53 down` on each looping box.

`./glm53 up --build` builds the thin recipe image first (gr8's pinned image plus `knobs.sh`), for a box that cannot
pull it. `./glm53 status|smoke|health|show-config|logs` run `gr8 glm53 <command>` in this box's container.

## Switching

`KV_STORE=ssd:...,persist=on,keep=sessions` + `GR8_STOP_GRACE=150s` and
`EXTRA_ENV=GR8_GEN_CACHE=/var/lib/gr8/cache/gen-cache` are the fast-switching settings of gr8's
[SWITCHING.md](https://github.com/kindlingai/gr8/blob/main/docs/SWITCHING.md): at the stop each rank stores its open
chats on the SSD (45-194 ms per rank measured there, 2026-11-07), and the next boot reads the store's index back, so
a chat's next turn restores its KV instead of a prefill. The store and the gen cache live in the cache volume
(`/var/lib/gr8/cache/kv`, `/var/lib/gr8/cache/gen-cache`).

This recipe needs no separate `kv-store.yaml`: the SSD store is one `KV_STORE` line (gr8's inline form). The 2-box
Flash recipe's `kv-store.yaml` file is the Flash prompt-cache form (`FLASH_CACHE=aligned`), which the full GLM-5.3
recipe does not use.

## CI

`.github/workflows/ci.yml` runs a **no-GPU smoke** on every push: shell syntax of every script, `.env.example`
parses as `KEY=value` lines, `knobs.sh` dispatches all four `TUNE` names (and `agents-fast` prints its warning) (and refuses a bad one and a wrong
`PEERS` count), `./fetch --print` prints the pinned `MODEL` and `DRAFTER` commits, and `./glm53`'s checks run against
a stand-in docker (`tests/fake-docker`) and a show-config fixture in gr8's real format. Checks: `tests/ci-smoke.sh`.

## What is not measured yet

- `TUNE=context` on this rig: the int4 knobs come from gr8's KV4.md trade, not from our rows.
- bit275's KL against the full-precision model: no KL card yet.
- CONC 1-8 with `ATTIC=0`: memory, cache size and quality measured; C4/C8 aggregate speed not measured.
- A clean-boot switch timing GLM-5.3 ↔ another model on this recipe.
- Custom width manifests (`VARIANT=<path>`) other than the shipped bit275.

## Licence

The recipe's scripts and docs: MIT (LICENSE). `manifests/exlr8-manifest-bit275.json` is a modified KindlingAI exlr8
manifest, shared under CC BY 4.0 with credit to KindlingAI (see above). The model weights stay under the GLM-5.3
License; gr8 is KindlingAI's (MIT).
