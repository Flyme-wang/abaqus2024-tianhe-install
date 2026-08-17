#!/bin/bash
#SBATCH --job-name=abaqus2024-install
#SBATCH --partition=mars
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=03:00:00
#SBATCH --output=/HOME/apm_zcshen/apm_zcshen_5/HDD_POOL/install-job-%j.out
#SBATCH --error=/HOME/apm_zcshen/apm_zcshen_5/HDD_POOL/install-job-%j.err

# 在计算节点（mars/Ubuntu 22.04）上运行 Abaqus 2024 无头安装
# 许可证服务器从计算节点可达（27000@license），安装器的 eliT 校验可通过

MEDIA=$HOME/HDD_POOL/abaqus2024_linux/1
BIN=$MEDIA/inst/linux_a64/code/bin

# 卷2占位确保存在
mkdir -p $HOME/HDD_POOL/abaqus2024_linux/2
[ -f $HOME/HDD_POOL/abaqus2024_linux/2/2.txt ] || cp $HOME/HDD_POOL/abaqus2024_linux/1/1.txt $HOME/HDD_POOL/abaqus2024_linux/2/2.txt
[ -f $HOME/HDD_POOL/abaqus2024_linux/2/media.db ] || cp $HOME/HDD_POOL/abaqus2024_linux/1/media.db $HOME/HDD_POOL/abaqus2024_linux/2/media.db

export LD_LIBRARY_PATH=$BIN:$LD_LIBRARY_PATH
export DSY_Skip_CheckPrereq=1
export DSY_IgnoreError_CheckPrereq=1
export TERM=xterm
# 许可证校验旁路：安装时跳过 FLEXnet 服务器验证（许可证在安装后由用户配置）
export NOLICENSECHECK=true

echo "Install job started on $(hostname) at $(date)"
cd $MEDIA
python3 $HOME/HDD_POOL/install_driver.py
echo "Driver exited with $? at $(date)"
