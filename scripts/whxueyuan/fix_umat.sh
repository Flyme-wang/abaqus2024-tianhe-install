#!/bin/bash
# ============================================================
#  wh-xueyuan Abaqus 2024 UMAT（Fortran 用户子程序）支持补齐
#  参照天河流程 README §12，三组件从本机 abaqus2021_install 复制：
#    1) SMAUsubs/PublicInterfaces（26 个接口文件，整树 ~115K）
#    2) libstandardU_static.a → linux_a64/code/lib（2024 介质 media.db 无此文件）
#    3) 参数 inc 双路径覆盖 → linux_a64/SMA/site（兼容两种 include 解析路径）
#  编译器：Intel oneAPI 2024.2 的 ifort classic 2021.13（PATH-only 注入）
#  ⚠️ 勿在包装器内 source intel env/vars.sh：其 while/shift 参数解析
#     （约 L215-224）会吃掉包装器 $@，SMALauncher 收零参数报
#     "Command line option job must have a value"
#  ⚠️ oneapi latest=2025.2 已无 ifort classic，须定向 compiler/2024.2/bin
#  验证：make library=umat_test.f COMPLETED；umat_e2e 端到端 COMPLETED
# ============================================================
set -e
ABQ=/data3/sunxinyao/abaqus2024install/SIMULIA/EstProducts/2024
A21=/data3/sunxinyao/abaqus2021_install/SIMULIA/EstProducts/2021

echo "===== 1) 复制 SMAUsubs 整树 ====="
[ -d $ABQ/SMAUsubs ] || cp -r $A21/SMAUsubs $ABQ/SMAUsubs
echo "PublicInterfaces 文件数: $(ls $ABQ/SMAUsubs/PublicInterfaces | wc -l)"

echo "===== 2) libstandardU_static.a -> linux_a64/code/lib ====="
mkdir -p $ABQ/linux_a64/code/lib
[ -f $ABQ/linux_a64/code/lib/libstandardU_static.a ] || \
    cp $A21/linux_a64/code/lib/libstandardU_static.a $ABQ/linux_a64/code/lib/
ls -la $ABQ/linux_a64/code/lib/libstandardU_static.a

echo "===== 3) 参数 inc 复制到 SMA/site（双路径覆盖） ====="
for f in $A21/SMAUsubs/PublicInterfaces/*.inc \
         $A21/SMAUsubs/PublicInterfaces/*.h \
         $A21/SMAUsubs/PublicInterfaces/*.blk; do
    [ -f "$f" ] && cp -f "$f" $ABQ/linux_a64/SMA/site/
done
echo "SMA/site 参数文件: $(ls $ABQ/linux_a64/SMA/site/ | grep -cE 'param|for_c|\.blk')"

echo "===== 4) 安装启动包装器（PATH 注入 ifort） ====="
cat > /data3/sunxinyao/bin/abaqus2024 <<'WRAPEOF'
#!/bin/bash
# ============================================================
#  Abaqus 2024 启动包装器（wh-xueyuan / rosefinch-login03，含 UMAT 支持）
#  - LIBGL_ALWAYS_INDIRECT=1 解决 X11 转发下 GLX visuals 问题
#  - PATH 注入 ifort classic 2021.13（Intel oneAPI 2024.2）
#    ⚠️ 勿 source .../compiler/2024.2/env/vars.sh：该脚本含 shift 参数
#       解析（约 L215-224），在包装器内 source 会吃掉 $@，SMALauncher
#       收到零参数报 "Command line option job must have a value"
#    ⚠️ oneapi latest=2025.2 已无 ifort classic，须定向 2024.2/bin
#  - make 编译与 user=*.f 运行时编译均只需 PATH（LD_LIBRARY_PATH 勿注入）
# ============================================================
export LIBGL_ALWAYS_INDIRECT=1
export PATH=/data3/sunxinyao/intel/oneapi/compiler/2024.2/bin:$PATH
exec /data3/sunxinyao/abaqus2024install/SIMULIA/var/dassaultsystemes/simulia/commands/abaqus "$@"
WRAPEOF
chmod +x /data3/sunxinyao/bin/abaqus2024
echo "wrapper installed"

echo "===== 5) ifort 核验（定向 2024.2） ====="
/data3/sunxinyao/intel/oneapi/compiler/2024.2/bin/ifort --version 2>&1 | \
    grep -i "ifort (IFORT)" || echo "WARN: ifort 版本行未匹配"

echo "FIX_UMAT_OK"
