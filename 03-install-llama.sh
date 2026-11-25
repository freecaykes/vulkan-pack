#!/usr/bin/env bash
set -euo pipefail
[ -f /etc/profile.d/wsl-vulkan.sh ] && source /etc/profile.d/wsl-vulkan.sh

sudo apt-get install -y build-essential cmake git ninja-build pkg-config \
  libvulkan-dev glslc spirv-headers libcurl4-openssl-dev

DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only; else git clone https://github.com/ggml-org/llama.cpp "$DIR"; fi

cd "$DIR"
cmake -B build -G Ninja -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"

echo "Built: $DIR/build/bin/llama-server"
