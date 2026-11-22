# GLM-5.3 (full) on four GB10 boxes: gr8's published image, pinned by digest, with the recipe's TUNE knob (knobs.sh)
# applied before gr8's own entrypoint. No engine is compiled here: the base image carries the engine for every TP
# width and this recipe runs glm53 at TP=4 (the g6m4 engine binary), the shape the rows in README.md were measured on.
#
#   docker buildx build --platform linux/arm64 -t glm53-4x-spark .      (compose.yaml builds it the same way)
#
# v3.2.1 pin: gr8 v1.1.1 — ghcr.io/kindlingai/gr8:v1.1.1 (a3f44a0: v1.1.0 + the TP=4 prefill fix #557; the busy
# guard of PR #516 is in it), digest sha256:fa5c9f66fbfa55d162782578b3262893b782e6365a76562bcab951b54acc6d96. The
# default lane adds the attic client on top of this image (ATTIC=1; not in any published gr8 image — README).
# v2.1 (issue #1, reported by Chuck @adapt-ai-systems): knobs.sh sources conc_lookup.sh next to itself, and
# conc_lookup.sh reads conc.tsv and manifests/ next to itself — all COPYed, or the CONC dial silently dies.
ARG GR8_IMAGE=ghcr.io/kindlingai/gr8@sha256:fa5c9f66fbfa55d162782578b3262893b782e6365a76562bcab951b54acc6d96
FROM ${GR8_IMAGE}
COPY knobs.sh entrypoint.sh conc_lookup.sh conc.tsv /opt/glm53-4x/
COPY manifests/ /opt/glm53-4x/manifests/
COPY bin/gr8 /opt/glm53-4x/bin/gr8
ENV PATH=/opt/glm53-4x/bin:$PATH
ENTRYPOINT ["/opt/glm53-4x/entrypoint.sh"]
