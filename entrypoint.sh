#!/bin/bash
# The recipe's knobs (knobs.sh), then gr8's own entrypoint (gr8/docker/entrypoint.sh). The base image is gr8's
# published image, pinned by digest (Dockerfile); this wrapper only applies the recipe's TUNE knob first.
set -euo pipefail
. /opt/glm53-4x/knobs.sh
exec /opt/gr8/docker/entrypoint.sh "$@"
