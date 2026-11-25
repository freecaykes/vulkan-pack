#!/usr/bin/env bash
# One-shot: setup -> verify -> build (-> optionally run). Run inside WSL after 00-windows-prep.ps1.
#
# Usage: ./run-all.sh [options]
#   -m, --model  MODEL   HF repo[:quant] or path to .gguf   (default: Qwen/Qwen3-4B-GGUF:Q4_K_M)
#   -p, --port   PORT    server port                        (default: 8080)
#   -H, --host   HOST    server bind address                (default: 0.0.0.0)
#   -n, --ngl    N       GPU layers                         (default: 99)
#   -c, --ctx    N       context size                       (default: 8192)
#   -d, --dir    PATH    llama.cpp checkout                 (default: ~/llama.cpp)
#   -r, --run    MODE    after building, run: server | chat | bench
#       --build-mesa     build dzn from source if the distro's Mesa lacks it (runs 01b)
#       --mesa-ref TAG   Mesa tag to build (default: latest stable)
#       --skip-setup     skip steps 01/02 (Vulkan already working)
#       --skip-build     skip step 03 (llama.cpp already built)
#   -h, --help
# Env vars MODEL, PORT, HOST, NGL, CTX, LLAMA_DIR also work; flags override them.
set -euo pipefail
cd "$(dirname "$0")"
 
export MODEL="${MODEL:-Qwen/Qwen3-4B-GGUF:Q4_K_M}"
export PORT="${PORT:-8080}"
export HOST="${HOST:-0.0.0.0}"
export NGL="${NGL:-99}"
export CTX="${CTX:-8192}"
export LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
RUN_MODE=""; SKIP_SETUP=0; SKIP_BUILD=0
 
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
 
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model) MODEL="$2"; shift 2 ;;
    -p|--port)  PORT="$2";  shift 2 ;;
    -H|--host)  HOST="$2";  shift 2 ;;
    -n|--ngl)   NGL="$2";   shift 2 ;;
    -c|--ctx)   CTX="$2";   shift 2 ;;
    -d|--dir)   LLAMA_DIR="$2"; shift 2 ;;
    -r|--run)   RUN_MODE="$2"; shift 2 ;;
    --build-mesa) export BUILD_MESA=1; shift ;;
    --mesa-ref) export MESA_REF="$2"; shift 2 ;;
    --skip-setup) SKIP_SETUP=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help)  usage 0 ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done
export MODEL PORT HOST NGL CTX LLAMA_DIR
 
if [ "$SKIP_SETUP" -eq 0 ]; then
  ./01-vulkan-setup.sh
  source /etc/profile.d/wsl-vulkan.sh
  ./02-verify-vulkan.sh
fi
[ "$SKIP_BUILD" -eq 0 ] && ./03-install-llama.sh
 
CMD="./04-run-model.sh --model \"$MODEL\" --port $PORT --host $HOST --ngl $NGL --ctx $CTX --dir \"$LLAMA_DIR\""
if [ -n "$RUN_MODE" ]; then
  eval exec "$CMD" "$RUN_MODE"
else
  echo; echo "All set. Start with:"; echo "  $CMD server"
fi
