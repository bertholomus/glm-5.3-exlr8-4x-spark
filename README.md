# GLM-5.3 (full) EXLR8 on four DGX Sparks
> **Installing with an AI agent? (most people do)** Paste this into Claude Code, Codex, ChatGPT or your own agent:
>
> `Install https://github.com/bertholomus/glm-5.3-exlr8-4x-spark on my four DGX Sparks. Follow its AGENTS.md exactly.`
>
> [AGENTS.md](AGENTS.md) is written for the agent: rules, a fast path, a check for every step, and the fix for each
> failure. Claude Code also reads [CLAUDE.md](CLAUDE.md), which points to the same file.

[GLM-5.3](https://huggingface.co/zai-org/GLM-5.3) on four DGX Sparks (GB10, 128 GB each) at TP=4, served by
[gr8](https://github.com/kindlingai/gr8) from the kindlingai exlr8 release
[`glm-5.3-exlr8-k2-k3-k4`](https://huggingface.co/kindlingai/glm-5.3-exlr8-k2-k3-k4): the release's own bit280 width
manifest (about 2.80 bits per routed weight, KindlingAI's v0.7 profile), a concurrency dial (`CONC=1|2|4|6|8`),
spark-attic memory lending (on by default), fp8 KV, MTP + DFlash2 drafting, and a persistent SSD KV store (on by
default) so a stop keeps chats for the next boot.

**Default:** `VARIANT=bit280` at `CONC=8`, attic on, the busy guard on, the SSD KV store on. Every number in this README is our measurement on four DGX Sparks, or is
marked as someone else's. Nothing unmeasured is presented as measured; "What is not measured yet" lists the gaps.

## What is new in v3.2.1

- **gr8 v1.1.1.** The stock image pin moves to
  `ghcr.io/kindlingai/gr8:v1.1.1@sha256:fa5c9f66fbfa55d162782578b3262893b782e6365a76562bcab951b54acc6d96`
  (gr8 a3f44a0, was 97089b3). KindlingAI's v1.1.1 fixes garbled TP=4 output (#557: prefill waits for the context-parallel
  staged index pool, and RDMA receive slots are read uncached). Their fix, validated by them on 4x GB10 with 4
  concurrent multi-turn sessions at 185K-195K tokens. The default lane runs `gr8:a3f44a0-attic` (v1.1.1 + the attic
  client). Nothing else changes: same weights, bit280, CONC 8, 1,048,576-token pool.
- **Checked on our four Sparks, one boot, 2026-11-22**, exactly the `.env.example` settings: smoke passed, quality panel
  12/12 with the same reply hashes as v3.2, agent replay 24/24 turns with 20/20 warm reuses (warm TTFT p50 6.75 s),
  C4 with the v3 boot's exact prompts, cold, 101.5 tok/s (v3.2: 99.0), 9.1-10.3 GiB free a box under load.
- **Not re-measured on v1.1.1:** the RigMark speed rows (8 chats, single chat). The v3.2 numbers below were measured on
  97089b3; v1.1.1 changes only the prefill synchronization above.

## What is new in v3.2

- **Rebased on gr8 97089b3, after KindlingAI's gr8 v1.1.0.** The stock image pin moves to
  `ghcr.io/kindlingai/gr8:sha-97089b3@sha256:717168f9afff1538c49383502e662fb45bd34d23630ac00f4d88fb1502b2fe4c`
  (was ca7e874). The engine work is theirs: gr8 v1.1.0 turns on its tuned TP=4 kernels and caps the MoE expert
  union per step at 48 (`MOE_UNION_CAP=48`, the image's own TP=4 default), and later commits add capacity-scaled
  CP sharding in RAM. The recipe sets no new engine knob; the default lane runs the attic build of this image
  (`gr8:97089b3-attic`, gr8 97089b3 + the attic client); the attic client is still NOT in any published gr8 image.
  Same weights (release v0.7 `9e25c28a`) and the same bit280 manifest as v3.1.
- **8 chats: 173.5 tok/s total, 23.0 per chat** (was 133.2 total, 17.9 per chat on v3.1, +30%). First token with 8
  chats arriving together: 0.38 s for every chat (v3.1: 0.39-0.41 s).
- **A bigger pool: 1,048,576 tokens** at `CONC=8` (was 950,272, +10%). `max_model_len` 1,048,562. The new engine
  also leaves more memory free: **9.0-9.3 GiB free a box at the lowest point under load** (v3.1: 5.4-5.7), so the
  bigger pool costs nothing against the v3.1 floor.
- **Single chat code/prose/structured 61.7 / 39.7 / 79.7 tok/s** (v3.1: 60.2 / 39.2 / 66.0). Structured output is
  +21%; code and prose are level.
- **4 chats:** RigMark C4 115.4 tok/s total, 30.0 per chat (the v3.1 boot: 99.7). With the v3 boot's exact prompts,
  cold, the gain is smaller: 99.0 vs 96.1 on v3.1 (+3%). We count that as the like-for-like row.
- **Agents:** agent replay 24/24 turns with 20/20 warm reuses; warm TTFT p50 5.95 s, p90 7.81 s (v3.1: 6.52 / 10.05 s).
- **The v3.2 measured row** — ONE boot, 2026-11-21, on our four Sparks with exactly the `.env.example` settings.
  RigMark is the median of 3 invocations; the clocks ran 2171-2190 MHz (under the 2250 clean-clock bar, no throttle
  flags, the same as the v3.1 boot); smoke passed, quality panel 12/12. A second boot of the same settings (the switch of
  our own lane) passed smoke and the panel 12/12 again and held 9.3-10.5 GiB free a box.
- **Honest rows:** prefill 8K 1,527.7 tok/s on gr8's own bench (v3.1: 1,554.7, -1.7%). The C8 gain is one boot.
  Attic-off rows are still NOT measured at CONC 8 on bit280.
- `conc.tsv`: the bit280 CONC 8 attic row is now this boot (CAP 1,048,576, 4,288 pages a rank, 84,992 tokens a
  session); the v3.1 row it replaces is described above. Version bumped to 3.2 in `kindling.json`.

## What is new in v3.1

- **Eight chats at once, and a bigger pool: 950,272 tokens** (was 6 chats at 776,704, +22%). Same weights, same
  bit280 manifest, same image as v3. Only the default dial moves: `CONC=8` (SESS 8, CAP 950,272, attic on). The
  memory comes from the free room v3 left on each box: the v3 boot kept 11.6-12.1 GiB free under load, and this one
  keeps 5.4-5.7 GiB free (5 s samples over the whole run).
- **8 chats: 133.2 tok/s total, 17.9 per chat** (was 103.7 total on v3, where only 6 decoded at once and the other
  2 waited). The wait for the first token with 8 chats arriving together: **0.39-0.41 s for every chat** (on v3, 6
  started at 0.31 s and 2 waited 13.5 s for a free slot).
- **1-4 chats: the same speed as v3.** Single chat code/prose/structured 60.2 / 39.2 / 66.0 tok/s (v3: 59.9 / 39.2 /
  67.5). C4 99.7 tok/s total, 26.8 per chat on this boot. Correction to v3: our bench gives each run its own prompt
  nonces, and the v3 row of 110.2 was a warm repeat. With the v3 boot's exact prompts, cold, the two boots are level
  (96.1 on v3.1, 95.9 on v3).
- **The v3.1 measured row** — ONE boot, 2026-11-21, on our four Sparks with exactly the `.env.example` settings.
  RigMark is the median of 3 invocations; the clocks ran 2171-2190 MHz (under the 2250 clean-clock bar, no throttle
  flags); smoke 14/14, quality panel 12/12, agent replay 24/24 turns with 20/20 warm reuses (warm TTFT p50 6.52 s,
  p90 10.05 s; v3: 6.58 / 12.3 s); prefill 8K 1,554.7 tok/s (v3: 1,454.7). Attic-off rows are NOT measured at
  CONC 8 on bit280: with `ATTIC=0` the dial falls back to the TUNE CAP (776,704) and says so.
- **Less free memory is the trade.** 5.4-5.7 GiB stays free a box under load (v3: 11.6-12.1). If your boxes run other
  work, keep `CONC=6` (the v3 row is still in `conc.tsv`).
- Version bumped to 3.1 in `kindling.json`.

## What is new in v3

- **bit280 on the v0.7 mul1 weights, rebased on stock gr8 ca7e874.** `VARIANT=bit280` is KindlingAI's own width
  manifest from release v0.7 (`manifests/exlr8-manifest-bit280.json` in their release; this recipe ships the same
  bytes, sha256 `748cdc59...`) — about 2.80 routed bits per weight. **Their profile, not ours.** The release pin
  moves to `kindlingai/glm-5.3-exlr8-k2-k3-k4@9e25c28a2e8808d8b2599d780521fd6af24e7558` (release v0.7, the mul1
  weights); the stock image pin moves to
  `ghcr.io/kindlingai/gr8:sha-ca7e874@sha256:d140aca32886d2055b7ff11d88c8860c6bb9c108c626f8f3a4f3cebdfe5fcfc6`
  (gr8 ca7e874; the busy guard of v2.1 is in it). The default lane runs the attic build of that image
  (`gr8:ca7e874-attic`, gr8 ca7e874 + the attic client `6e7df66b`); the attic client is still NOT in any published
  gr8 image — build it and tag it, as v2 said.
- **Six chats at once at the same 776,704-token pool** (`SESS=6`; the concurrency dial gains `6`): the v2 default
  was 4 at the same pool, attic on in both. About 3 GB more free memory a box: boot serving
  13.30 / 13.26 / 13.46 / 13.38 GiB across the four boxes (was 9.68-10.47 on the bit275 lane before it).
- **The v3 measured row** — ONE boot, 2026-11-19, on our four Sparks with exactly the `.env.example` settings.
  RigMark single chat code/prose/structured
  **59.9 / 39.2 / 67.5 tok/s** (was 59.3 / 37.7 / 66.6, the v2 bit275 CONC 4 row), C4 aggregate **110.2 tok/s,
  28.4 per chat** (was 95.5); C8 **103.7** — below C4 at SESS 6.
  Honest rows: **one boot only** (RigMark is the median of 3 invocations on it); the clocks ran 2171-2190 MHz,
  under the 2250 clean-clock bar, with no throttle flags; prefill 8K **1,454.7 tok/s** vs 1,561.0 on the previous
  bit275 lane, **-6.8%**; agent warm TTFT p50 6.58 s, p90 **12.3 s** (was 6.9 s); smoke
  14/14, quality panel 12/12, agent replay 24/24 turns with 20/20 warm reuses
  on that boot. Attic-off rows and other SESS values are NOT measured on bit280.
- **KL, KindlingAI's numbers, not ours**: their v0.7 card gives bit280 a full-vocabulary KL of 0.086 mean /
  0.0125 median on model-written text (wikitext-2 0.121 / 0.0175).
- **The SSD KV store is on by default** (`keep=all`, in the home volume), with `GR8_STOP_GRACE=150s`: measured
  141.8-146.4 GB/h a box writes under load on the v3 boot.
- **The busy guard is on by default** at gr8's own `BUSY_IDLE_SECS` 60 / `BUSY_RETRY_AFTER` 60 / `BUSY_QUEUE_MAX`
  8 — the measured lane's pair. The v2.1 finding stands (a client that obeys `Retry-After` at or above the idle
  bound loses its own retained run while it backs off), so `knobs.sh` prints it as a WARNING on every boot and the
  docs name `BUSY_IDLE_SECS=120 BUSY_RETRY_AFTER=20` for agent lanes whose clients obey `Retry-After`.
- Version bumped to 3 in `kindling.json`.

## What is new in v2.1

- **The busy guard is in stock gr8**: the pinned image is now `ghcr.io/kindlingai/gr8:sha-5625ed6@sha256:fdc662e2791b13e4d95ef2c6a8d8e6fd11f7f9b384c1d7d007fe76a9efc41c19`
  (gr8 PR #516, merge `5625ed6`), so `BUSY=1` works with **no custom build**. `knobs.sh` accepts the pinned
  image by digest (or any image whose own knob table carries `GR8_BUSY_GUARD`) and still refuses an image
  without the guard, before any boot.
- **Recipe defaults when `BUSY=1`**: `BUSY_IDLE_SECS` 120, `BUSY_RETRY_AFTER` 20, `BUSY_QUEUE_MAX` 8. Idle 120
  sits above a full back-to-back agent prefill (four ~29K prompts took 84 s upstream, past gr8's 60);
  retry 20 keeps the retry window well inside the idle bound; queue 8 names the bound past the free session
  slots.
- The guard was proposed by Matt Mastracci ([@mmastrac](https://x.com/mmastrac), KindlingAI) and merged by him
  into stock gr8 (PR #516) with two fixes of his: `busy_view` now matches reserve's evictions exactly
  (a split grant no longer double-counts evicted runs), and the intake check runs off the module hooks (modules
  that never retain runs — DS41, Flash — never see it). It pairs with the tiered KV store and session-keep
  design of Matt Mastracci ([@mmastrac](https://x.com/mmastrac), KindlingAI) and Chuck (@ck2084 on X; GitHub
  @chuck-ads / @adapt-ai-systems, both KindlingAI).
- Version bumped to 2.1 in `kindling.json`.

## What is new in v2

- **The busy guard, `BUSY=1`** (off by default): an incoming request that would evict a retained session's KV cache
  is refused at once with HTTP 429 + `Retry-After` instead of silently evicting it or queueing it in silence, so
  agents on the lane stop going quiet for minutes behind a re-prefill. See ["The busy guard"](#the-busy-guard-busy1).
  Needs a gr8 engine with the guard (see that section for the build until it merges upstream).
- **The settings standard** (shipped since its commit, now documented here): settings resolve in layers — exported
  environment > `scripts/local.sh` > `.env` (literal, never executed) > the `knobs.sh` defaults — with
  `./glm53 install` for a fresh set of boxes and `DRY_RUN=1` to print any plan without running it. See
  ["Settings"](#settings-the-layers-install-and-dry_run).
- **The SSD KV store is now an opt-in tier** (off by default): a stop writes open chats to the SSD and the next
  boot restores them. Its measured cost is in ["Switching"](#switching-and-the-ssd-kv-store-tier-opt-in); turn it
  on by uncommenting two lines in `.env.example`.
- Version bumped to 2 in `kindling.json`.

## Measured (v2): the `home` baseline (2026-11-07)

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
already in `EXTRA_ENV` is kept after the tier's words. The default: `VARIANT=bit280` (KindlingAI's v0.7 manifest, shipped in
`manifests/exlr8-manifest-bit280.json`) at `CONC=8` — the serving choice. `bit275` (v2) still ships.

The concurrency dial: `CONC=1|2|4|6|8` picks how many requests decode at once and takes the KV cache the freed slots
give back — `CAP` follows the largest pool a boot at that `SESS` measured holding the serving floor (the v2/v3 rows: 9 GiB free at
ready, never under 8 GiB under load; the v3.1 and v3.2 rows: never under 5 GiB under load). `./glm53 conc` prints this table for your `VARIANT`; a `CAP` you set always
wins (one above the measured value prints a warning on `./glm53 up`). Measured on bit275 (the v2 rows, release `9372b74d`; the bit280 rows are in "What is new in v3.2", "What is new in v3.1" and "What is new in v3"), SHARE_LIMIT 16384
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
| `quality` (default) | `VARIANT=bit280`, `CONC=8`; the lane defaults (attic, the SSD store, the busy guard, `SHARE_LIMIT=16384`) | The exact model's output (temp-0 identical across boots), 8 sessions at the 1,048,576-token pool. | **Measured** 2026-11-21, one boot ("What is new in v3.2") |
| `context` | `KV_FORMAT=int4`, `CAP=513536` | The int4 KV trade (gr8 docs/KV4.md: decode −2.3-3.3 %, prefill +5.8 %, temp-0 output moves marginally), a 513,536-token pool. | **Knobs set, not measured** on four Sparks |
| `agents` | quality's settings and `SHARE_LIMIT=16384` | For agents (long prompts that come back turn after turn). Every rank holds a session's first `SHARE_LIMIT` tokens and a quarter of the rest, so the same 485,376-token pool keeps four 60-70K-token agents at once (1,857 of 2,088 pages a rank) and each warm turn is a prefix hit. Exact output, as quality. The cost: a request over 16,384 tokens (prompt + max_tokens) decodes alone instead of sharing decode steps (over 32,768 at quality). | **Measured** 2026-11-09 (v2 rows, release `9372b74d`; not re-measured on v0.7): the table below |
| `agents-fast` (opt-in) | `TUNE=agents` and `GR8_REUSE_ALIGN=0` (on `EXTRA_ENV`) | A warm turn prefills only its new tokens: a prefix hit keeps the whole matched prefix instead of whole 4,096-row cells. **Not bit-exact against a cold prefill (gr8 SETTINGS.md)**: a warm turn can get other temp-0 text than the same request sent cold. `knobs.sh` prints that warning on every boot and command, and `./glm53 check-env` before the boot. | **Measured** 2026-11-09 (v2 rows, release `9372b74d`; not re-measured on v0.7): the second table below. Opt-in only, never the default |

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

## The busy guard (`BUSY=1`)

On a lane where several agents share the four boxes, one agent's big cold prefill used to evict another agent's
retained KV cache: the victim's next turn re-prefilled its whole prompt and the agent went quiet for minutes. The
busy guard (gr8's `GR8_BUSY_*` knobs, opt-in) answers that arrival instead of evicting: when granting a request
would evict a retained run whose session is not idle (no request in flight and its last response ended under
`BUSY_IDLE_SECS` ago; recipe default 120 with `BUSY=1`, gr8 upstream 60), the head refuses it at once with
HTTP 429, an OpenAI-shaped error body and `Retry-After` (`BUSY_RETRY_AFTER`, recipe default 20, gr8 upstream 60)
— the client retries after the gap. `BUSY_QUEUE_MAX` (recipe default 8) refuses arrivals once this many are
already queued past the free session slots. A turn that continues its own retained run is never refused, and the
refusal is decided at intake: a fresh arrival that would evict a live run is answered in under a second, before it
waits in the queue (a grant-time check stays as a backstop; when the queue is saturated a backstop refusal can
still wait long — see the numbers).

`BUSY_RETRY_AFTER` must stay under `BUSY_IDLE_SECS` (the recipe refuses the pair before any boot; a gr8 boot
refusal is staged upstream): a refused
probe does not refresh the session's idle clock — only admitted activity does — so a client that obeys
`Retry-After` and backed off at or above the idle bound lost its own run before the retry arrived (with both at 60
every obedient client did; the defaults 20 < 60 keep the retry window well inside the idle bound).

The rule was proposed by Matt Mastracci ([@mmastrac](https://x.com/mmastrac), KindlingAI): "evict a session
that is idle for > N s; if none are idle then 429". He merged it into stock gr8 (PR #516, `5625ed6`) with two
fixes of his: `busy_view` matches reserve's evictions exactly (a split grant no longer double-counts
evicted runs), and the intake check runs off the module hooks, so modules that never retain runs (DS41, Flash)
never see it. It pairs with the tiered KV store and session-keep design of Matt Mastracci ([@mmastrac](https://x.com/mmastrac),
KindlingAI) and Chuck (@ck2084 on X; GitHub @chuck-ads / @adapt-ai-systems, both KindlingAI).

Turn it on with `BUSY=1` (and `BUSY_IDLE_SECS` / `BUSY_RETRY_AFTER` / `BUSY_QUEUE_MAX` if you want other
values). v2.1: the pinned stock image `ghcr.io/kindlingai/gr8:sha-5625ed6@sha256:fdc662e2791b13e4d95ef2c6a8d8e6fd11f7f9b384c1d7d007fe76a9efc41c19` (gr8 PR #516, merge `5625ed6`) ships the guard, so `BUSY=1`
needs no custom build; `knobs.sh` verifies the image (its digest is known-good, or its own knob table must carry
`GR8_BUSY_GUARD`) and refuses `BUSY=1` on an image without it, before any boot. The guard stays off by default
upstream (`GR8_BUSY_GUARD=0`), so an image that merely contains it behaves exactly as before until you set
`BUSY=1`.

Measured on this rig (four DGX Sparks, GLM-5.3 bit275, 6 agents x ~130K tokens x multiple turns, `BUSY=1` vs
`BUSY=0`, same boot count), before the merge on our busy-guard build — the guard code the pinned stock image now
ships:

| row | guard off | guard on |
|---|---|---|
| warm first token, p50 / p90 (a returning turn after the guard refused an unrelated arrival) | 359 s / 423 s (the run was evicted; the turn re-prefilled ~130K tokens) | **6.9 s / 13.7 s** |
| intake-path refusals, client-measured max | n/a (no refusals) | **0.449 s** (samples 0.087-0.449 s) |
| live evictions (a retained run lost while its session was inside the idle window) | the eviction is the behaviour | **0**; follow-up turns hit the pool 50/50 |
| quality panel / boot smoke | 12/12 | 12/12 |

The grant-path backstop is honest about its limit: with 10 x 130K-token agents against a ~413K-row pool the head
sat saturated for ~7 minutes and backstop refusals carried waits up to 416 s. That is the queue-capacity behaviour
of the backstop, reported separately from the intake path, which stayed sub-second throughout.

## Knobs

| knob | values | default |
|---|---|---|
| `PEERS` | the four boxes' 10G LAN addresses, comma-separated, head first, the same list on every box; the head serves port 8100 | none: required unless `MENTAT=1` |
| `IPS`, `IPS2` | each box's ConnectX address on PCIe root 1 and root 2, in `PEERS` order | none (recommended on a switch) |
| `SHAPE` | `ring`: four boxes cabled in a ring without a switch; list `PEERS` in cable order, leave out `IPS`/`IPS2` | unset (a switch) |
| `TP` | 4 | `4` |
| `TUNE` | `quality`, `context`, `agents`, `agents-fast` (opt-in, not bit-exact) | `quality` |
| `VARIANT` | `bit280` (v3 default) or `bit275` (v2), both shipped in `manifests/`, or the release's width manifests: `home` (measured), `bit325`, `bit338`, `up1`, `bit225`, `bit243`, `bit260`, `down1`, or a path to a custom exlr8-v2-manifest JSON | `bit280` (`home` for `context`/`agents`) |
| `SESS` | requests decoding at once, 1-8 | set by `CONC` (8) |
| `CONC` | `1`, `2`, `4`, `6`, `8`: the concurrency dial. Sets `SESS` and lets `CAP` follow the largest CAP a boot at that SESS measured holding the serving floor (the `conc.tsv` header: 9 GiB free at ready and never under 8 GiB under load for the older rows, never under 5 GiB under load for the v3.1 row) — fewer slots, more KV cache per session (`./glm53 conc` prints the measured table for your `VARIANT`, split by the `attic` column). A `CAP` you set keeps your value; one above the measured value warns (it is not refused). A pair with no measured row falls back to `SESS=CONC` and the `TUNE`'s `CAP`, with a stderr line | `4` |
| `ATTIC` | `1`: boot with the memory-reserve layer ([spark-attic](https://github.com/bertholomus/spark-attic)) lending each rank its display-carveout slice (`compose.attic.yaml` is added to the compose files, and the `CONC` rows with `attic on` apply). Needs `GR8_IMAGE` to name an image **with** the attic client — the pinned `ghcr.io/kindlingai/gr8:sha-e231adb` has none and `ATTIC=1` is refused with the fix named. The gr8 attic client is not in a published gr8 image yet: `ATTIC=1` needs a gr8 build that includes it | `0` |
| `BUSY` | `1`: the busy guard. When granting a request would evict a retained run whose session is not idle (no request in flight and its last response ended under `BUSY_IDLE_SECS` ago), the head refuses it at once with HTTP 429, an OpenAI-shaped error body and `Retry-After` (`BUSY_RETRY_AFTER`) — instead of evicting the run (that agent then sits out a full re-prefill, minutes of silence) or queueing the request in silence. `BUSY_QUEUE_MAX` refuses arrivals once this many are already queued past the free session slots. A turn that continues its own retained run is never refused. v2.1: the pinned stock image ships the guard (gr8 PR #516, merge `5625ed6`); `knobs.sh` verifies the image by digest or its knob table and refuses `BUSY=1` on an image without it | `0` |
| `BUSY_IDLE_SECS` | `BUSY=1`: a session counts as idle when it has no request in flight and its last response ended at least this many seconds ago; only idle sessions' retained runs are evicted. Tune it from your agents' tool-call gaps | recipe 60 (gr8 60); `120` for agent lanes whose clients obey `Retry-After` |
| `BUSY_RETRY_AFTER` | `BUSY=1`: the seconds in a refused request's `Retry-After` header and error body. Keep it under `BUSY_IDLE_SECS` for clients that obey `Retry-After` (v3 defaults to the measured lane's 60/60 and prints a WARNING on every boot): a refused probe does not refresh the session's idle clock, so a client that obeys `Retry-After` and backs off at or above the idle bound loses its own run before the retry arrives. For such agent lanes set `BUSY_IDLE_SECS=120 BUSY_RETRY_AFTER=20` | recipe 60 (gr8 upstream 60); `20` with `BUSY_IDLE_SECS=120` |
| `BUSY_QUEUE_MAX` | `BUSY=1`: a request arriving while this many requests are already queued past the free session slots is refused at once instead of joining the queue; 0 = no bound | recipe 8 (gr8 8) |
| `CAP` | the KV pool in tokens, shared by the sessions, a multiple of 64 | by `TUNE` (485376; 513536 with int4 KV) |
| `SHARE_LIMIT` | requests up to this many tokens (prompt + max_tokens) share decode steps; every rank holds a session's first `SHARE_LIMIT` tokens and a share of the rest. A multiple of 64 from 4096 | by `TUNE` (gr8's 32768; 16384 with `TUNE=agents` and `agents-fast`) |
| `KV_STORE` | `ssd:<dir>,size=200G,persist=on,keep=sessions`: at an orderly stop the engine writes open chats to the SSD; the next boot restores their KV. An **opt-in tier** in v2 | off by default; uncomment the two lines in `.env.example` (see ["Switching"](#switching-and-the-ssd-kv-store-tier-opt-in)) |
| `GR8_STOP_GRACE` | docker's stop grace, read by `compose.yaml` | `150s` — set it when the SSD KV store tier is on, or docker kills the engine mid-store |
| `MENTAT` | `0`: the boxes in `PEERS`. `1`: find the boxes through the host's `mentat` daemon and register the API in group `GROUP` | `0` |
| `GR8_IMAGE` | the pinned image, read by `compose.yaml` | `ghcr.io/kindlingai/gr8:v1.1.1@sha256:fa5c9f66...` (`.env.example` sets `gr8:a3f44a0-attic`, your attic build) |
| `MODEL`, `DRAFTER` | the release and the drafter, each pinned to a Hugging Face commit | the commits measured above (`./fetch --print` prints them) |
| `EXTRA_ENV` | engine settings, `NAME=value` pairs separated by spaces | `GR8_GEN_CACHE=/var/lib/gr8/cache/gen-cache` |

**UPDATE 2 (Kindling, 2026-11-07, verified on this rig): `GR8_*` engine knobs reach the engine only through
`EXTRA_ENV`.** A plain `GR8_FOO=...` line in `.env` is dropped by the launcher (`-e GR8_MOE_TOPK=6` never appeared in
`engine.env`; `-e EXTRA_ENV=GR8_MOE_TOPK=6` did). Append new `GR8_*` knobs to the one `EXTRA_ENV` line,
space-separated, never replacing what is there. Short launcher names (`SESS`, `CAP`, `KV_FORMAT`, `DFLASH_K`, ...)
stay plain `.env` lines.

## Settings: the layers, install and DRY_RUN

Settings resolve in layers, later never beats earlier:

1. **The exported environment** — `TUNE=agents CONC=4 ./glm53 up` wins over everything below, even over an export of
   the same name inside `scripts/local.sh`.
2. **`scripts/local.sh`** — trusted Bash, sourced; computed settings belong here. Gitignored; copy
   `scripts/local.sh.example` to start.
3. **`.env`** — read as literal `KEY=value` lines, **never executed** (a `$(...)` line is stored as text). Compose
   also passes it into the container, where the gr8 launcher reads it.
4. **The defaults** in `knobs.sh` (and `conc.tsv` for the dial), each documented in the table above.

Every knob in the table above can be set in any layer. The shipped `.env.example` turns nothing optional on:
`BUSY=0` and `ATTIC=0` are the defaults, and the SSD KV store tier ships commented (off). `check-env`,
`check-config` and `./glm53 conc` keep reading `.env` directly: their contract is what `.env` says.

**Install** — one command for a fresh set of four boxes, run from the recipe folder on the head:

```
./glm53 install          # this box, then the other three over ssh (INSTALL_PEER_DIR, INSTALL_SSH_USER)
./glm53 install --this-box   # only this box
DRY_RUN=1 ./glm53 install    # print the per-box plan, run nothing
```

It checks docker on the box, writes `.env` from `.env.example` only when `.env` is missing (never overwrites a file
you have), runs `check-env`, pulls the pinned `GR8_IMAGE` when the image is absent (a locally built image is named,
not pulled — build or copy it first), and checks the weights cache and the `MODEL`/`DRAFTER` pins (`./fetch
--check`).

**DRY_RUN** — `DRY_RUN=1 ./glm53 up` (and `install`) prints the whole plan — the layered settings, the exact compose
command, the per-box steps — and changes nothing.

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

The API is OpenAI-compatible on the head's port 8100, model name `glm-5.3`. To stop and start again (with the SSD
KV store tier on, a stop keeps open chats across the stop; `GR8_STOP_GRACE=150s` gives the store time to write):

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

## Switching and the SSD KV store tier (opt-in)

gr8's [SWITCHING.md](https://github.com/kindlingai/gr8/blob/main/docs/SWITCHING.md) fast-switching settings are

```
KV_STORE=ssd:/var/lib/gr8/cache/kv,size=200G,persist=on,keep=sessions
GR8_STOP_GRACE=150s
```

At the stop each rank stores its open chats on the SSD (45-194 ms per rank measured in gr8's SWITCHING.md,
2026-11-07), and the next boot reads the store's index back, so a chat's next turn restores its KV instead of a
prefill. The store and the gen cache live in the cache volume (`/var/lib/gr8/cache/kv`,
`/var/lib/gr8/cache/gen-cache`). This recipe needs no separate `kv-store.yaml`: the SSD store is one `KV_STORE`
line (gr8's inline form). The 2-box Flash recipe's `kv-store.yaml` file is the Flash prompt-cache form
(`FLASH_CACHE=aligned`), which the full GLM-5.3 recipe does not use.

**The tier is off by default in v2** (the two lines ship commented in `.env.example`; uncomment both). What it
costs and buys, measured on this rig with `keep=all` on gr8 `a555ee2`:

- Writes: **about 150 GB/h a box** during the stop drains — real SSD wear and a longer stop.
- Buy: **30/30 follow-up turns warm** (a chat's next turn after the stop restored its KV instead of re-prefilling).

Credit where the store comes from: the tiered KV store and its tier design are by Matt Mastracci ([@mmastrac](https://x.com/mmastrac)) (kindlingai/gr8
#32, #36, #37, #40, #131, #239, #349). The persist=on SSD store and the session keep it runs on are by Chuck ([@ck2084](https://x.com/ck2084), KindlingAI; GitHub [chuck-ads](https://github.com/chuck-ads) / [adapt-ai-systems](https://github.com/adapt-ai-systems))
(kindlingai/gr8 #397 (persist=on + keep=sessions with the quit drain), #417, #145, #118).

Honest base note: those two measured numbers ran `keep=all` on gr8 `a555ee2`. The newer store work by Chuck ([@ck2084](https://x.com/ck2084)) is **not**
in that base — #484 (keep=sessions writes only new page blocks and preallocates the SSD reserve), #498, #500 and
#501 came after it — so the write rate on a current gr8 build should be lower, but it is **not measured** on this
rig and we do not claim it. On gr8 `a555ee2`, `keep=sessions` (the line above) wrote less than `keep=all` but
restored fewer follow-up turns (a chat whose turn-1 run was evicted is not covered); `keep=all` covers every
evicted run.

## Credits

- **Matt Mastracci** ([@mmastrac](https://x.com/mmastrac), KindlingAI; GitHub [mmastrac](https://github.com/mmastrac)) — the tiered KV store and its tier design
  (kindlingai/gr8 #32, #36, #37, #40, #131, #239, #349), and the busy-guard rule this recipe's `BUSY=1` builds on
  ("evict a session that is idle for > N s; if none are idle then 429").
- **Chuck** ([@ck2084](https://x.com/ck2084), KindlingAI; GitHub [chuck-ads](https://github.com/chuck-ads) /
  [adapt-ai-systems](https://github.com/adapt-ai-systems)) — the persist=on SSD KV store and the session keep it runs on (kindlingai/gr8 #397, #417, #145, #118).

## CI

`.github/workflows/ci.yml` runs a **no-GPU smoke** on every push: shell syntax of every script, `.env.example`
parses as `KEY=value` lines, `knobs.sh` dispatches all four `TUNE` names (and `agents-fast` prints its warning) (and refuses a bad one and a wrong
`PEERS` count), `./fetch --print` prints the pinned `MODEL` and `DRAFTER` commits, and `./glm53`'s checks run against
a stand-in docker (`tests/fake-docker`) and a show-config fixture in gr8's real format. Checks: `tests/ci-smoke.sh`.

## What is not measured yet

- `TUNE=context` on this rig: the int4 knobs come from gr8's KV4.md trade, not from our rows.
- The SSD KV store tier's write rate on a current gr8 build: our measured numbers ran `keep=all` on gr8
  `a555ee2` (see ["Switching"](#switching-and-the-ssd-kv-store-tier-opt-in)); the newer store work by Chuck ([@ck2084](https://x.com/ck2084)) (#484,
  #498, #500, #501) postdates that base and is not measured on this rig.
- bit275's KL against the full-precision model: no KL card yet. bit280's KL is KindlingAI's (their v0.7 card), not ours.
- CONC 1-8 with `ATTIC=0`: memory, cache size and quality measured; C4/C8 aggregate speed not measured.
- A clean-boot switch timing GLM-5.3 ↔ another model on this recipe.
- Custom width manifests (`VARIANT=<path>`) other than the shipped bit275.

## Licence

The recipe's scripts and docs: MIT (LICENSE). `manifests/exlr8-manifest-bit280.json` is KindlingAI's own v0.7 manifest, unmodified;
`manifests/exlr8-manifest-bit275.json` is a modified KindlingAI exlr8 manifest; both are shared under CC BY 4.0 with credit to KindlingAI (see above). The model weights stay under the GLM-5.3
License; gr8 is KindlingAI's (MIT).
