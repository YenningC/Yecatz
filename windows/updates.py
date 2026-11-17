"""Platform-specific releases and staged updates for the Windows distribution."""
from contextlib import contextmanager
import hashlib
import ctypes
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import urllib.parse
import urllib.request
import uuid
import zipfile

VERSION = "0.1.2"
REPOSITORY = "YenningC/Yecatz"
ASSET_NAME = "Yecatz-Windows-x64.zip"
MAX_ARCHIVE = 1024 * 1024 * 1024
MAX_EXTRACTED = 3 * MAX_ARCHIVE
RUNTIME_NAMES = {"yecatz.exe", "_internal", "update-version.json"}
RECOVERY_NAME = "Restore-Yecatz.cmd"
RECOVERY_SCRIPT = r"""@echo off
setlocal DisableDelayedExpansion
cd /d "%SystemRoot%" || exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-update.ps1" -Transaction "%~dp0." -Recover
if errorlevel 1 pause
"""


def version(value, release=False):
    if not isinstance(value, str):
        return None
    pattern = r"[vV]?(\d+)\.(\d+)\.(\d+)_W" if release else r"[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:_W)?"
    match = re.fullmatch(pattern, value.strip(), flags=re.ASCII)
    return tuple(int(part or 0) for part in match.groups()) if match else None


def installed_version():
    if getattr(sys, "frozen", False):
        metadata = Path(sys.executable).parent / "update-version.json"
        if metadata.exists():
            value = json.loads(metadata.read_text(encoding="utf-8-sig"))["version"]
            if version(value, release=True) is None:
                raise ValueError("安装包版本信息无效。")
            return value
    return VERSION


def valid_release_url(url, tag, asset=False):
    if not isinstance(url, str):
        return False
    parsed = urllib.parse.urlsplit(url)
    expected = f"/{REPOSITORY}/releases/"
    expected += f"download/{tag}/{ASSET_NAME}" if asset else f"tag/{tag}"
    return (parsed.scheme == "https" and parsed.netloc.lower() == "github.com"
            and not parsed.query and not parsed.fragment
            and urllib.parse.unquote(parsed.path).lower() == expected.lower())


def select_release(releases, current):
    installed = version(current)
    if installed is None:
        raise ValueError("当前版本信息无效。")
    best = None
    for release in releases:
        if not isinstance(release, dict) or release.get("draft", True) or release.get("prerelease", True):
            continue
        tag = release.get("tag_name")
        candidate = version(tag, release=True)
        if candidate is None or candidate <= installed or not valid_release_url(release.get("html_url"), tag):
            continue
        assets = release.get("assets", [])
        if not isinstance(assets, list):
            continue
        for asset in assets:
            if (isinstance(asset, dict) and asset.get("name") == ASSET_NAME
                    and asset.get("state", "uploaded") == "uploaded"
                    and valid_release_url(asset.get("browser_download_url"), tag, asset=True)):
                if best is None or candidate > version(best["tag_name"], release=True):
                    best = {"tag_name": tag, "html_url": release["html_url"], "asset": asset}
                break
    return best


def check_update(current, get_json):
    releases = []
    page = 1
    while True:
        data = get_json(f"https://api.github.com/repos/{REPOSITORY}/releases?per_page=100&page={page}",
                        headers={"Accept": "application/vnd.github+json", "User-Agent": "Yecatz/" + current})
        if not isinstance(data, list):
            raise ValueError("GitHub 返回了无效的版本列表。")
        releases.extend(data)
        if len(data) < 100:
            return select_release(releases, current)
        page += 1


def extract_package(archive, destination, tag):
    """Extract only a normal Yecatz directory, never links or escaping paths."""
    with zipfile.ZipFile(archive) as package:
        entries = package.infolist()
        if len(entries) > 20000 or sum(item.file_size for item in entries) > MAX_EXTRACTED:
            raise ValueError("更新包解压大小超出限制。")
        names = set()
        for item in entries:
            name = item.filename.replace("\\", "/")
            path = PurePosixPath(name)
            mode = item.external_attr >> 16
            if (not path.parts or path.parts[0] != "Yecatz" or path.is_absolute()
                    or (len(path.parts) > 1 and path.parts[1].lower() not in RUNTIME_NAMES)
                    or any(part in (".", "..") or ":" in part or part.endswith((" ", "."))
                           or re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", part)
                           for part in path.parts)
                    or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR))):
                raise ValueError("更新包包含无效路径。")
            normalized = str(path).lower()
            if normalized in names:
                raise ValueError("更新包包含重复路径。")
            names.add(normalized)
        for item in entries:
            path = destination.joinpath(*PurePosixPath(item.filename.replace("\\", "/")).parts)
            if item.is_dir() or item.filename.endswith("\\"):
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with package.open(item) as source, path.open("xb") as output:
                    shutil.copyfileobj(source, output)
    app = destination / "Yecatz"
    if not (app / "Yecatz.exe").is_file() or not (app / "_internal").is_dir():
        raise ValueError("更新包缺少 Yecatz.exe 或运行依赖。")
    with (app / "Yecatz.exe").open("rb") as executable:
        if executable.read(2) != b"MZ":
            raise ValueError("更新包中的程序格式无效。")
    metadata = json.loads((app / "update-version.json").read_text(encoding="utf-8-sig"))
    if version(metadata.get("version"), release=True) != version(tag, release=True):
        raise ValueError("更新包版本与发布标签不一致。")
    return app


