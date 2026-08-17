---
name: tianhe-aba
description: Submit and monitor Abaqus 2024 jobs on the Tianhe (天河) HPC cluster via SLURM. Use when the user asks to run/submit/execute an Abaqus .inp job on the cluster, monitor a running Abaqus job, check license availability on the cluster, or upload/download model files to the Tianhe login node. Covers the com_u22 partition, the cluster FLEXnet license (27000@12.8.3.194), the abaqus2024 launcher wrapper, and the SLURM submission script that writes outputs in the inp folder.
---

# Tianhe Abaqus 2024 Job Submission (tianhe-aba)

Submit Abaqus 2024 `.inp` jobs to the Tianhe supercomputer and monitor them through completion. This skill knows the exact cluster layout, the legal license route, and the proven working scripts.

## Cluster facts (do not rediscover)

- **Login**: `ssh tianhe` (alias in local `~/.ssh/config`) → `121.46.19.4:6666`, user `apm_zcshen_5`, key `~/.ssh/tianhe_key`.
- **Scheduler**: SLURM (tianhexy-cn).
- **Working partition**: `com_u22` (Ubuntu 22.04, 64 cores/node, ~28 idle nodes). License `27000@12.8.3.194` IS reachable from com_u22.
- **Unusable partitions**: `com_c76` (CentOS 7, glibc 2.28 wall blocks Abaqus 2024), `com_u22_8458` (nodes DOWN/DRAIN), mars/deimos/e9/phobos (FLEXnet protocol unreachable).
- **Install root**: `~/HDD_POOL/SIMULIA/EstProducts/2024` (official Abaqus 2024).
- **Launcher wrapper**: `~/bin/abaqus2024` (sets `LD_LIBRARY_PATH=~/HDD_POOL/abaqus2024_libs`, `LIBGL_ALWAYS_INDIRECT=1`, execs the real `abaqus`).
- **Env file**: `~/abaqus_v6.env` (pure ASCII; builds `mp_host_list` from `SLURM_NODELIST`; license `abaquslm_license_file = "27000@12.8.3.194"`).
- **SSH flakiness is routine** ("banner exchange ... timed out"). Retry a few times; prefer uploading script files over long inline commands.

## Workflow: submit a job

### Step 1 — Ensure the inp is on the login node

Upload from the local machine (inp keeps its folder on the cluster):

```bash
scp model.inp tianhe:~/abaqus/abaqus2024-try/
```

### Step 2 — Submit via SLURM

Run the production script `run_abaqus2024.sh` (it `cd`s into the inp folder, writes a local `./abaqus_v6.env` with the cluster license, and runs with `interactive` so the solver stays in the foreground):

```bash
ssh tianhe "cd ~/abaqus/abaqus2024-try && sbatch run_abaqus2024.sh model.inp"
```

The script lives at `~/abaqus/abaqus2024-try/run_abaqus2024.sh` and is also bundled in `scripts/`. Key settings: `--partition=com_u22`, `--ntasks-per-node=32`, `--time=48:00:00`, outputs `slurm-%j.out`/`slurm-%j.err` in the job folder.

### Step 3 — Monitor

```bash
ssh tianhe "squeue -j <JOBID>; tail -30 ~/abaqus/abaqus2024-try/<jobname>.sta"
```

The `.sta` file shows increment progress. `.msg` shows solver messages; `.dat` the printed output. All outputs are written **in the inp folder** (`~/abaqus/abaqus2024-try/`).

### Step 4 — Collect results

```bash
scp -r tianhe:~/abaqus/abaqus2024-try/<jobname>.odb .
```

## The production submission script

`scripts/run_abaqus2024.sh` (same content as on the cluster):

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

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Abaqus could not locate the standard executable` | Standard solver was not installed by the installer | Reinstall from media: see `scripts/install_std_solver.sh` (media.db hash → CAFS zip → verify sha256) |
| Job finishes leaving only empty `.log`/`.com` | Missing `interactive` argument | Always use `interactive` so the solver runs in the foreground |
| `lmgrd is not running` / no checkout | Partition cannot reach FLEXnet | Use `com_u22`; only that partition has license access |
| `GLIBC_2.28 not found` | CentOS 7 (com_c76) | Use `com_u22` (Ubuntu 22.04) |
| `Unknown keyword (hostsCompressed)` warnings | env parsed by Abaqus; harmless | Ignore |
| SSH banner exchange timeout | Routine cluster flakiness | Retry a few times |

## Quick validation

After any change to the install (e.g. reinstalling solver files), run the tiny single-element Standard job before the real model:

```bash
ssh tianhe "mkdir -p ~/HDD_POOL/tiny_std_test"
scp scripts/tiny_std.inp scripts/tiny_std_test.sh tianhe:~/HDD_POOL/tiny_std_test/
ssh tianhe "cd ~/HDD_POOL/tiny_std_test && sbatch tiny_std_test.sh"
```

Expected: `THE ANALYSIS HAS COMPLETED SUCCESSFULLY` in `tiny_std.sta`.

## Files in this skill

- `scripts/run_abaqus2024.sh` — production SLURM submission script (32 cores, com_u22).
- `scripts/tiny_std.inp` — minimal single-element Standard verification model.
- `scripts/tiny_std_test.sh` — SLURM verification job for the tiny model.
- `scripts/install_std_solver.sh` — reinstalls the missing `standard` solver executable from install media by media.db hash.
- `scripts/abaqus2024` — the launcher wrapper deployed as `~/bin/abaqus2024`.
- `scripts/abaqus_v6.env` — the environment file template (license + SLURM hostlist).
