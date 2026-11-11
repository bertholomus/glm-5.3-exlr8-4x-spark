# For agents: boot GLM-5.3 (full) on four DGX Sparks

You are booting this recipe for someone. This file has the steps, every knob, and how to check each step. It is taken
from README.md, `knobs.sh`, `.env.example`, `compose.yaml`, the `Dockerfile` and gr8's docs. If this file and `knobs.sh`
or `compose.yaml` disagree, follow `knobs.sh` and `compose.yaml`, and tell the person. If you cannot run a check
yourself, ask the person.

## 1. Check the four boxes

On every box:

- It is a DGX Spark (GB10, 128 GB). All four are on one 200G switch (recommended), or cabled in a ring.
- Docker and the NVIDIA container toolkit are installed (both come with DGX OS): `docker info | grep -i nvidia` shows
  the `nvidia` runtime.
- About 90 GB of disk for the model cache volume (this box's rank part, ~85.6 GB at TP=4 variant `home`), plus 200 GB
  headroom for the SSD KV store and the gen cache: `df -h "$(docker info --format '{{.DockerRootDir}}')"`. Or set
  `GR8_CACHE` to a host directory on local NVMe, owned by uid 1000.
- The box can reach Hugging Face for the fetch: `curl -sI https://huggingface.co` answers.
- TCP ports 7340 and 7341 are open between the four boxes: no firewall blocks them. Check before the boot, while
  nothing listens on those ports (`nc` may not be installed; use `python3` and bash). On a peer, listen:

  ```bash
  python3 -c 'import socket; s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("", 7340)); s.listen(1); print("ACCEPTED from", s.accept()[1])'
  ```

  On the head: `timeout 5 bash -c 'exec 3<>/dev/tcp/<peer-address>/7340' && echo OPEN || echo BLOCKED`. The listener
  stops after one connection, so start it again per test. Do the same for port 7341, for each of the three peers, on
  the `PEERS` addresses and, if set, `IPS` and `IPS2`. Then once the other way. `BLOCKED` means a firewall, a wrong
  address, or no listener.
- No other model runs on the box: `docker ps` and `nvidia-smi` show none. The launcher refuses to start next to
  another g6m4 engine on the box.
- Proactive memory compaction is off: `sysctl vm.compaction_proactiveness` prints 0. If not, as root, once:

  ```bash
  echo 'vm.compaction_proactiveness = 0' > /etc/sysctl.d/90-gr8-no-proactive-compaction.conf
  sysctl -w vm.compaction_proactiveness=0
  ```

- The fabric: each box has one ConnectX address per PCIe root (`ip -br addr show` shows them; `ls /dev/infiniband`
  lists devices). You need all four boxes' 10G LAN addresses (`PEERS`, head first), their root-1 ConnectX addresses
  (`IPS`) and their root-2 addresses (`IPS2`), each list in the same order on every box. In a ring without a switch:
  each box's f0 port is cabled to the next box's f1 port; use `SHAPE=ring`, `PEERS` in that cable order, no `IPS`/`IPS2`.

## 2. Pick the settings

Set the same values on all four boxes, in `.env` (compose) or with `docker run -e`. Copy `.env.example` to `.env` and
fill in the cluster's addresses; the pins and the recipe defaults are already in it.

`TUNE` picks what to prioritize. `quality` is the default, measured (README.md, "Measured"). `agents` is quality with
`SHARE_LIMIT=16384` for agent sessions, measured 2026-11-09 (README.md, "Pick what to prioritize"). `agents-fast` adds
`GR8_REUSE_ALIGN=0`: faster warm turns, but NOT bit-exact against a cold prefill; set it only when the person asks for it
after you have told them that, never as a default. `speed` is an empty
slot for the running knob search's winner — it holds quality's settings and must not be read as faster. `context` sets
the int4 KV knobs (rows on this rig not yet measured).

| `TUNE` | the settings it sets (`knobs.sh`) | what it gives |
|---|---|---|
| `quality` (default) | `VARIANT=bit275`, `CONC=4` (SESS=4, CAP from conc.tsv), gr8's launcher defaults otherwise | the exact model's output: temp-0 replies identical across boots (gr8 checks this itself); 4 sessions; a 694,784-token pool (776,704 with `ATTIC=1`) |
| `context` | `VARIANT=home SESS=8 CAP=513536 KV_FORMAT=int4` | the int4 KV trade (gr8 docs/KV4.md), a 513,536-token pool; rows on this rig pending |
| `agents` | `VARIANT=home SESS=8 CAP=485376 SHARE_LIMIT=16384` | for agents: four 60-70K-token agents stay in the pool at once, each warm turn a prefix hit; exact output as quality; a request over 16,384 tokens (prompt + max_tokens) decodes alone. Measured 2026-11-09 |
| `agents-fast` (opt-in) | `agents` + `EXTRA_ENV` word `GR8_REUSE_ALIGN=0` | a warm turn prefills only its new tokens (warm-turn TTFT p50 3.4 s against 5.9 s); not bit-exact against a cold prefill (gr8 SETTINGS.md), and `knobs.sh` prints that warning. Measured 2026-11-09 |

Every value also carries the recipe defaults from `.env.example`:

- `KV_STORE=ssd:/var/lib/gr8/cache/kv,size=200G,persist=on,keep=sessions` and `GR8_STOP_GRACE=150s`: at an orderly
  stop each rank writes its open chats to the SSD store; the next boot reads the index back, so a chat's next turn
  restores its KV instead of a prefill. `GR8_STOP_GRACE` is read by `compose.yaml` (`stop_grace_period`); without it
  docker kills the engine mid-store. `SESS`/`CAP` notes: the pool is shared by the sessions; a request holds at most
  `CAP` less the guard rows.
- `EXTRA_ENV=GR8_GEN_CACHE=/var/lib/gr8/cache/gen-cache`: the loader's gen cache on each box's disk (first boot of an
  image writes it; about 4.8 GB a box for GLM-5.3, per gr8 docs/SWITCHING.md).

**The UPDATE 2 rule (verified on this rig, 2026-11-07): `GR8_*` engine knobs reach the engine only through
`EXTRA_ENV`.** A plain `GR8_FOO=...` line in `.env` is dropped by the launcher (`-e GR8_MOE_TOPK=6` never reached
`engine.env`; `-e EXTRA_ENV=GR8_MOE_TOPK=6` did). Append new `GR8_*` knobs to the one `EXTRA_ENV` line,
space-separated `NAME=value`, never replacing what is already there. Short launcher names (`SESS`, `CAP`, `KV_FORMAT`,
`DFLASH_K`, `SPEC_ADAPT`, `VARIANT`, ...) are plain `.env` lines. `./glm53` enforces this rule: `./glm53 check-env`
(and `./glm53 up`, which runs it first) refuses a plain `GR8_*` engine line with exit 2, and after every `up` it checks
that each knob `.env` sets, and each `EXTRA_ENV` word, shows in `gr8 glm53 show-config` with its value (exit 3 when one
does not). `./glm53 check-config` runs that check again at any time.

Every knob:

| knob | values | default |
|---|---|---|
| `PEERS` | the four boxes' 10G LAN addresses, head first, the same on every box | none: required unless `MENTAT=1` |
| `IPS`, `IPS2` | each box's ConnectX address on PCIe root 1 and root 2, in `PEERS` order | none |
| `SHAPE` | `ring`: four boxes cabled in a ring, without `IPS` and `IPS2` | unset (a switch) |
| `TP` | 4 | `4` |
| `TUNE` | `quality`, `speed`, `context`, `agents`, `agents-fast` (opt-in, not bit-exact) | `quality` |
| `VARIANT` | the release's width manifest: `home`, `bit325`, `bit338`, `up1`, `bit225`, `bit243`, `bit260`, `down1`, or a path to a custom exlr8-v2-manifest JSON | by `TUNE` (`home`) |
| `SESS` | requests decoding at once, 1-8 | by `TUNE` (8) |
| `CAP` | the KV pool in tokens, a multiple of 64 | by `TUNE` (485376; 513536 with `TUNE=context`) |
| `KV_FORMAT` | `fp8` or `int4` | by `TUNE` (unset = fp8) |
| `SHARE_LIMIT` | requests up to this many tokens (prompt + max_tokens) share decode steps; every rank holds a session's first `SHARE_LIMIT` tokens and a share of the rest | by `TUNE` (unset = gr8's 32768; 16384 with `TUNE=agents` and `agents-fast`) |
| `KV_STORE` | `ssd:<dir>,size=200G,persist=on,keep=sessions` | the recipe default |
| `GR8_STOP_GRACE` | docker's stop grace period | `150s` |
| `MENTAT` | `0`: the boxes in `PEERS`. `1`: find the boxes through the host's `mentat` daemon and register the API | `0` |
| `GROUP` | the `mentat` group | `gr8-glm53-4x` |
| `GR8_IMAGE` | the pinned image, read by compose | `ghcr.io/kindlingai/gr8:sha-e231adb` |
| `GR8_CACHE`, `GR8_HOME` | compose only: host directories in place of the `cache` and `home` volumes, owned by uid 1000 | the named volumes |
| `MODEL`, `DRAFTER` | the release and drafter, pinned to Hugging Face commits (`./fetch --print` prints the pins) | the commits measured in README.md |
| `FETCH_JOBS` | files the fetch takes at once | `8` |
| `HF_TOKEN` | sent only to Hugging Face, for a gated or private repo | none |
| `EXTRA_ENV` | more engine settings, `NAME=value` pairs separated by spaces | `GR8_GEN_CACHE=/var/lib/gr8/cache/gen-cache` |

