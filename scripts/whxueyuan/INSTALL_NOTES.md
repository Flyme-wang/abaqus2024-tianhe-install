# Abaqus 2024 安装记录（wh-xueyuan / rosefinch-login03）

日期: 2026-10-22
流程: 参照 github.com/Flyme-wang/abaqus2024-tianhe-install（天河流程）适配本节点

## 布局

- 安装根: `/data3/sunxinyao/abaqus2024install`
  - 介质卷 1/3/4/5/6（解压自 DS.SIMULIA.SUITE.2024.LINX64.tar.gz；卷2为占位: 2.txt+media.db 复制自卷1）
  - `SIMULIA/EstProducts/2024`: 主安装 (~12GB, explicit 求解器随装)
  - `SIMULIA/var/dassaultsystemes/simulia/commands/{abaqus,abq2024}`: 启动器符号链接 → SMALauncher
- 启动包装器: `~/bin/abaqus2024`（注入 abaqus2024_libs[当前为空] + LIBGL_ALWAYS_INDIRECT=1）
- 环境文件: `~/abaqus_v6.env` → `abaquslm_license_file = "27800@127.0.0.1"`
- 适配脚本: `adapt.sh` / `install_driver.py` / `install_std_solver.sh` / `check_std_missing.sh`（均在安装根目录）

## 与天河流程的关键差异

1. **Ubuntu 20.04 无缺系统库**（天河 22.04 缺 libjpeg.so.62 等 8 个旧库）→ `abaqus2024_libs` 留空
2. **无 SLURM** → 登录节点直接跑 TUI 安装与验证作业
3. **许可证**: 本地 Windows FlexNet（lmgrd:27800 + ABAQUSLM vendor:65260）经 ssh 反向隧道：
   `ssh -R 27800:127.0.0.1:27800 -R 65260:127.0.0.1:65260 wh-xueyuan`（须双端口都映射）
4. **CAA API 组件不需要**: 主装完成后 CAA 子安装器卡在目录校验死循环（Default [/usr/SIMULIA/...] 不可写）→ kill CAA 子安装器进程（4187042/4187049）；主安装器随之报 `Cannot wait for process` + `Input error` 循环 → 一并 kill（所需产物已全部落盘：EstProducts 12GB + commands 启动器 + CATEnv 注册）
5. **Standard 求解器照旧缺 6 个文件** → `install_std_solver.sh` 按 media.db 哈希从卷6 CAFS zip 补装（哈希与天河 README §9.6 完全相同），sha256 全部校验通过

## 验证（2026-10-22 16:27）

tiny_std 单元素作业（tiny_std_test/）：Abaqus/Standard 2024，license checked out 5 tokens from 127.0.0.1（9994/9999 remain），`THE ANALYSIS HAS COMPLETED SUCCESSFULLY` ✓

## UMAT（Fortran 用户子程序）补齐（2026-10-23）

主装 + Standard 补装后 **UMAT 仍不可用**（`abaqus make library=*.f` 报 ifort 找不到 + ABA_PARAM.INC 打不开；media.db 亦无 SMAUsubs 条目）。
`fix_umat.sh` 从 abaqus2021_install 复制三组件补齐（2021 与 2024 接口兼容，天河 README §12 同法）：

| 组件 | 来源（2021）→ 目标（2024） |
|---|---|
| SMAUsubs 全树（含 PublicInterfaces 26 文件） | `abaqus2021_install/SIMULIA/EstProducts/2021/SMAUsubs` → `$ABQ/SMAUsubs` |
| 静态链接库 | `.../2021/code/lib/libstandardU_static.a`（951402 B）→ `$ABQ/linux_a64/code/lib/` |
| site 参数头文件（.inc/.h/.blk） | `.../2021/SMA/site/` → `$ABQ/linux_a64/SMA/site/`（aba_param.inc 等） |

编译器：**ifort classic 2021.13.1 仅存在于 oneAPI `compiler/2024.2/bin`**（latest=2025.2 已无 ifort classic，须定向 2024.2）。
包装器 `~/bin/abaqus2024` 采用 **PATH 注入**。

**两个关键坑**：

1. 勿在包装器内 `source .../compiler/2024.2/env/vars.sh`：该脚本 L215-224 含
   `while [ $# -gt 0 ]; case "$1" in ... shift` 位置参数解析，被 source 时会吃掉包装器的 `$@`
   → SMALauncher 收到零参数，报 `Command line option "job" must have a value`。
   只 `export PATH=/data3/sunxinyao/intel/oneapi/compiler/2024.2/bin:$PATH` 即可
   （make 编译与 user=*.f 运行时编译均验证通过，无需 LD_LIBRARY_PATH）。
2. **2024 的 `user=` 必须传 Fortran 源码**（`user=umat_test.f`，运行时编译）；
   传编译好的 `libstandardU.so` 会报 "could not be located: libstandardU.so.f, .for, ..."。

验证（2026-10-23，登录节点直跑，无 SLURM）：

- `~/bin/abaqus2024 make library=umat_test.f` → `Abaqus JOB umat_test.f COMPLETED`，libstandardU.so 390808 B
- 单元素 e2e（`fortran_test/umat_e2e.inp`，`user=umat_test.f`）→ `Abaqus JOB umat_e2e COMPLETED`，
  `THE ANALYSIS HAS COMPLETED SUCCESSFULLY`，`0 ERROR MESSAGES` ✓

## 待办/备注

- **UMAT**: 已补齐并验证（见上节）；日常用法 `~/bin/abaqus2024 make library=xxx.f`、作业 `user=xxx.f`
- **GUI/CAE**: `abaqus2024 cae -mesa`（若 GLX 报错）；包装器已设 LIBGL_ALWAYS_INDIRECT=1
- **磁盘**: 介质卷(~12GB)+tar.gz(11GB) 确认运行稳定后可删；保留介质便于后续按哈希补装
- **日常使用**: 建议在 ~/.bashrc 加 `alias abaqus2024="/data3/sunxinyao/bin/abaqus2024"`（未替你改 .bashrc）
