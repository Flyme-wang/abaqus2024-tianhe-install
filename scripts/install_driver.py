#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SIMULIA 2024 无头安装驱动 v17。
- 全局异常捕获（崩溃信息写入日志）
- 媒体/组件逐个切换、安装目录退路链、许可证 FLEXnet + 27000@12.8.3.194
"""
import os, sys, pty, select, time, signal, re, traceback

MEDIA   = os.path.expanduser('~/HDD_POOL/abaqus2024_linux/1')
BIN     = os.path.join(MEDIA, 'inst/linux_a64/code/bin')
TMPDIR  = os.path.expanduser('~/HDD_POOL/tmpinstall')
INSTALL_DIR = os.path.expanduser('~/HDD_POOL/SIMULIA/EstProducts/2024')
PLUGINS_DIR = os.path.expanduser('~/HDD_POOL/SIMULIA/CAE/plugins/2024')
LICENSE = '27000@12.8.3.194'
LOG     = os.path.expanduser('~/HDD_POOL/install_driver.log')
DEBUG   = os.path.expanduser('~/HDD_POOL/install_driver_debug.log')

env = os.environ.copy()
env.update({
    'LD_LIBRARY_PATH': BIN + ':' + env.get('LD_LIBRARY_PATH', ''),
    'DSY_Skip_CheckPrereq': '1',
    'DSY_IgnoreError_CheckPrereq': '1',
    'TERM': 'xterm',
    'TMPDIR': TMPDIR,
    'NOLICENSECHECK': 'true',
})
os.makedirs(TMPDIR, exist_ok=True)
os.makedirs(os.path.dirname(INSTALL_DIR), exist_ok=True)

pid, fd = pty.fork()
if pid == 0:
    os.chdir(MEDIA)
    os.execvpe('bash', ['bash', 'StartTUI.sh'], env)

log = open(LOG, 'wb')
dbg = open(DEBUG, 'wb')
buf = b''
start = time.time()
MAX_TOTAL = 10800
IDLE_ENTER = 100
last_data = time.time()
last_resp = 0.0
media_select_done = False
components_sent = False
idir_state = 0
idir_clear_t = 0.0
license_type_done = False
srv1_count = 0
license_sent = False
license_skipped = False
plugins_dir_done = False
dirvar_done = set()
done = False

def send(data):
    try:
        os.write(fd, data)
        log.write(b'[SEND] ' + data + b'\n'); log.flush()
    except OSError as e:
        log.write(('[SEND-ERR] %s\n' % e).encode()); log.flush()

def clean(text):
    text = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', text)
    text = re.sub(r'\x1b[()][0AB]', '', text)
    text = re.sub(r'\x1b[>=]', '', text)
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
    return text.replace('\r', '')

def respond(data, why):
    global buf, last_resp
    now = time.time()
    if now - last_resp < 1.2:
        time.sleep(1.2 - (now - last_resp))
    last_resp = time.time()
    try:
        win = clean(buf[-12000:].decode('utf-8', errors='replace'))
        dbg.write(('\n[%s] responding: %r\n--- window ---\n%s\n--- end ---\n' % (why, data, win)).encode())
        dbg.flush()
    except Exception:
        pass
    send(data)
    buf = b''

def snapshot(tag):
    try:
        win = clean(buf[-12000:].decode('utf-8', errors='replace'))
        dbg.write(('\n[%s]\n--- window ---\n%s\n--- end ---\n' % (tag, win)).encode())
        dbg.flush()
    except Exception:
        pass

def is_idir_prompt(low):
    return ('installation directory' in low
            or '!c to clear the default value' in low
            or re.search(r'default \[/usr/simulia', low))

def now_low():
    return clean(buf[-12000:].decode('utf-8', errors='replace')).lower()

try:
    while not done:
        if time.time() - start > MAX_TOTAL:
            log.write(b'[FATAL] total timeout\n'); log.flush()
            os.kill(pid, signal.SIGTERM); break
        try:
            r, _, _ = select.select([fd], [], [], 2)
        except OSError:
            break
        if r:
            try:
                data = os.read(fd, 8192)
            except OSError:
                break
            if not data:
                log.write(b'[EOF]\n'); log.flush(); break
            buf += data
            log.write(data); log.flush()
            last_data = time.time()
        else:
            idle_timeout = 300 if (license_sent or license_skipped) else IDLE_ENTER
            if time.time() - last_data > idle_timeout:
                respond(b'\n', 'idle-enter')
                last_data = time.time()
            continue

        low = now_low()

        if 'installation completed successfully' in low or 'installation complete.' in low \
           or 'has been installed successfully' in low:
            log.write(b'[DONE-INSTALL]\n'); log.flush()
            done = True; break

        # 安装目录状态机（退路链）；!c 无回车实时清除默认值
        if idir_state == 0 and is_idir_prompt(low) \
           and re.search(r'default \[/usr/simulia', low):
            idir_state = 1
            idir_clear_t = time.time()
            respond(b'!c', 'idir-clear')
            continue
        if idir_state == 1 and time.time() - idir_clear_t > 2.5:
            idir_state = 2
            snapshot('idir-after-clear')
            respond(INSTALL_DIR.encode() + b'\n', 'idir-path')
            continue
        if idir_state == 2 and 'not creatable' in low:
            idir_state = 3
            respond(b'!c\n', 'idir-clear2')
            time.sleep(1.5)
            respond(INSTALL_DIR.encode() + b'\n', 'idir-path2')
            continue
        if idir_state == 3 and 'not creatable' in low:
            idir_state = 4
            respond(b'!c' + INSTALL_DIR.encode() + b'\n', 'idir-once')
            continue
        if idir_state == 4 and 'not creatable' in low:
            idir_state = 5
            respond(INSTALL_DIR.encode() + b'\n', 'idir-direct')
            continue

        # 媒体选择
        if not media_select_done and 'select the medias you want to install' in low \
           and re.search(r'enter selection \(default: next\):', low):
            media_select_done = True
            if '[*] simulia established products caa api' in low:
                respond(b'6\n', 'media-caa')
                time.sleep(0.6)
            if '[*] isight' in low:
                respond(b'7\n', 'media-isight')
                time.sleep(0.6)
            respond(b'\n', 'media-next')
            continue

        # 通用目录提示：Default [/var/DassaultSystemes/SIMULIA/X] → ~/HDD_POOL/SIMULIA/X
        mvar = re.search(r'default \[(/var/[^\]]+)\]', low)
        if mvar and mvar.group(1) not in dirvar_done:
            dirvar_done.add(mvar.group(1))
            rel = mvar.group(1).replace('/var/DassaultSystemes/SIMULIA/', '').lstrip('/')
            target = os.path.expanduser('~/HDD_POOL/SIMULIA/') + rel
            try:
                os.makedirs(target, exist_ok=True)
            except Exception:
                pass
            respond(b'!c\n', 'dirvar-clear')
            time.sleep(1.0)
            respond(target.encode() + b'\n', 'dirvar-path')
            continue

        # /var 路径不可创建 → 重试映射路径
        mvarerr = re.search(r'Path (/var/[^\s]+) is not creatable', low)
        if mvarerr:
            rel = mvarerr.group(1).replace('/var/DassaultSystemes/SIMULIA/', '').lstrip('/')
            target = os.path.expanduser('~/HDD_POOL/SIMULIA/') + rel
            respond(target.encode() + b'\n', 'dirvar-retry')
            continue

        # 插件目录等 /var/ 默认值提示：输入用户可写路径
        if not plugins_dir_done and ('plugins' in low or 'default [/var/' in low) \
           and re.search(r'default \[', low):
            plugins_dir_done = True
            os.makedirs(PLUGINS_DIR, exist_ok=True)
            respond(b'!c\n', 'plugins-clear')
            time.sleep(1.0)
            respond(PLUGINS_DIR.encode() + b'\n', 'plugins-path')
            continue
        if plugins_dir_done and 'not creatable' in low and 'plugins' in low:
            respond(PLUGINS_DIR.encode() + b'\n', 'plugins-retry')
            continue

        # 组件选择
        if not components_sent and (
                'select the components you want to install' in low
                or '3dsflow solver' in low
                or 'fe-safe tutorial models for abaqus' in low):
            components_sent = True
            for n in (1, 2, 3, 4, 5, 6):
                respond(('%d\n' % n).encode(), 'comp-%d' % n)
                time.sleep(0.5)
            respond(b'\n', 'comp-next')
            continue

        # 警告/错误对话框
        if 'please choose an action' in low:
            respond(b'\n', 'action-ok'); continue
        if 'failed to continue' in low:
            respond(b'\n', 'warn-ok'); continue

        # 许可证类型选择：选 3 = Skip licensing configuration（无回车选中 + 回车确认）
        # mars/deimos 无许可证服务器可达，校验必然失败；许可证在安装后由 env 配置
        if not license_type_done and 'license server configuration' in low \
           and re.search(r'enter selection', low):
            license_type_done = True
            respond(b'3', 'license-type-skip')
            time.sleep(1.5)
            respond(b'\n', 'license-type-enter')
            continue

        # License Server 1：!c 无回车实时清除默认值后输入
        if re.search(r'license server 1', low) and re.search(r'default \[', low):
            srv1_count += 1
            if srv1_count == 1:
                if '12.8.3.194' in low and 'localhost' not in low:
                    respond(b'\n', 'license-srv1-default-ok')
                else:
                    respond(b'!c', 'license-srv1-clear')
                    time.sleep(2.0)
                    respond(LICENSE.encode() + b'\n', 'license-srv1-value')
            elif srv1_count == 2:
                respond(b'!c', 'license-srv1-clear2')
                time.sleep(1.5)
                respond(LICENSE.encode() + b'\n', 'license-srv1-value2')
            else:
                respond(b'\n', 'license-srv1-enter')
            continue

        # 校验失败安全网
        if 'unable to validate' in low:
            respond(b'\n', 'license-fail-ok')
            continue

        # 备份服务器 2/3
        if re.search(r'license server [23]', low) and re.search(r'default \[', low):
            respond(b'\n', 'license-srv-backup'); continue

        if 'insert next volume' in low:
            respond(b'\n', 'nextvol'); continue

        m = re.search(r'enter selection \(default:[^)]*\):', low)
        if m:
            respond(b'\n', 'selection'); continue

        if 'press enter to continue' in low:
            respond(b'\n', 'enter-continue'); continue

        if len(buf) > 65536:
            buf = buf[-65536:]
except Exception:
    try:
        log.write(('[CRASH]\n%s\n' % traceback.format_exc()).encode()); log.flush()
    except Exception:
        pass
    raise

try:
    os.waitpid(pid, 0)
except Exception:
    pass
log.write(b'[DRIVER-EXIT]\n'); log.flush()
print('driver exited')
