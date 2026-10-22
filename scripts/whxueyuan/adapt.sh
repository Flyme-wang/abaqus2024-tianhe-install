#!/bin/bash
# wh-xueyuan (rosefinch) Abaqus 2024 安装后脚本适配
# 天河路径($HOME/HDD_POOL) -> 本机路径(/data3/sunxinyao/abaqus2024install)
set -e
R=/data3/sunxinyao/abaqus2024install

# 1) CRLF 清理（Windows 上传的文件）
sed -i 's/\r$//' install_std_solver.sh check_std_missing.sh tiny_std.inp

# 2) install_std_solver.sh 路径适配
sed -i \
  -e 's|ABQ=$HOME/HDD_POOL/SIMULIA/EstProducts/2024|ABQ=/data3/sunxinyao/abaqus2024install/SIMULIA/EstProducts/2024|' \
  -e 's|MEDIA=$HOME/HDD_POOL/abaqus2024_linux|MEDIA=/data3/sunxinyao/abaqus2024install|' \
  -e 's|TMP=$HOME/HDD_POOL/std_install_tmp|TMP=/data3/sunxinyao/abaqus2024install/std_install_tmp|' \
  -e 's|$HOME/HDD_POOL/abaqus2024_libs|/data3/sunxinyao/abaqus2024install/abaqus2024_libs|' \
  install_std_solver.sh

# 3) check_std_missing.sh 路径适配（含 python heredoc 内路径）
sed -i \
  -e 's|ABQ=$HOME/HDD_POOL/SIMULIA/EstProducts/2024|ABQ=/data3/sunxinyao/abaqus2024install/SIMULIA/EstProducts/2024|' \
  -e 's|TMP=$HOME/HDD_POOL/std_install_tmp|TMP=/data3/sunxinyao/abaqus2024install/std_install_tmp|' \
  -e "s|abq = os.environ\['HOME'\] + '/HDD_POOL/SIMULIA/EstProducts/2024'|abq = '/data3/sunxinyao/abaqus2024install/SIMULIA/EstProducts/2024'|" \
  check_std_missing.sh

# 4) 启动包装器 ~/bin/abaqus2024
#    注意：本节点（2024 安装布局）launcher 不在 EstProducts/2024 根下，
#    而在 SIMULIA/var/dassaultsystemes/simulia/commands/abaqus（→SMALauncher 符号链接）
mkdir -p /data3/sunxinyao/bin
cat > /data3/sunxinyao/bin/abaqus2024 <<'WRAPEOF'
#!/bin/bash
# ============================================================
#  Abaqus 2024 启动包装器（wh-xueyuan / rosefinch-login03）
#  - 注入缺失系统库目录 abaqus2024_libs
#  - LIBGL_ALWAYS_INDIRECT=1 解决 X11 转发下 GLX visuals 问题
# ============================================================
export LD_LIBRARY_PATH=/data3/sunxinyao/abaqus2024install/abaqus2024_libs:$LD_LIBRARY_PATH
export LIBGL_ALWAYS_INDIRECT=1
exec /data3/sunxinyao/abaqus2024install/SIMULIA/var/dassaultsystemes/simulia/commands/abaqus "$@"
WRAPEOF
chmod +x /data3/sunxinyao/bin/abaqus2024

# 5) home 环境文件（许可证：本地 Windows FlexNet 经反向隧道）
if [ ! -f /data3/sunxinyao/abaqus_v6.env ]; then
cat > /data3/sunxinyao/abaqus_v6.env <<'ENVEOF'
# Abaqus 2024 environment - wh-xueyuan (rosefinch)
# 许可证：本地 Windows FlexNet 经 SSH 反向隧道（127.0.0.1:27800）
abaquslm_license_file = "27800@127.0.0.1"
ENVEOF
else
  echo "NOTE: ~/abaqus_v6.env 已存在，未覆盖："
  cat /data3/sunxinyao/abaqus_v6.env
fi

# 6) tiny_std 验证目录
mkdir -p $R/tiny_std_test
cp -f tiny_std.inp $R/tiny_std_test/tiny_std.inp 2>/dev/null || true

echo "===== 适配结果 ====="
grep -nE '^ABQ=|^MEDIA=|^TMP=' install_std_solver.sh
grep -n 'abaqus2024_libs' install_std_solver.sh | head -2
grep -nE '^ABQ=|^TMP=|^DB=' check_std_missing.sh
grep -n 'abq =' check_std_missing.sh | head -2
ls -la /data3/sunxinyao/bin/abaqus2024 $R/tiny_std_test/
cat /data3/sunxinyao/abaqus_v6.env
echo ADAPT_OK
