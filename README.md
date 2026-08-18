# Abaqus 2024 在天河超算上的安装与 SLURM 作业教程

> 天河超算（Tianhe）登录节点 `121.46.19.4:6666`，用户 `apm_zcshen_5`，SLURM 调度器。
> 本教程完整记录 Abaqus 2024（官方版）从介质解压、无头安装、缺失系统库补齐、
> **Standard 求解器补装**、环境文件配置、到 SLURM 32 核提交运行的全过程。
> 所有命令均可直接复制执行。

---

## 目录

1. [总体架构](#1-总体架构)
2. [环境与前置条件](#2-环境与前置条件)
3. [安装介质准备](#3-安装介质准备)
4. [无头安装（关键：绕过许可证校验与 /tmp noexec）](#4-无头安装)
5. [缺失系统库收集](#5-缺失系统库收集)
6. [启动包装器 abaqus2024](#6-启动包装器)
7. [环境文件 abaqus_v6.env](#7-环境文件)
8. [SLURM 提交脚本](#8-slurm-提交脚本)
9. [Standard 求解器缺失的补装（重点）](#9-standard-求解器补装重点)
10. [验证：单元素测试作业](#10-验证单元素测试作业)
11. [GUI（CAE）使用方法](#11-gui-cae-使用方法)
12. [Fortran 用户子程序（UMAT）配置（重点）](#12-fortran-用户子程序umat配置重点)
13. [常见问题 FAQ](#13-常见问题-faq)
14. [文件布局速查](#14-文件布局速查)

---

## 1. 总体架构

```
用户 inp 目录
   │  sbatch run_abaqus2024.sh model.inp
   ▼
SLURM 计算节点 (com_u22, Ubuntu 22.04, 64 核/节点)
   │
   ├── ~/bin/abaqus2024            ← 启动包装器（补缺失系统库）
   │        │
   │        ▼
   │   ~/HDD_POOL/SIMULIA/EstProducts/2024/abaqus   ← 官方 2024 主程序
   │        │
   │        ▼
   │   求解器：standard / explicit（在 linux_a64/code/bin/ 下）
   │
   └── 许可证：27000@12.8.3.194（集群 FLEXnet，com_u22 可达）
```

**关键目录：**

| 路径 | 说明 |
|---|---|
| `~/HDD_POOL/abaqus2024_linux/` | 解压后的安装介质（卷 1-6） |
| `~/HDD_POOL/SIMULIA/EstProducts/2024/` | Abaqus 2024 安装目录（约 12GB） |
| `~/HDD_POOL/abaqus2024_libs/` | 补齐的缺失系统库（libjpeg.so.62 等） |
| `~/HDD_POOL/tmpinstall/` | 安装临时目录（因为 /tmp 是 noexec） |
| `~/bin/abaqus2024` | 启动包装器脚本 |
| `~/abaqus_v6.env` | 环境文件（许可证 + MPI hostlist） |
| `~/abaqus/abaqus2024-try/` | 作业目录（inp + 输出就地保存） |

---

## 2. 环境与前置条件

### 2.1 分区与操作系统

| 分区 | OS | 说明 |
|---|---|---|
| **com_u22** | Ubuntu 22.04 | ✅ **可用**：28 个空闲节点，许可证可达，MaxTime 不限 |
| com_u22_8458 | Ubuntu 22.04 | ❌ 节点全部 DOWN+DRAIN（savepower），需管理员开机 |
| com_c76 | CentOS 7 | ❌ 2024 无法运行：glibc 2.28 硬墙 |
| mars/deimos/e9/phobos | Ubuntu 22.04 | ❌ FLEXnet 协议不通（许可证无法签出） |

> **结论：只有 com_u22 能同时满足「Ubuntu 22.04 + 许可证可达」。**

### 2.2 许可证

- 集群 FLEXnet/FlexLM 服务器：`12.8.3.194:27000`（lmgrd v11.6 + ABAQUSLM v11.6）
- com_u22 节点可正常 `lmstat` 签出 `standard` / `explicit` 功能
- 许可证池 1024 tokens（32 核作业约需 21 tokens）

### 2.3 检查许可证是否可达

```bash
# 在 com_u22 分区节点上测试
srun -p com_u22 -N 1 --time=00:05:00 bash -c "lmstat -a -c 27000@12.8.3.194 | head -30"
```

---

## 3. 安装介质准备

介质卷解压到 `~/HDD_POOL/abaqus2024_linux/`（卷 1,3,4,5,6 + 卷 2 占位）：

```bash
mkdir -p ~/HDD_POOL/abaqus2024_linux/{1,2,3,4,5,6}

# 卷 2 占位（卷 2 实际内容很少，占位文件即可让安装器通过）
cp ~/HDD_POOL/abaqus2024_linux/1/1.txt ~/HDD_POOL/abaqus2024_linux/2/2.txt
cp ~/HDD_POOL/abaqus2024_linux/1/media.db ~/HDD_POOL/abaqus2024_linux/2/media.db
```

各卷解压后应有 `SIMULIA_EstablishedProducts/Linux64/<n>/...` 结构，
其中 `media.db` 是**安装文件清单数据库**（后面补装求解器要用到它）。

---

## 4. 无头安装

### 4.1 三个关键问题与对策

| 问题 | 对策 |
|---|---|
| `/tmp` 是 **noexec**，安装器报 "Cannot wait for process" | `TMPDIR=~/HDD_POOL/tmpinstall` |
| 安装时 eliT 许可证校验失败 | `NOLICENSECHECK=true` 旁路（许可证安装后由 env 配置） |
| TUI 交互式安装无法手动操作 | 用 `install_driver.py` 自动应答驱动 |

### 4.2 安装作业脚本 `install_on_mars.sh`

> 安装需要计算节点（mars/Ubuntu 22.04），通过 SLURM 提交。

```bash
#!/bin/bash
#SBATCH --job-name=abaqus2024-install
#SBATCH --partition=mars
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=03:00:00
#SBATCH --output=/HOME/apm_zcshen/apm_zcshen_5/HDD_POOL/install-job-%j.out
#SBATCH --error=/HOME/apm_zcshen/apm_zcshen_5/HDD_POOL/install-job-%j.err

MEDIA=$HOME/HDD_POOL/abaqus2024_linux/1
BIN=$MEDIA/inst/linux_a64/code/bin

mkdir -p $HOME/HDD_POOL/abaqus2024_linux/2
[ -f $HOME/HDD_POOL/abaqus2024_linux/2/2.txt ] || cp $HOME/HDD_POOL/abaqus2024_linux/1/1.txt $HOME/HDD_POOL/abaqus2024_linux/2/2.txt
[ -f $HOME/HDD_POOL/abaqus2024_linux/2/media.db ] || cp $HOME/HDD_POOL/abaqus2024_linux/1/media.db $HOME/HDD_POOL/abaqus2024_linux/2/media.db

export LD_LIBRARY_PATH=$BIN:$LD_LIBRARY_PATH
export DSY_Skip_CheckPrereq=1
export DSY_IgnoreError_CheckPrereq=1
export TERM=xterm
export NOLICENSECHECK=true

cd $MEDIA
python3 $HOME/HDD_POOL/install_driver.py
```

### 4.3 自动应答驱动 `install_driver.py`

安装器是 TUI（`StartTUI.sh`），用 pty 驱动并自动应答：

- 安装目录：`~/HDD_POOL/SIMULIA/EstProducts/2024`（默认 `/usr/simulia` 无权限，需 `!c` 清默认值后输入）
- 媒体选择：接受默认（CAA API / Isight 等按需切换）
- 通用目录：`/var/DassaultSystemes/SIMULIA/X` → 映射到 `~/HDD_POOL/SIMULIA/X`
- 组件选择：接受全部组件（**注意：安装器默认组件可能不含 Standard 求解器，见第 9 节**）
- 许可证：选 **3 = Skip licensing configuration**（跳过服务器校验）
- 完成标志：检测 "installation completed successfully" 退出

> ⚠️ **重要**：即使安装器选了全部组件，2024 的 Standard 求解器主程序
> （`linux_a64/code/bin/standard`）**可能没有被安装**。运行 Standard 作业时报
> `Abaqus could not locate the standard executable`。修复方法见第 9 节。

---

## 5. 缺失系统库收集

Ubuntu 22.04 缺少 Abaqus 2024 依赖的旧版系统库，安装后运行会报
`error while loading shared libraries: libXXX.so.N: cannot open shared object file`。

收集到 `~/HDD_POOL/abaqus2024_libs/`（从集群 /APP 的 Ansys/Altair 树或 Abaqus SMAExternal 复制）：

```bash
mkdir -p ~/HDD_POOL/abaqus2024_libs
cd ~/HDD_POOL/abaqus2024_libs

# 需要补齐的库清单
# libjpeg.so.62    libpng12.so.0    libXm.so.4    libXmu.so.6
# libXp.so.6       libGLU.so.1      libGLw.so.1   libOSMesa.so.6
```

例如从 /APP 目录查找并复制：

```bash
find /APP -name 'libjpeg.so.62*' 2>/dev/null | head -3
find /APP -name 'libXm.so.4*' 2>/dev/null | head -3
# ... 逐个找到后 cp 到 ~/HDD_POOL/abaqus2024_libs/
```

> 排查缺库的命令：
> ```bash
> export LD_LIBRARY_PATH=~/HDD_POOL/abaqus2024_libs:$LD_LIBRARY_PATH
> ldd ~/HDD_POOL/SIMULIA/EstProducts/2024/linux_a64/code/bin/standard | grep 'not found'
> ```

---

## 6. 启动包装器

`~/bin/abaqus2024`（启动前注入缺失库路径 + 解决 X11 GLX 问题）：

```bash
#!/bin/bash
# Abaqus 2024 启动包装器
# 补充缺失系统库；LIBGL_ALWAYS_INDIRECT 解决 X11 转发下的 GLX visuals 问题
export LD_LIBRARY_PATH=$HOME/HDD_POOL/abaqus2024_libs:$LD_LIBRARY_PATH
export LIBGL_ALWAYS_INDIRECT=1
exec $HOME/HDD_POOL/SIMULIA/EstProducts/2024/abaqus "$@"
```

```bash
chmod +x ~/bin/abaqus2024
```

---

## 7. 环境文件

`~/abaqus_v6.env`（**必须纯 ASCII，无 BOM，不能有 coding cookie**——Python2 兼容）：

```python
# Abaqus environment file - cluster version
# SLURM MPI hostlist + FLEXnet license (IP form)
import os, subprocess

hostsCompressed = os.getenv('SLURM_NODELIST', 'NONE')
if hostsCompressed != 'NONE':
    try:
        hostsExpanded = subprocess.check_output(
            'scontrol show hostname ' + hostsCompressed, shell=True)
        hostsList = [h for h in hostsExpanded.decode().split() if h.strip()]
        cpusPerNode = 64
        mp_host_list = [[h, cpusPerNode] for h in hostsList]
    except Exception:
        pass

abaquslm_license_file = "27000@12.8.3.194"
```

> ⚠️ 环境文件会按 Python 解析执行，Abaqus 对未知顶层变量会打印
> `Abaqus Warning: Unknown keyword (...)` —— 这是**正常现象**，不影响运行。

---

## 8. SLURM 提交脚本

`~/abaqus/abaqus2024-try/run_abaqus2024.sh`（在 inp 目录运行、输出就地保存、32 核）：

```bash
#!/bin/bash
# ============================================================
#  Abaqus 2024 SLURM 提交脚本（模仿门户 2017 脚本模式）
#  用法: sbatch run_abaqus2024.sh [input.inp]
#  特点: 在 inp 目录运行、输出就地保存、32 核、自动生成 env
# ============================================================
#SBATCH --job-name=abaqus2024
#SBATCH --partition=com_u22
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=32
#SBATCH --time=48:00:00
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err

INPUT_FILE=${1:-$(ls *.inp 2>/dev/null | head -1)}
if [ -z "$INPUT_FILE" ]; then echo "No inp file"; exit 1; fi

export JOB_WORKING_DIR=$(dirname $INPUT_FILE)
export NCORES=${SLURM_NTASKS:-32}
export JOB_NAME=$(basename $INPUT_FILE .inp)
export ABAQUS_EXECUTABLE=$HOME/bin/abaqus2024

cd "$JOB_WORKING_DIR"
echo "Workdir: $(pwd)"
echo "Job: $JOB_NAME, cores: $NCORES, input: $(basename $INPUT_FILE)"
echo "Node: $(hostname), Nodelist: $SLURM_NODELIST"

# 生成环境文件（SLURM MPI hostlist + 许可证）——模仿 abqenv2017.py
cat > ./abaqus_v6.env <<'ENVEOF'
import os, subprocess
hostsCompressed = os.getenv('SLURM_NODELIST', 'NONE')
if hostsCompressed != 'NONE':
    try:
        hostsExpanded = subprocess.check_output(
            'scontrol show hostname ' + hostsCompressed, shell=True)
        hostsList = [h for h in hostsExpanded.decode().split() if h.strip()]
        cpusPerNode = 64
        mp_host_list = [[h, cpusPerNode] for h in hostsList]
    except Exception:
        pass
abaquslm_license_file = "27000@12.8.3.194"
ENVEOF

export LD_LIBRARY_PATH=$HOME/HDD_POOL/abaqus2024_libs:$LD_LIBRARY_PATH

echo "Start: $(date)"
$ABAQUS_EXECUTABLE input=$(basename $INPUT_FILE) job=$JOB_NAME \
    cpus=$NCORES mp_mode=threads scratch=/dev/shm interactive
echo "Abaqus exit: $?"
echo "End: $(date)"
```

**提交作业：**

```bash
cd ~/abaqus/abaqus2024-try
sbatch run_abaqus2024.sh CodexTarget49_CAE_NATIVE_allcohesive_gc50x_maxinc2p5.inp

# 查看进度
squeue -j <JOBID>
tail -30 CodexTarget49_CAE_NATIVE_allcohesive_gc50x_maxinc2p5.sta
```

> ⚠️ 必须加 `interactive` 参数，否则 Abaqus 后台运行、SLURM 脚本一结束作业就被杀掉，
> 只会留下空的 `.log` 和 `.com`，没有 `.sta/.dat/.msg`。

---

## 9. Standard 求解器补装（重点）

### 9.1 症状

```
Abaqus could not locate the standard executable
```

`$ABQ/linux_a64/code/bin/` 下只有 `explicit` / `explicit_dp`，**没有 `standard`**。

### 9.2 原理

安装介质的 `media.db`（SQLite）记录每个文件的**安装路径 + SHA256 哈希**，
CAFS 介质 zip 内的文件**以哈希命名**。因此可以：

1. 在 `media.db` 查 `standard` 的哈希
2. 在全介质 zip 里按哈希定位
3. 解压后校验哈希一致再放入安装目录

### 9.3 第一步：在 media.db 查哈希

```bash
python3 - ~/HDD_POOL/SIMULIA/EstProducts/2024/InstallData/426/CODE/linux_a64/SIMULIA_EstPrd.media/media.db <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
cur = con.cursor()
for pat in ['%code/bin/standard%', '%SMAStaMain%']:
    rows = cur.execute("""SELECT fe.name, f.dest, f.hash FROM Files f
                          JOIN Features fe ON fe.featureid=f.featureid
                          WHERE f.dest LIKE ? LIMIT 30""", (pat,)).fetchall()
    print(f"--- pattern {pat} ---")
    for r in rows: print(r)
PYEOF
```

结果：

```
('CODE\\linux_a64\\SMAStaMain', 'linux_a64/code/bin/standard', 'bf613d09bd68a8c28ac3f80e0fd1c0a9b8d8c6ef65c60484b330d7429a031336')
```

### 9.4 第二步：按哈希在介质 zip 里定位

```bash
HASH=bf613d09bd68a8c28ac3f80e0fd1c0a9b8d8c6ef65c60484b330d7429a031336
for z in $(find ~/HDD_POOL/abaqus2024_linux -iname '*.zip' 2>/dev/null); do
  if unzip -l "$z" 2>/dev/null | grep -q "$HASH"; then echo "FOUND: $z"; fi
done
```

结果：

```
FOUND: ~/HDD_POOL/abaqus2024_linux/6/SIMULIA_EstablishedProducts/Linux64/2/CAFS/CODE/linux_a64/SMAStaMain.zip
```

### 9.5 第三步：检查还缺哪些 Standard 相关文件

Standard 求解器共涉及 4 个 feature（media.db 查询）：

| feature | 文件 |
|---|---|
| `SMAStaMain` | `linux_a64/code/bin/standard`（1.2MB） |
| `SMAStandard` | `libABQSMAStaCore.so`（82MB 核心）、`libSMAStaCodeGen.so`、`stddss`、`stdtransens`、`transhtpgd` |
| `SMAStsStandardSupport` | 7 个 `libABQSMASts*.so`（通常已装） |
| `SMAUStd` | `libstandardB.so`、`libstandardU.so`（通常已装） |

### 9.6 第四步：一键补装脚本 `install_std_solver.sh`

```bash
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
```

### 9.7 验证补装结果

```bash
ls -la $ABQ/linux_a64/code/bin/standard \
      $ABQ/linux_a64/code/bin/stddss \
      $ABQ/linux_a64/code/bin/stdtransens \
      $ABQ/linux_a64/code/bin/transhtpgd \
      $ABQ/linux_a64/code/bin/libABQSMAStaCore.so \
      $ABQ/linux_a64/code/bin/libSMAStaCodeGen.so
```

> `ldd standard` 输出大量 `not found` 是**正常的**——那些 ABQ 自有库都在安装目录内，
> 由启动包装器/launcher 设置的 `LD_LIBRARY_PATH` 负责加载。

---

## 10. 验证：单元素测试作业

### 10.1 测试 inp `tiny_std.inp`

```
*Heading
tiny standard solver test - single element
*Node
1, 0, 0, 0
2, 1, 0, 0
3, 1, 1, 0
4, 0, 1, 0
5, 0, 0, 1
6, 1, 0, 1
7, 1, 1, 1
8, 0, 1, 1
*Element, type=C3D8
1, 1, 2, 3, 4, 5, 6, 7, 8
*Nset, nset=ALLN, generate
1, 8, 1
*Elset, elset=ALLE, generate
1, 1, 1
*Solid Section, elset=ALLE, material=STEEL
1.,
*Material, name=STEEL
*Elastic
210000., 0.3
*Step, name=LoadStep, nlgeom=NO
*Static
1., 1., 1.e-5, 1.
*Boundary
5, 1, 3
6, 1, 3
7, 1, 3
8, 1, 3
*Cload
4, 2, -1000.
*Output, field
*Node Output
U
*End Step
```

### 10.2 测试 SLURM 脚本 `tiny_std_test.sh`

```bash
#!/bin/bash
#SBATCH -p com_u22
#SBATCH -N 1
#SBATCH --ntasks-per-node=4
#SBATCH -t 00:10:00
#SBATCH -o tiny_std_%j.out
#SBATCH -e tiny_std_%j.err
#SBATCH -J tiny_std
cd $HOME/HDD_POOL/tiny_std_test
cat > ./abaqus_v6.env <<'EOF'
# tiny standard test env
import os, subprocess
hostsCompressed = os.getenv('SLURM_NODELIST', 'NONE')
if hostsCompressed != 'NONE':
    try:
        hostsExpanded = subprocess.check_output(
            'scontrol show hostname ' + hostsCompressed, shell=True)
        hostsList = [h for h in hostsExpanded.decode().split() if h.strip()]
        cpusPerNode = 64
        mp_host_list = [[h, cpusPerNode] for h in hostsList]
    except Exception:
        pass
abaquslm_license_file = "27000@12.8.3.194"
EOF
$HOME/bin/abaqus2024 input=tiny_std.inp job=tiny_std cpus=4 double=both scratch=/dev/shm interactive
echo "=== exit: $? ==="
cat tiny_std.sta 2>/dev/null | head -40
```

### 10.3 期望输出

```
Abaqus/Standard 2024   DATE 17-Aug-2026 TIME 10:42:57
 STEP  INC ATT SEVERE EQUIL TOTAL ...
   1     1   1     0     1     1  1.00   1.00   1.000
 THE ANALYSIS HAS COMPLETED SUCCESSFULLY
```

---

## 11. GUI（CAE）使用方法

```bash
# 软件渲染模式（解决 Xmanager/Xshell 的 glXCreateContext failed / visuals 超限问题）
abaqus2024 cae -mesa
```

> 若直接 `abaqus2024 cae` 报 GLX 错误，用 `-mesa`（纯软件渲染）即可。

---

## 12. Fortran 用户子程序（UMAT）配置（重点）

> 参考集群 Abaqus 2017 的配置方式：site env 使用 `ifort` 编译用户子程序。
> Abaqus 2024 安装时**缺少用户子程序组件**（SMAUsubs/PublicInterfaces 接口文件、
> `libstandardU_static.a` 静态库），需要补装，并让 `abaqus make` 能找到 Intel ifort。

### 12.1 症状

```
Abaqus Error: Include file "aba_param.inc" required for compilation is not found.
Abaqus Error: The Abaqus user subroutine library could not be found.
```

### 12.2 三个缺失组件与补装

| 缺失项 | 正确位置 | 来源 |
|---|---|---|
| `SMAUsubs/PublicInterfaces/`（26 个接口文件） | `$ABQ/SMAUsubs/PublicInterfaces/`（**与 `linux_a64` 平级**） | 从 Abaqus 2020 复制 |
| site 参数 inc（`aba_param_dp/sp.inc`、`vaba_param*.inc` 等 9 个） | `$ABQ/linux_a64/SMA/site/` | 从 Abaqus 2017 site 复制 |
| `libstandardU_static.a`（静态库，含标准子程序符号） | `$ABQ/linux_a64/code/lib/` | 从 Abaqus 2020 复制 |

> ⚠️ make.pyc 的 include 路径是 `$ABA_HOME/../SMAUsubs/PublicInterfaces`，
> 即 `$ABQ/SMAUsubs/PublicInterfaces`（安装根，**不是** `linux_a64` 下面）。

### 12.3 编译器：Intel oneAPI 2024.2（ifort 2021.13）

集群有 Intel oneAPI 2024.2（`/APP/u22/x86/intel/oneapi2024.2`），含 ifort 2021.13.0。

### 12.4 启动包装器（make 时加载 ifort，正常运行不注入）

`~/bin/abaqus2024`（完整版，见 `scripts/fortran/abaqus2024_fortran`）：

```bash
#!/bin/bash
# ============================================================
#  Abaqus 2024 启动包装器（含 Fortran 用户子程序支持）
#  - 补充缺失系统库
#  - LIBGL_ALWAYS_INDIRECT 解决 X11 GLX visuals 问题
#  - make 子命令时加载 Intel oneAPI（ifort）+ Abaqus code/bin
#  - 正常运行不注入 LD_LIBRARY_PATH（避免干扰 Abaqus MPI 加载）
# ============================================================
export LIBGL_ALWAYS_INDIRECT=1

ABQ=$HOME/HDD_POOL/SIMULIA/EstProducts/2024
export ABA_HOME=$ABQ/linux_a64

# 判断子命令：make 需要编译器环境；其余交给 Abaqus launcher 自己处理
FIRST_ARG="${1:-}"

if [ "$FIRST_ARG" = "make" ] || [ "$FIRST_ARG" = "python" ]; then
    export LD_LIBRARY_PATH=$HOME/HDD_POOL/abaqus2024_libs:$LD_LIBRARY_PATH
    INTEL_SETVARS=/APP/u22/x86/intel/oneapi2024.2/setvars.sh
    if [ -f "$INTEL_SETVARS" ]; then
        source "$INTEL_SETVARS" >/dev/null 2>&1
    fi
    export LD_LIBRARY_PATH=$ABQ/linux_a64/code/bin:$LD_LIBRARY_PATH
    INTEL_LIBS=/APP/u22/x86/intel/oneapi2024.2/compiler/2024.2/lib
    [ -d "$INTEL_LIBS" ] && export LD_LIBRARY_PATH="$INTEL_LIBS:$LD_LIBRARY_PATH"
    export FOR_IGNORE_EXCEPTIONS=1
    export FOR_DISABLE_STACK_TRACE=1
fi

exec $ABQ/abaqus "$@"
```

### 12.5 编译 UMAT 并提交作业

```bash
# 1) 编译用户子程序（产物为 libstandardU.so）
cd ~/HDD_POOL/fortran_test
~/bin/abaqus2024 make library=umat_test.f
# 期望：Abaqus JOB umat_test.f COMPLETED

# 2) 提交作业（必须走 SLURM！登录节点 interactive 会因缺少 PMPI 初始化报
#    "libstandardU.so: failed to map segment"）
sbatch umat_slurm_test.sh
```

> ⚠️ **必须通过 SLURM 运行 UMAT 作业**。在登录节点直接 `interactive` 运行时，
> 求解器 dlopen `libstandardU.so` 时依赖的 `libmpiCC.so` 缺少 `hpmp_bor` 符号
> （Platform MPI 的 dlopen 行为），报 `failed to map segment from shared object`。
> SLURM 计算节点上 PMPI 完整初始化，无此问题。

### 12.6 测试脚本（见 `scripts/fortran/`）

- `umat_test.f` — 可用的线性弹性 UMAT（含应力更新，保证收敛）
- `umat_e2e.inp` — 调用 UMAT 的单元素测试模型（`*User Material` + `*Depvar`）
- `umat_slurm_test.sh` — SLURM 端到端测试（com_u22，8 核）

### 12.7 验证输出

```
Abaqus JOB umat_test.f COMPLETED        ← 编译链接成功
Abaqus JOB umat_e2e COMPLETED           ← 作业成功
THE ANALYSIS HAS COMPLETED SUCCESSFULLY ← 收敛
```

## 13. 常见问题 FAQ

| 症状 | 原因 | 解决 |
|---|---|---|
| `Cannot wait for process` | /tmp 是 noexec | `TMPDIR=~/HDD_POOL/tmpinstall` |
| 安装时 eliT 校验失败 | 许可证服务器校验 | `NOLICENSECHECK=true` |
| `Unknown keyword (hostsCompressed)` 警告 | env 顶层变量被 Abaqus 解析 | 正常现象，忽略 |
| `could not locate the standard executable` | Standard 求解器未安装 | 第 9 节补装 |
| 作业只留下空 `.log`/`.com` | 没加 `interactive` | 加 `interactive` 参数 |
| `error while loading shared libraries` | 缺系统库 | 第 5 节补齐 |
| `glXCreateContext failed` / `maximum number of visuals exceeded` | X11 GLX 问题 | `abaqus2024 cae -mesa` |
| GLIBC_2.28 not found | CentOS 7 上跑 2024 | 用 com_u22（Ubuntu 22.04） |
| `lmgrd is not running` | 分区到许可证服务器 FLEXnet 不通 | 用 com_u22 分区 |

---

## 14. 文件布局速查

```
~/HDD_POOL/
├── abaqus2024_linux/          # 安装介质（卷1-6，含 media.db 与 CAFS zips）
├── SIMULIA/
│   ├── EstProducts/2024/      # 安装目录
│   │   ├── abaqus             # 主 launcher
│   │   ├── SMAUsubs/PublicInterfaces/   # 用户子程序接口文件（aba_param.inc 等）
│   │   ├── linux_a64/code/bin/{standard, explicit, explicit_dp, *.so}
│   │   ├── linux_a64/code/lib/libstandardU_static.a   # 标准子程序静态库
│   │   ├── linux_a64/SMA/site/lnx86_64.env            # 编译器配置（ifort）
│   │   └── InstallData/426/CODE/linux_a64/SIMULIA_EstPrd.media/media.db
│   └── CAE/plugins/2024/      # 插件目录
├── abaqus2024_libs/           # 补齐的系统库
├── tmpinstall/                # 安装临时目录
├── license_forwarder.py       # （可选）许可证 TCP 转发器
└── install_driver.py / install_driver.log
~/bin/abaqus2024               # 启动包装器（make 时加载 ifort）
~/abaqus_v6.env                # 环境文件
~/abaqus/abaqus2024-try/       # 作业目录（run_abaqus2024.sh + inp + 输出）
~/HDD_POOL/fortran_test/       # UMAT 测试目录（umat_test.f, libstandardU.so）
```

---

## 附：关键脚本索引

| 脚本 | 作用 |
|---|---|
| `scripts/install_on_mars.sh` | 在 mars 节点跑安装（SLURM） |
| `scripts/install_driver.py` | TUI 自动应答驱动 |
| `scripts/abaqus2024` | 启动包装器 |
| `scripts/abaqus_v6.env` | 环境文件模板 |
| `scripts/run_abaqus2024.sh` | 生产作业提交脚本（com_u22, 32 核） |
| `scripts/install_std_solver.sh` | Standard 求解器补装 |
| `scripts/tiny_std.inp` | 验证用单元素模型 |
| `scripts/tiny_std_test.sh` | 验证用 SLURM 脚本 |
| `scripts/fortran/abaqus2024_fortran` | 含 Fortran 支持的启动包装器 |
| `scripts/fortran/umat_test.f` | 线性弹性 UMAT 示例 |
| `scripts/fortran/umat_e2e.inp` | 调用 UMAT 的测试模型 |
| `scripts/fortran/umat_slurm_test.sh` | UMAT 端到端测试（SLURM） |
