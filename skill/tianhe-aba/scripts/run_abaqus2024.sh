#!/bin/bash
# ============================================================
#  Abaqus 2024 SLURM 提交脚本（模仿门户 2017 脚本模式）
#  用法: sbatch run_abaqus2024.sh [input.inp]
#  特点: 在 inp 目录运行、输出就地保存、32 核、自动生成 env
# ============================================================
#SBATCH --job-name=abaqus2024
#SBATCH --partition=mars
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
