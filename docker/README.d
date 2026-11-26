# Docker: one image for WSL2 and native Linux (AMD, Vulkan)

Host prerequisites (NOT in the image):
- WSL2: AMD Adrenalin driver + `wsl --update` (run `../00-windows-prep.ps1`), Docker running inside WSL
- Linux: working amdgpu kernel driver (/dev/dri), Docker

## Building image:

```
    docker build -f docker/Dockerfile -t llama-vulkan:latest .
```

/dev/dxg and /dev/dri are the two ways a Linux system reaches a GPU. Which one you have depends on whether Linux is talking to real hardware or to a virtualized GPU.

## Run on WSL2:
```
    docker run --rm -it --device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro \
        -p 8080:8080 -v ~/models:/models \
        -e MODEL=Qwen/Qwen3-4B-GGUF:Q4_K_M -e PORT=8080 \
        llama-vulkan:latest server
```

## Run natively on Linux:
```
    docker run --rm -it --device /dev/dri --group-add video --group-add render \
        -p 8080:8080 -v ~/models:/models \
        -e MODEL=Qwen/Qwen3-4B-GGUF:Q4_K_M -e PORT=8080 \
        llama-vulkan:latest server
```

Models/cache live in ~/models (override with --models-dir), so they persist across runs.

Build args: MESA_REF, LLVM_VER, LLAMA_REF (env vars read by docker-compose.yml).