Any other gr8 launcher option works too (gr8/KNOBS.md). `DRAFTER`'s licence is CC BY-NC-ND 4.0: it forbids sharing a
converted copy, so each box downloads and converts its own rank part. Never copy a converted drafter between boxes.

## 3. Boot

1. On every box, fetch this box's part of the release and the drafter. It resumes if run again:

   ```bash
   cd glm-5.3-exlr8-4x-spark
   cp .env.example .env            # then set PEERS, IPS, IPS2 (or MENTAT=1): the same file on every box
   ./fetch                         # docker compose run --rm gr8 prepare, with the pinned MODEL and DRAFTER
   ./fetch --check                 # exits 0 when .env carries exactly the pinned commits
   ```

2. On every box, check `.env` (exit 0 when gr8 will read it as written). Optional, on the head: print the settings
   the boot will use and compare the `VARIANT`, `SESS`, `CAP`, `KV_STORE` and `EXTRA_ENV` lines with the tables above.

   ```bash
   ./glm53 check-env
   docker compose run --rm gr8 gr8 glm53 show-config --tp 4
   ```

3. Start the container on all four boxes within 10 minutes of each other (the boxes wait for each other for 600 s).
   `./glm53 up` is `docker compose up -d` plus three checks: `.env` first, then 120 s of watching the container for a
   restart (it stops a restart loop and prints the engine's error), then every set knob against `show-config`. It
   takes about 2 minutes a box, so start the four in parallel, one terminal per box:

   ```bash
   ./glm53 up                      # pulls the pinned image; ./glm53 up --build builds the thin recipe image
   docker compose logs -f          # ready when the supervisor prints that the cluster serves
   ```

4. To change `TUNE` or any other knob later: `./glm53 down` on any box (stops every box), edit `.env` on every box,
   then `./glm53 up` on all four. The boxes refuse to join unless they all have the same options.

## 4. Check that it serves

- On the head, `docker compose logs -f` prints that the cluster serves; expect a couple of minutes (our measured
  boots went ready 101.9-104.9 s after `up -d`, 2026-11-07, warm model cache).
- On every box, `./glm53 health` exits 0 when that box serves; `docker compose ps` shows the container `healthy` once
  this check passes (on the head it also needs the API's `/health`).
- `./glm53 status` shows every box's state, engine and free memory.
- On the head, `./glm53 smoke` checks the API; it exits 0 when every case passes (measured 14/14 on each of the three
  recorded boots). (`./glm53 health|status|smoke` run `gr8 glm53 <command>` in the box's container.)
- `curl -s localhost:8100/health` prints `{"ready":true,...}` on the head. Send one chat:

  ```bash
  curl -s localhost:8100/v1/chat/completions -H 'Content-Type: application/json' -d '{
    "model": "glm-5.3",
    "messages": [{"role": "user", "content": "Write a haiku about a small computer."}],
    "max_tokens": 4096
  }'
  ```

- Bench (the image has no `ssh`, so `--hosts` must be `""`; measured invocation shape, 2026-11-07):

  ```bash
  docker compose exec -T gr8 /opt/gr8/gr8 glm53 bench --hosts "" --json /tmp/gr8bench.json
  ```

- A resumed chat (one that lived through a stop with the SSD KV store): its next turn restores KV instead of
  prefilling. Check the store after a stop: the cache volume holds `/var/lib/gr8/cache/kv`.
- To stop: `./glm53 down` on any box (every container exits 0 and stays down), or `docker compose down` per box.
  `./glm53 down` is safe to repeat: a box that is already down exits 0. To boot again, `./glm53 up` on all four
  (`restart` does not work from inside the container).

## 5. When a step fails

| what you see | what to do |
|---|---|
| `PEERS=...: want the four boxes' LAN addresses, head first, the same on every box (or MENTAT=1)` | set `PEERS` to four addresses, the same list on every box, or `MENTAT=1` |
| `TUNE=...: want quality ..., speed ... or context ...` | use one of the three values |
| a box never joins | start all four within 600 s; check that `PEERS` and every other knob are the same on every box, head first, and that ports 7340 and 7341 are open |
| `fetch: .env sets MODEL=..., but this recipe pins ...` | `.env` moves off the measured commit: change the pin in `fetch` and `.env` together, and re-measure before publishing numbers |
| `./glm53 check-env` or `./glm53 up` exits 2: `GR8_FOO=...: gr8 engine variables on their own line never reach the engine` | the UPDATE 2 rule: `GR8_*` knobs ride `EXTRA_ENV` only. Append `GR8_FOO=...` to the one `EXTRA_ENV` line, then `./glm53 up` again |
| exit 2: `NAME is set twice` | keep one line for it (the last one wins, so a second `EXTRA_ENV` line silently replaces the first); put every engine variable on the one `EXTRA_ENV` line |
| `./glm53 up` or `./glm53 check-config` exits 3: `MISSING: NAME=value` | the boot is not running what `.env` says (a misspelled name, a value gr8 rewrote, an `EXTRA_ENV` word it dropped). Fix `.env`, `./glm53 down`, `./glm53 up` |
| `./glm53 up` exits 4: the container restarted within 120 s | it is stopped already, and the engine's error from `out/supervisor.log` is printed above (2026-11-08 on this rig: `GR8_MOE_TOPK is a Flash-model option`). Remove or fix that option, `./glm53 down` on every box, then `./glm53 up` on all four. `./glm53 error` prints the error again |
| `gr8 glm53 down` fails: `container ... is restarting, wait until the container is running` | a refused option left the container restart-looping: `./glm53 down` on each box stops the loop and prints the engine's error |
| docker kills the engine during a stop, the next boot loses chats | `GR8_STOP_GRACE=150s` is missing: `.env` must set it with `KV_STORE=ssd:...,persist=on,keep=sessions` (compose reads it for `stop_grace_period`) |
| the image does not pull | build the thin recipe image on the box: `./glm53 up --build` (it is gr8's pinned image plus `knobs.sh`) |
| a rank failed | every box's container exits non-zero and restarts, and the boxes boot again together; read the failing box's `./glm53 error` and `docker compose logs`, and, while it runs, `./glm53 logs supervisor` |

The container's exit status is the launcher's: 0 after a stop, 1 when a rank failed, 2 for bad options, 4 when the
boxes' handshake refused the boot. `./glm53`'s own exit codes: 0 ok, 2 a `.env` gr8 would misread, 3 a set knob that
did not reach gr8, 4 the container restarted within the watch, 1 anything else. The logs live in the home volume: `out/supervisor.log`, `g6m4.r0.err`, `shim.log`,
`front.log`.

If a step fails for a reason not listed here, ask on the KindlingAI Discord (the link is at the top of gr8's README).

## 6. Not measured yet: tell the person

- `TUNE=context`'s int4 knobs come from gr8's docs/KV4.md trade, not from rows measured on this rig.
- A switch timing GLM-5.3 ↔ another model with this recipe's SSD KV settings is scheduled, not yet measured here.
- The measured rows in README.md are three boots of `TUNE=quality`, and for `TUNE=agents` and `agents-fast` the boots their tables name, on
  one rig (four DGX Sparks, 200G switch), on the image and commits pinned above; other hardware has not measured this
  recipe.
