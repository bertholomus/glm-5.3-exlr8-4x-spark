#!/usr/bin/env bash
# The recipe's settings layers, in precedence order: the exported environment, scripts/local.sh (trusted Bash),
# .env (read as literal KEY=value lines, never executed), then each consumer's own defaults (knobs.sh, glm53).
# Sourced by ./glm53 and knobs.sh; it runs no docker, GPU, ssh or network command.
# An exported variable always wins: even an export of the same name inside scripts/local.sh cannot beat the
# caller's environment (the exported names are snapshotted before local.sh is sourced and restored after it).
# .env is parsed, not sourced: a "$(...)" or backtick line is stored as literal text (scripts/local.sh is the
# place for computed settings). gitignored: scripts/local.sh (ship scripts/local.sh.example as the template).
[[ "${_GLM53_CONFIG_LOADED:-0}" == 1 ]] && return 0
_GLM53_CONFIG_LOADED=1
_GLM53_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ -f "$_GLM53_ROOT/scripts/local.sh" ]]; then
  declare -A _glm53_env=()
  while IFS= read -r _glm53_k; do _glm53_env[$_glm53_k]=${!_glm53_k}; done < <(compgen -e)
  # shellcheck source=/dev/null
  source "$_GLM53_ROOT/scripts/local.sh"
  for _glm53_k in "${!_glm53_env[@]}"; do export "$_glm53_k=${_glm53_env[$_glm53_k]}"; done
  unset _glm53_env
fi
if [[ -f "${GLM53_ENV_FILE:-$_GLM53_ROOT/.env}" ]]; then
  while IFS= read -r _glm53_line || [[ -n "$_glm53_line" ]]; do
    _glm53_line=${_glm53_line%$'\r'}
    [[ $_glm53_line =~ ^[[:space:]]*(#|$) ]] && continue
    _glm53_line=${_glm53_line#export }
    [[ $_glm53_line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    _glm53_k=${BASH_REMATCH[1]} _glm53_v=${BASH_REMATCH[2]}
    if [[ $_glm53_v =~ ^\"(.*)\"$ ]] || [[ $_glm53_v =~ ^\'(.*)\'$ ]]; then
      _glm53_v=${BASH_REMATCH[1]}
    else  # compose drops an unquoted value's " # comment" and trailing blanks
      _glm53_v=$(printf '%s' "$_glm53_v" | sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//')
    fi
    [[ -n "${!_glm53_k+x}" ]] || export "$_glm53_k=$_glm53_v"
  done < "${GLM53_ENV_FILE:-$_GLM53_ROOT/.env}"
fi
unset _glm53_root _glm53_k _glm53_v _glm53_line