def download_package(asset, destination):
    expected_size = asset.get("size")
    if type(expected_size) is not int or not 0 < expected_size <= MAX_ARCHIVE:
        raise ValueError("更新包大小无效。")
    request = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "Yecatz-Updater"})
    digest = hashlib.sha256()
    count = 0
    with urllib.request.urlopen(request, timeout=30) as response, destination.open("xb") as output:
        if urllib.parse.urlsplit(response.url).scheme != "https":
            raise ValueError("更新下载必须使用 HTTPS。")
        while chunk := response.read(1024 * 1024):
            count += len(chunk)
            if count > expected_size:
                raise ValueError("更新包大小与发布记录不一致。")
            digest.update(chunk)
            output.write(chunk)
    if count != expected_size:
        raise ValueError("更新包下载不完整。")
    expected_digest = asset.get("digest")
    if expected_digest and expected_digest != "sha256:" + digest.hexdigest():
        raise ValueError("更新包 SHA-256 校验失败。")


def transaction_path(target):
    return target.parent / ("." + target.name + ".yecatz-update")


def retire_transaction(transaction):
    # Clear the active name first so interrupted cleanup cannot block the next update.
    retired = transaction.with_name(f"{transaction.name}.finished-{uuid.uuid4().hex}")
    transaction.rename(retired)
    shutil.rmtree(retired, ignore_errors=True)


def process_running(pid):
    if type(pid) is not int or pid <= 0:
        return False
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x100000, False, pid)
    if not handle:
        return ctypes.get_last_error() != 87  # Access denied is treated as still active.
    try:
        return kernel.WaitForSingleObject(handle, 0) == 258
    finally:
        kernel.CloseHandle(handle)


@contextmanager
def transaction_lock(token):
    if os.name != "nt":
        yield True
        return
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_wchar_p]
    kernel.CreateMutexW.restype = ctypes.c_void_p
    kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    kernel.ReleaseMutex.argtypes = [ctypes.c_void_p]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.CreateMutexW(None, False, rf"Global\Yecatz-Update-{token}")
    if not handle:
        yield False
        return
    try:
        acquired = kernel.WaitForSingleObject(handle, 0) in (0, 0x80)
        try:
            yield acquired
        finally:
            if acquired:
                kernel.ReleaseMutex(handle)
    finally:
        kernel.CloseHandle(handle)


def clear_finished_transaction(transaction, target):
    """Reclaim abandoned staging or a completed transaction, keeping interrupted swaps."""
    if transaction.is_symlink() or transaction.is_junction():
        return
    config_path = transaction / "config.json"
    try:
        initial = json.loads(config_path.read_text(encoding="utf-8"))
        token = initial["token"]
    except (OSError, ValueError, KeyError, TypeError):
        return
    if not isinstance(token, str) or not re.fullmatch(r"[a-zA-Z0-9-]+", token):
        return
    with transaction_lock(token) as acquired:
        if not acquired:
            return
        try:
            config = json.loads(config_path.read_text(encoding="utf-8"))
            matches = config["token"] == token and Path(config["target"]).resolve() == target.resolve()
        except (OSError, ValueError, KeyError, TypeError):
            return
        if matches:
            reclaim_transaction(transaction, config)


def reclaim_transaction(transaction, config):
    if process_running(config.get("parent_pid")) or process_running(config.get("helper_pid")):
        return
    if (transaction / "rolled-back").is_file():
        retire_transaction(transaction)
        return
    if (transaction / "applying").exists():
        if ((transaction / "committed").is_file()
                and version(installed_version()) == version(config["tag"], True)):
            retire_transaction(transaction)
        return
    if not (transaction / "result.txt").is_file():
        # A process interrupted during download leaves no result. Reclaim only its
        # staged files, after both the original app and any installer have exited.
        if (config.get("phase") != "preparing"
                or (transaction / "previous").exists() or (transaction / "installed").exists()):
            return
        retire_transaction(transaction)
        return
    if (transaction / "previous").exists():
        if not (transaction / "installed").is_file() or version(installed_version()) != version(config["tag"], True):
            return
        acknowledgment = json.loads((transaction / "ready.json").read_text(encoding="utf-8"))
        if acknowledgment.get("token") != config["token"]:
            return
    retire_transaction(transaction)


