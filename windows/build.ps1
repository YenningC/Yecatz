$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
if (-not (Test-Path ".venv-win\Scripts\python.exe")) {
    py -3.12 -m venv .venv-win
    if ($LASTEXITCODE -ne 0) { throw "请先安装 Windows 版 Python 3.12。" }
}
$python = ".venv-win\Scripts\python.exe"
& $python -m pip install -r windows/requirements.txt pyinstaller==6.22.2 pillow==12.0.0
if ($LASTEXITCODE -ne 0) { throw "安装构建依赖失败。" }
& $python -m PyInstaller --noconfirm --clean --windowed --name Yecatz --icon Assets/AppIcon.icns --add-data "Assets;Assets" --add-data "persona.md;." windows/yecatz.py
if ($LASTEXITCODE -ne 0) { throw "Windows 构建失败。" }
Compress-Archive -Path dist/Yecatz -DestinationPath dist/Yecatz-Windows-x64.zip -Force
Write-Host "已创建 dist/Yecatz-Windows-x64.zip"
