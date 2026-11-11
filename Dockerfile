# GLM-5.3 (full) on four GB10 boxes: gr8's published image, pinned by digest, with the recipe's TUNE knob (knobs.sh)
# applied before gr8's own entrypoint. No engine is compiled here: the base image carries the engine for every TP
# width and this recipe runs glm53 at TP=4 (the g6m4 engine binary), the shape the rows in README.md were measured on.
#
#   docker buildx build --platform linux/arm64 -t glm53-4x-spark .      (compose.yaml builds it the same way)
#
# The pin is the image the measured rows come from: ghcr.io/kindlingai/gr8:sha-e231adb, digest
# sha256:d920e26b3105f9f56f7766121394da1e37fb93d82e2176e20f8c1c2e64f4f174 (measured 2026-11-07).
ARG GR8_IMAGE=ghcr.io/kindlingai/gr8@sha256:d920e26b3105f9f56f7766121394da1e37fb93d82e2176e20f8c1c2e64f4f174
FROM ${GR8_IMAGE}
COPY knobs.sh entrypoint.sh /opt/glm53-4x/
COPY bin/gr8 /opt/glm53-4x/bin/gr8
ENV PATH=/opt/glm53-4x/bin:$PATH
ENTRYPOINT ["/opt/glm53-4x/entrypoint.sh"]
