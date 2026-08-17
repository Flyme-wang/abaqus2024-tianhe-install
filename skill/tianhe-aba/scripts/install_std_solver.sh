#!/bin/bash
# 按 media.db 哈希从 CAFS zip 补装缺失的 Abaqus/Standard 文件
set -u
ABQ=$HOME/HDD_POOL/SIMULIA/EstProducts/2024
MEDIA=$HOME/HDD_POOL/abaqus2024_linux
TMP=$HOME/HDD_POOL/std_install_tmp
mkdir -p $TMP

# dest|hash 列表
FILES="
linux_a64/code/bin/standard|bf613d09bd68a8c28ac3f80e0fd1c0a9b8d8c6ef65c60484b330d7429a031336
linux_a64/code/bin/libABQSMAStaCore.so|2d462468d1b0cd859ec47773b59ebe061175b33d209f64357d0025d56ae145b6
linux_a64/code/bin/libSMAStaCodeGen.so|47567b112bcc414a4aed9a6e0c7f25b86084f83c86f23936534e60133231d66a
linux_a64/code/bin/stddss|b197122b197e97cecdf65954773d4b0b94dd47ea3fa365b15ef347fad30e9511
linux_a64/code/bin/stdtransens|d1024047026cf037de3a0009aa0cdd265e934fe2d9d042caa1e955c6585d21c7
linux_a64/code/bin/transhtpgd|167d792359e54c30f35ff973a38535bb0bb12a5810ffc38f838629e228047f98
"

# 先建 hash -> zip 索引（只列一次）
echo "===== 建立 CAFS zip 索引 ====="
ALLZIPS=$(find $MEDIA -iname '*.zip' 2>/dev/null)
echo "zips: $(echo "$ALLZIPS" | wc -l)"

extract_one() {
  local dest="$1" hash="$2"
  local target="$ABQ/$dest"
  if [ -f "$target" ]; then echo "ALREADY: $dest"; return; fi
  local zip=""
  for z in $ALLZIPS; do
    if unzip -l "$z" 2>/dev/null | grep -q " $hash"; then zip="$z"; break; fi
  done
  if [ -z "$zip" ]; then echo "NOZIP for $dest ($hash)"; return 1; fi
  echo "EXTRACT: $dest  <-  $zip"
  unzip -p "$zip" "$hash" > "$TMP/$hash.bin" || { echo "unzip FAILED for $dest"; return 1; }
  local actual=$(sha256sum "$TMP/$hash.bin" | awk '{print $1}')
  if [ "$actual" != "$hash" ]; then echo "HASH MISMATCH for $dest: $actual"; return 1; fi
  mkdir -p "$(dirname "$target")"
  cp "$TMP/$hash.bin" "$target"
  chmod 755 "$target"
  echo "OK: $dest ($(stat -c%s "$target") bytes)"
}

echo "$FILES" | while IFS='|' read -r dest hash; do
  [ -z "$dest" ] && continue
  extract_one "$dest" "$hash"
done

echo ""
echo "===== 校验：code/bin 下 standard 相关文件 ====="
ls -la $ABQ/linux_a64/code/bin/standard $ABQ/linux_a64/code/bin/stddss $ABQ/linux_a64/code/bin/stdtransens $ABQ/linux_a64/code/bin/transhtpgd $ABQ/linux_a64/code/bin/libABQSMAStaCore.so $ABQ/linux_a64/code/bin/libSMAStaCodeGen.so 2>&1

echo ""
echo "===== ldd standard ====="
LD_LIBRARY_PATH=$HOME/HDD_POOL/abaqus2024_libs ldd $ABQ/linux_a64/code/bin/standard 2>&1 | head -40
