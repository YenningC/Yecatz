param([string]$Version = "")

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$requiredAssets = @("cat.png", "cat-blink.png", "cat-entry.png", "AppIcon.icns", "pixel-zh-hans.ttf", "tie-status.png")
$missingAssets = @(
    foreach ($name in $requiredAssets) {
        $path = Join-Path "Assets" $name
        $asset = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $asset -or $asset.PSIsContainer -or $asset.Length -eq 0) {
            $path
        }
    }
)
if ($missingAssets.Count -gt 0) {
    throw ("缺少必需素材或文件为空，请向维护者取得完整的 Assets 目录：`n  " + ($missingAssets -join "`n  "))
}

if (-not (Test-Path ".venv-win\Scripts\python.exe")) {
    py -3.12 -m venv .venv-win
    if ($LASTEXITCODE -ne 0) { throw "请先安装 Windows 版 Python 3.12。" }
}
$python = ".venv-win\Scripts\python.exe"
if (-not $Version) {
    $sourceVersion = & $python -c "import ast; from pathlib import Path; tree = ast.parse(Path('windows/updates.py').read_text(encoding='utf-8')); print(next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'VERSION' for target in node.targets)))"
    if ($LASTEXITCODE -ne 0) { throw "读取 Windows 默认版本失败。" }
    $Version = "$sourceVersion`_W"
}
if ($Version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+_W$') {
    throw "版本参数应使用 1.0.0_W 格式。"
}
& $python -m pip install -r windows/requirements.txt pyinstaller==6.22.2 pillow==12.0.0
if ($LASTEXITCODE -ne 0) { throw "安装构建依赖失败。" }
$originalBuildPath = $env:PATH
try {
    # Qt uses Windows ICU; unrelated PATH entries can contain incompatible ICU DLLs.
    $env:PATH = "$env:SystemRoot\System32;$originalBuildPath"
    & $python -m PyInstaller --noconfirm --clean --windowed --name Yecatz --icon Assets/AppIcon.icns --add-data "Assets;Assets" --add-data "persona.md;." --add-data "windows/install-update.ps1;." windows/yecatz.py
} finally {
    $env:PATH = $originalBuildPath
}
if ($LASTEXITCODE -ne 0) { throw "Windows 构建失败。" }
$versionFile = Join-Path (Get-Location) "dist/Yecatz/update-version.json"
$versionJson = @{ version = $Version } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($versionFile, $versionJson, [System.Text.UTF8Encoding]::new($false))
Compress-Archive -Path dist/Yecatz -DestinationPath dist/Yecatz-Windows-x64.zip -Force
Write-Host "已创建 dist/Yecatz-Windows-x64.zip ($Version)"
