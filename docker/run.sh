#!/usr/bin/env bash
# Wrapper using plain `docker build` / `docker run` (no docker compose needed).
# Detects WSL2 vs native Linux and applies the right GPU flags.
#
# Usage: ./docker-run.sh [options] [build|pull|server|chat|bench|check] [-- extra llama.cpp args]
#   -m, --model  MODEL      HF repo[:quant] or .gguf filename under the models dir (default Qwen/Qwen3-4B-GGUF:Q4_K_M)
#   -p, --port   PORT       server port                 (default 8080)
#   -H, --host   HOST       bind address                (default 0.0.0.0)
#   -n, --ngl    N          GPU layers                  (default 99)
#   -c, --ctx    N          context size                (default 8192)
#   -M, --models-dir DIR    host models/cache folder    (default ~/models)
#   -i, --image  NAME       image name/tag              (default llama-vulkan:latest; use a registry path to share)
#       --platform wsl|linux   override auto-detection
#       --driver auto|dzn|radv|cpu   override driver choice inside the container
#       --dry-run           print the docker command instead of running it
#   -h, --help
#   build = build the image; pull = pull IMAGE from a registry; check = print Vulkan devices.
# Build args via env: MESA_REF, LLVM_VER, LLAMA_REF
set -euo pipefail
cd "$(dirname "$0")"

MODEL="${MODEL:-Qwen/Qwen3-4B-GGUF:Q4_K_M}"
PORT="${PORT:-8080}"
BIND_HOST="${LLAMA_HOST:-0.0.0.0}"
NGL="${NGL:-99}"
CTX="${CTX:-8192}"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
IMAGE="${IMAGE:-llama-vulkan:latest}"
VK_DRIVER="${VK_DRIVER:-auto}"
PLATFORM=""; MODE="server"; EXTRA=(); DRY=0

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model) MODEL="$2"; shift 2 ;;
    -p|--port)  PORT="$2"; shift 2 ;;
    -H|--host)  BIND_HOST="$2"; shift 2 ;;
    -n|--ngl)   NGL="$2"; shift 2 ;;
    -c|--ctx)   CTX="$2"; shift 2 ;;
    -M|--models-dir) MODELS_DIR="$2"; shift 2 ;;
    -i|--image) IMAGE="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --driver)   VK_DRIVER="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    -h|--help)  usage 0 ;;
    build|pull|server|chat|bench|check) MODE="$1"; shift ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then printf '%q ' "$@"; echo; else "$@"; fi; }

if [ -z "$PLATFORM" ]; then
  if   [ -e /dev/dxg ]; then PLATFORM=wsl
  elif [ -d /dev/dri ]; then PLATFORM=linux
  else echo "No /dev/dxg (WSL2) or /dev/dri (Linux GPU) found. Use --platform wsl|linux to force."; exit 1; fi
fi
echo "Platform: $PLATFORM | Image: $IMAGE" >&2

build_image() {
  run docker build -f Dockerfile -t "$IMAGE" \
    --build-arg "MESA_REF=${MESA_REF:-}" \
    --build-arg "LLVM_VER=${LLVM_VER:-}" \
    --build-arg "LLAMA_REF=${LLAMA_REF:-master}" \
    ..
}

case "$MODE" in
  build) build_image; exit 0 ;;
  pull)  run docker pull "$IMAGE"; exit 0 ;;
esac

# Make sure the image exists: local -> pull -> build
if [ "$DRY" = 0 ] && ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker pull "$IMAGE" 2>/dev/null || build_image
fi

mkdir -p "$MODELS_DIR"

GPU_ARGS=()
if [ "$PLATFORM" = "wsl" ]; then
  GPU_ARGS=(--device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro)
else
  VIDEO_GID="$(getent group video  | cut -d: -f3 || true)"; : "${VIDEO_GID:=44}"
  RENDER_GID="$(getent group render | cut -d: -f3 || true)"; : "${RENDER_GID:=109}"
  GPU_ARGS=(--device /dev/dri --group-add "$VIDEO_GID" --group-add "$RENDER_GID")
fi

TTY=(-i); [ -t 0 ] && TTY=(-it)

run docker run --rm "${TTY[@]}" \
  "${GPU_ARGS[@]}" \
  -p "$PORT:$PORT" \
  -v "$MODELS_DIR:/models" \
  -e MODEL="$MODEL" -e PORT="$PORT" -e HOST="$BIND_HOST" \
  -e NGL="$NGL" -e CTX="$CTX" -e VK_DRIVER="$VK_DRIVER" \
  "$IMAGE" "$MODE" ${EXTRA[@]+"${EXTRA[@]}"}