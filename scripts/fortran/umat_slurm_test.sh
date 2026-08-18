#!/bin/bash
# UMAT 端到端测试 v3：修正的弹性 UMAT（SLURM）
#SBATCH -p com_u22
#SBATCH -N 1
#SBATCH --ntasks-per-node=8
#SBATCH -t 00:20:00
#SBATCH -o umat_slurm_%j.out
#SBATCH -e umat_slurm_%j.err
#SBATCH -J umat_test
cd $HOME/HDD_POOL/fortran_test
echo "=== 节点: $(hostname) ==="
source /APP/u22/x86/intel/oneapi2024.2/setvars.sh >/dev/null 2>&1

echo "=== 1) 清理并编译 UMAT ==="
rm -f libstandardU.so *.o umat_e2e.sta umat_e2e.dat umat_e2e.msg
$HOME/bin/abaqus2024 make library=umat_test.f 2>&1 | tail -3
ls -la libstandardU.so 2>/dev/null

cat > ./abaqus_v6.env <<'EOF'
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

echo "=== 2) 运行 UMAT 作业 ==="
$HOME/bin/abaqus2024 input=umat_e2e.inp job=umat_e2e user=umat_test.f \
    cpus=8 mp_mode=threads scratch=/dev/shm interactive 2>&1 | tail -8
echo "JOB_RC=$?"

echo "=== 3) 结果 ==="
cat umat_e2e.sta 2>/dev/null | tail -10
echo "--- dat ---"
grep -iE "COMPLETED|ERROR|TERMINATED" umat_e2e.dat 2>/dev/null | tail -3
echo "DONE"
