#!/usr/bin/env bash
set -uo pipefail
[ -f /etc/profile.d/wsl-vulkan.sh ] && source /etc/profile.d/wsl-vulkan.sh

echo "== /dev/dxg =="; ls -l /dev/dxg || { echo "missing"; exit 1; }
echo; echo "== WSL GPU libs =="; ls /usr/lib/wsl/lib 2>/dev/null | grep -E 'libd3d12|libdxcore' || echo "not found"
echo; echo "== VK_ICD_FILENAMES =="; echo "${VK_ICD_FILENAMES:-<unset>}"

echo; echo "== vulkaninfo --summary =="
OUT="$(vulkaninfo --summary 2>&1)"; echo "$OUT"

echo
if echo "$OUT" | grep -qiE 'Direct3D12|AMD|Radeon'; then
  echo "OK: GPU Vulkan device detected."
elif echo "$OUT" | grep -qi llvmpipe; then
  echo "FAIL: only llvmpipe (CPU) found. Re-check steps 00 and 01."; exit 1
else
  echo "FAIL: no usable Vulkan device."; exit 1
fi

