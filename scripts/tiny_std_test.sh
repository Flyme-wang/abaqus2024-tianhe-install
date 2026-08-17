#!/bin/bash
#SBATCH -p com_u22
#SBATCH -N 1
#SBATCH --ntasks-per-node=4
#SBATCH -t 00:10:00
#SBATCH -o tiny_std_%j.out
#SBATCH -e tiny_std_%j.err
#SBATCH -J tiny_std
cd $HOME/HDD_POOL/tiny_std_test
# 本地 env：纯 ASCII + 集群 license
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
echo "=== nodes ==="
scontrol show hostname $SLURM_NODELIST
echo "=== start abaqus ==="
$HOME/bin/abaqus2024 input=tiny_std.inp job=tiny_std cpus=4 double=both scratch=/dev/shm interactive 2>&1 | tail -40
echo "=== exit: $? ==="
echo "=== ls ==="
ls -la
echo "=== tiny_std.sta ==="
cat tiny_std.sta 2>/dev/null | head -40
echo "=== tiny_std.dat tail ==="
tail -20 tiny_std.dat 2>/dev/null
echo "=== tiny_std.msg tail ==="
tail -30 tiny_std.msg 2>/dev/null
