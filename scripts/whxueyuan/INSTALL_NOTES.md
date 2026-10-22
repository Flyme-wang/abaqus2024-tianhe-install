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

## 待办/备注

- **UMAT（Fortran 用户子程序）**: `SMAUsubs/PublicInterfaces` 未随装；需要时从 `abaqus2021_install/SIMULIA/EstProducts/2021/SMAUsubs` 复制（参照天河 README §12，另需 site inc 与 libstandardU_static.a；节点 home 有 intel_parallel2025 可配 ifort）
- **GUI/CAE**: `abaqus2024 cae -mesa`（若 GLX 报错）；包装器已设 LIBGL_ALWAYS_INDIRECT=1
- **磁盘**: 介质卷(~12GB)+tar.gz(11GB) 确认运行稳定后可删；保留介质便于后续按哈希补装
- **日常使用**: 建议在 ~/.bashrc 加 `alias abaqus2024="/data3/sunxinyao/bin/abaqus2024"`（未替你改 .bashrc）
