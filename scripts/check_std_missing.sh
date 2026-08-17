#!/bin/bash
# 从 CAFS zip 按 media.db 哈希补装缺失的 Abaqus/Standard 求解器文件
set -u
ABQ=$HOME/HDD_POOL/SIMULIA/EstProducts/2024
MEDIA=$HOME/HDD_POOL/abaqus2024_linux
DB=$ABQ/InstallData/426/CODE/linux_a64/SIMULIA_EstPrd.media/media.db
TMP=$HOME/HDD_POOL/std_install_tmp
mkdir -p $TMP

echo "===== 1) media.db: SMAStaMain / SMAStandard / SMAStsStandardSupport 全部文件 ====="
python3 - "$DB" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
cur = con.cursor()
feats = ['%SMAStaMain%', '%SMAStandard%', '%SMAStsStandardSupport%', '%SMAUStd%']
for f in feats:
    rows = cur.execute("""SELECT fe.name, f.dest, f.hash FROM Files f
                          JOIN Features fe ON fe.featureid=f.featureid
                          WHERE fe.name LIKE ?""", (f,)).fetchall()
    print(f"--- feature {f}: {len(rows)} files ---")
    for r in rows: print("   ", r)
PYEOF

echo ""
echo "===== 2) 检查目标位置缺哪些文件 ====="
python3 - "$DB" <<'PYEOF'
import sqlite3, sys, os
con = sqlite3.connect(sys.argv[1])
cur = con.cursor()
abq = os.environ['HOME'] + '/HDD_POOL/SIMULIA/EstProducts/2024'
feats = ['%SMAStaMain%', '%SMAStandard%', '%SMAStsStandardSupport%', '%SMAUStd%']
missing = []
for f in feats:
    rows = cur.execute("""SELECT fe.name, f.dest, f.hash FROM Files f
                          JOIN Features fe ON fe.featureid=f.featureid
                          WHERE fe.name LIKE ?""", (f,)).fetchall()
    for name, dest, h in rows:
        p = os.path.join(abq, dest.replace('/', os.sep))
        if not os.path.exists(p):
            missing.append((name, dest, h))
for m in missing: print("MISSING:", m)
print("total missing:", len(missing))
PYEOF