def launch_helper(transaction):
    powershell = Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
    return subprocess.Popen(
        [str(powershell), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
         "-File", str(transaction / "install-update.ps1"), "-Transaction", str(transaction)],
        cwd=str(transaction.parent), creationflags=subprocess.CREATE_NO_WINDOW,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def protected_install_roots(target):
    home = Path.home().resolve()
    roots = {home, Path(target.anchor)}
    roots.update((home / name).resolve() for name in ("Desktop", "Documents", "Downloads"))
    if os.name == "nt":
        import winreg

        shell_folders = r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, shell_folders) as key:
                for name in ("Desktop", "Personal", "{374DE290-123F-4565-9164-39C4925E467B}"):
                    try:
                        value, _ = winreg.QueryValueEx(key, name)
                    except OSError:
                        continue
                    if isinstance(value, str):
                        folder = Path(os.path.expandvars(value))
                        if folder.is_absolute():
                            roots.add(folder.resolve())
        except OSError:
            pass
    return roots


def prepare_update(release, resource_root):
    if not getattr(sys, "frozen", False):
        raise ValueError("源码运行时请使用 Git 更新；自动安装适用于打包后的 Yecatz.exe。")
    target = Path(sys.executable).resolve().parent
    if target in protected_install_roots(target) or (target / ".git").exists():
        raise ValueError("请将完整 Yecatz 文件夹放入独立的程序目录后再更新。")
    if not (target / "_internal").is_dir():
        raise ValueError("当前程序目录缺少运行依赖，无法自动更新。")
    transaction = transaction_path(target)
    if transaction.exists():
        clear_finished_transaction(transaction, target)
    config = {"target": str(target), "parent_pid": os.getpid(), "tag": release["tag_name"],
              "token": uuid.uuid4().hex, "phase": "preparing"}
    pending = Path(tempfile.mkdtemp(prefix=".yecatz-prepare-", dir=target.parent))
    try:
        with (pending / "config.json").open("w", encoding="utf-8") as output:
            json.dump(config, output)
            output.flush()
            os.fsync(output.fileno())
        try:
            pending.rename(transaction)
        except OSError:
            if transaction.exists() or transaction.is_symlink():
                raise ValueError(f"上次更新尚未完成。请退出 Yecatz，再运行 {transaction / RECOVERY_NAME} 恢复。") from None
            raise
    finally:
        shutil.rmtree(pending, ignore_errors=True)
    helper = None
    try:
        config_file = transaction / "config.json"
        archive = transaction / "package.zip"
        download_package(release["asset"], archive)
        extract_package(archive, transaction, release["tag_name"])
        archive.unlink()
        shutil.copyfile(resource_root / "install-update.ps1", transaction / "install-update.ps1")
        (transaction / RECOVERY_NAME).write_text(RECOVERY_SCRIPT, encoding="ascii", newline="\r\n")
        helper = launch_helper(transaction)
        config["helper_pid"] = helper.pid
        temporary_config = transaction / "config.tmp"
        temporary_config.write_text(json.dumps(config), encoding="utf-8")
        temporary_config.replace(config_file)
        # The helper validates paths and its configuration before the app exits.
        for _ in range(100):
            if (transaction / "helper-ready").exists():
                return
            if helper.poll() is not None:
                raise OSError("更新安装程序启动失败。")
            threading.Event().wait(0.1)
        helper.terminate()
        helper.wait(timeout=10)
        raise OSError("更新安装程序启动超时。")
    except Exception:
        # Before helper-ready, the running installation has not been touched.
        if helper is not None and helper.poll() is None:
            helper.terminate()
            helper.wait(timeout=10)
        if not (transaction / "applying").exists():
            try:
                retire_transaction(transaction)
            except OSError:
                pass
        raise


def confirm_startup(current):
    """Called by the GUI event loop only after the new Pet has initialized."""
    if not getattr(sys, "frozen", False):
        return
    target = Path(sys.executable).resolve().parent
    transaction = transaction_path(target)
    try:
        config = json.loads((transaction / "config.json").read_text(encoding="utf-8"))
        if (Path(config["target"]).resolve() != target or version(config["tag"], True) != version(current)
                or not (transaction / "installed").exists()):
            return
        acknowledgment = {"token": config["token"], "pid": os.getpid(), "tag": config["tag"]}
        temporary = transaction / "ready.tmp"
        temporary.write_text(json.dumps(acknowledgment), encoding="utf-8")
        temporary.replace(transaction / "ready.json")
    except (OSError, ValueError, KeyError, TypeError):
        pass
