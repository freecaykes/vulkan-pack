#!/usr/bin/env bash
# Picks the Vulkan driver for the host, then runs llama.cpp.
#   WSL2 (/dev/dxg present)  -> Mesa dzn   (needs -v /usr/lib/wsl:/usr/lib/wsl:ro)
#   Linux (/dev/dri present) -> Mesa RADV
# Usage: entrypoint.sh [server|chat|bench|check|<any command>] [extra llama.cpp args]
# Env:   MODEL PORT HOST NGL CTX VK_DRIVER(auto|dzn|radv|cpu) LLAMA_CACHE
set -euo pipefail

MODEL="${MODEL:-Qwen/Qwen3-4B-GGUF:Q4_K_M}"
PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"
NGL="${NGL:-99}"
CTX="${CTX:-8192}"
VK_DRIVER="${VK_DRIVER:-auto}"
export LLAMA_CACHE="${LLAMA_CACHE:-/models/.cache}"
mkdir -p "$LLAMA_CACHE" 2>/dev/null || true

die() { echo "ERROR: $*" >&2; exit 1; }

DZN_ICD="$(find /opt/mesa-dzn -name 'dzn_icd*.json' 2>/dev/null | head -n1 || true)"
RADV_ICD="$(ls /usr/share/vulkan/icd.d/radeon_icd*.json 2>/dev/null | head -n1 || true)"

if [ "$VK_DRIVER" = "auto" ]; then
  if [ -e /dev/dxg ]; then VK_DRIVER=dzn
  elif [ -d /dev/dri ] && [ -n "$(ls -A /dev/dri 2>/dev/null)" ]; then VK_DRIVER=radv
  else VK_DRIVER=cpu; fi
fi

case "$VK_DRIVER" in
  dzn)
    [ -e /dev/dxg ]        || die "/dev/dxg not found. Run with --device /dev/dxg (WSL2 only)."
    [ -d /usr/lib/wsl/lib ] || die "/usr/lib/wsl not mounted. Run with -v /usr/lib/wsl:/usr/lib/wsl:ro"
    [ -n "$DZN_ICD" ]      || die "dzn driver missing from image."
    DZN_LIB="$(dirname "$(find /opt/mesa-dzn -name libvulkan_dzn.so | head -n1)")"
    export VK_ICD_FILENAMES="$DZN_ICD"
    export LD_LIBRARY_PATH="$DZN_LIB:/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ;;
  radv)
    [ -n "$RADV_ICD" ] || die "RADV ICD not found in image."
    export VK_ICD_FILENAMES="$RADV_ICD"
    ;;
  cpu)
    echo "WARNING: no GPU device found (/dev/dxg or /dev/dri). Running on CPU (NGL=0)." >&2
    unset VK_ICD_FILENAMES; NGL=0
    ;;
  *) die "Unknown VK_DRIVER '$VK_DRIVER' (use auto|dzn|radv|cpu)" ;;
esac

MODE="${1:-server}"; [ $# -gt 0 ] && shift

# Local .gguf (relative paths resolve under /models) -> -m ; otherwise Hugging Face repo[:quant] -> -hf
if [[ "$MODEL" == *.gguf ]]; then
  [[ "$MODEL" = /* ]] || MODEL="/models/$MODEL"
  [ -f "$MODEL" ] || die "Model file not found: $MODEL"
  MODEL_ARGS=(-m "$MODEL")
else
  MODEL_ARGS=(-hf "$MODEL")
fi

echo "Driver: $VK_DRIVER | Mode: $MODE | Model: $MODEL | Port: $PORT | Host: $HOST | NGL: $NGL | Ctx: $CTX" >&2

case "$MODE" in
  check)
    vulkaninfo --summary || true
    llama-server --list-devices || true ;;
  server) exec llama-server "${MODEL_ARGS[@]}" -ngl "$NGL" -c "$CTX" --host "$HOST" --port "$PORT" "$@" ;;
  chat)   exec llama-cli    "${MODEL_ARGS[@]}" -ngl "$NGL" -c "$CTX" -cnv "$@" ;;
  bench)  exec llama-bench  "${MODEL_ARGS[@]}" -ngl "$NGL" "$@" ;;
  *)      exec "$MODE" "$@" ;;   # e.g. `bash`, `vulkaninfo`
esac