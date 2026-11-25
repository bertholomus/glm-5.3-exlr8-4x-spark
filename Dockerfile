# GLM-5.3 (full) on four GB10 boxes: gr8's published image, pinned by digest, with the recipe's TUNE knob (knobs.sh)
# applied before gr8's own entrypoint. No engine is compiled here: the base image carries the engine for every TP
# width and this recipe runs glm53 at TP=4 (the g6m4 engine binary), the shape the rows in README.md were measured on.
#
#   docker buildx build --platform linux/arm64 -t glm53-4x-spark .      (compose.yaml builds it the same way)
#
# v3.3 pin: gr8 v1.2.0 — ghcr.io/kindlingai/gr8:v1.2.0 (ab2eb95: the KindlingAI GLM-5.3 TP=4 work #582; the busy
# guard of PR #516 is in it), digest sha256:3de05aab8cda21fd5d6b4af89ccdba6ff5abdbd704729601fd348fa638ade9fd. The
# default lane (ATTIC=1) runs gr8:v120-attic-a1a4 instead: gr8 v1.2.0 + #612 and #613 from gr8 main + the attic
# client (not in any published gr8 image — README "What is new in v3.3").
# v2.1 (issue #1, reported by Chuck @adapt-ai-systems): knobs.sh sources conc_lookup.sh next to itself, and
# conc_lookup.sh reads conc.tsv and manifests/ next to itself — all COPYed, or the CONC dial silently dies.
ARG GR8_IMAGE=ghcr.io/kindlingai/gr8@sha256:3de05aab8cda21fd5d6b4af89ccdba6ff5abdbd704729601fd348fa638ade9fd
FROM ${GR8_IMAGE}
COPY knobs.sh entrypoint.sh conc_lookup.sh conc.tsv /opt/glm53-4x/
COPY manifests/ /opt/glm53-4x/manifests/
COPY bin/gr8 /opt/glm53-4x/bin/gr8
ENV PATH=/opt/glm53-4x/bin:$PATH
ENTRYPOINT ["/opt/glm53-4x/entrypoint.sh"]
