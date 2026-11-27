# syntax=docker/dockerfile:1
# One image for WSL2 (Mesa dzn -> D3D12) and native Linux (Mesa RADV) AMD GPUs.
# Build context is the wsl-vulkan/ folder (see docker-compose.yml).
ARG DEBIAN=trixie

############################ Stage 1: Mesa dzn ############################
FROM debian:${DEBIAN} AS mesa-dzn
ARG MESA_REF=""
ARG LLVM_VER=""
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends sudo ca-certificates git && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY 01b-build-mesa-dzn.sh .
# Reuses the same build script as the bare-metal setup
# (the sed drops the /dev/dxg check even if an older copy of the script is in the build context)
RUN sed -i '/\/dev\/dxg missing/d' 01b-build-mesa-dzn.sh \
     && chmod +x 01b-build-mesa-dzn.sh \
     && SKIP_GPU_CHECK=1 MESA_PREFIX=/opt/mesa-dzn LLVM_VER="${LLVM_VER}" \
     ./01b-build-mesa-dzn.sh ${MESA_REF:+--ref ${MESA_REF}} \
     && rm -rf /root/mesa-dzn-src
# Record which Debian packages dzn needs at runtime so the final image installs exactly those
RUN so="$(find /opt/mesa-dzn -name libvulkan_dzn.so | head -n1)" \
     && ldd "$so" | awk '/=> \//{print $3}' | xargs -r readlink -f | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | tr ',' '\n' | tr -d ' ' | sort -u \
     > /opt/mesa-dzn/runtime-pkgs.txt || true

############################ Stage 2: llama.cpp ###########################
FROM debian:${DEBIAN} AS llama
ARG LLAMA_REF=master
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
     build-essential cmake ninja-build git ca-certificates pkg-config \
     libvulkan-dev glslc spirv-headers libcurl4-openssl-dev libssl-dev \
     && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${LLAMA_REF}" https://github.com/ggml-org/llama.cpp /src
WORKDIR /src
# GGML_NATIVE=OFF: don't tune for the build machine's CPU, so the image runs on any x86_64 host
RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
     -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=OFF \
     -DLLAMA_CURL=ON -DLLAMA_OPENSSL=ON \
     -DLLAMA_BUILD_TESTS=OFF \
     && cmake --build build -j"$(nproc)" --target llama-server llama-cli llama-bench
# The MCP proxy needs OpenSSL to reach https:// MCP servers
RUN ldd build/bin/llama-server | grep -qi libssl || echo 'WARNING: llama-server not linked to OpenSSL (MCP proxy cannot use https)'
RUN mkdir -p /opt/llama/bin \
     && cp build/bin/llama-server build/bin/llama-cli build/bin/llama-bench /opt/llama/bin/ \
     && ldd /opt/llama/bin/llama-server | awk '/=> \//{print $3}' | xargs -r readlink -f | xargs -r dpkg -S 2>/dev/null | cut -d: -f1 | tr ',' '\n' | tr -d ' ' | sort -u \
     > /opt/llama/runtime-pkgs.txt || true

############################ Stage 3: runtime #############################
FROM debian:${DEBIAN}-slim AS runtime
ENV DEBIAN_FRONTEND=noninteractive
COPY --from=mesa-dzn /opt/mesa-dzn /opt/mesa-dzn
COPY --from=llama /opt/llama /opt/llama
RUN apt-get update \
     && apt-get install -y --no-install-recommends \
     ca-certificates libvulkan1 libgomp1 mesa-vulkan-drivers vulkan-tools \
     $(cat /opt/mesa-dzn/runtime-pkgs.txt /opt/llama/runtime-pkgs.txt | sort -u | tr '\n' ' ') \
     && rm -rf /var/lib/apt/lists/*
RUN ln -s /opt/llama/bin/* /usr/local/bin/
RUN missing="$(for b in llama-server llama-cli llama-bench; do ldd /opt/llama/bin/$b | grep 'not found' || true; done)"; \
     if [ -n "$missing" ]; then printf 'Missing runtime libraries:\n%s\n' "$missing"; exit 1; fi
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
VOLUME /models
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["server"]
