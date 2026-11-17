param(
    [Parameter(Mandatory = $true)][string]$Transaction,
    [switch]$Recover
)
$ErrorActionPreference = 'Stop'

$transactionRoot = [IO.Path]::GetFullPath($Transaction).TrimEnd('\')
$config = Get-Content -LiteralPath (Join-Path $transactionRoot 'config.json') -Raw | ConvertFrom-Json
$target = [IO.Path]::GetFullPath($config.target).TrimEnd('\')
$expected = Join-Path (Split-Path -Parent $target) ('.' + (Split-Path -Leaf $target) + '.yecatz-update')
if ($transactionRoot -ne $expected -or $target -eq [IO.Path]::GetPathRoot($target).TrimEnd('\') -or
    $config.token -cnotmatch '^[a-zA-Z0-9-]+$') {
    throw 'Invalid update directory or token.'
}

function Get-PlainItem([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Update path must not be a link: $Path"
    }
    return $item
}

$targetItem = Get-PlainItem $target
$transactionItem = Get-PlainItem $transactionRoot
if (-not $targetItem.PSIsContainer -or -not $transactionItem.PSIsContainer) {
    throw 'Invalid update or installation directory.'
}

$incoming = Join-Path $transactionRoot 'Yecatz'
$backup = Join-Path $transactionRoot 'previous'
$failed = Join-Path $transactionRoot 'failed'
$ready = Join-Path $transactionRoot 'ready.json'
$applying = Join-Path $transactionRoot 'applying'
$committed = Join-Path $transactionRoot 'committed'
$rolledBack = Join-Path $transactionRoot 'rolled-back'
$oldMetadataAbsent = Join-Path $transactionRoot 'old-metadata-absent'
$runtime = @('Yecatz.exe', '_internal', 'update-version.json')

function Move-WithRetry([string]$Source, [string]$Destination) {
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $item = Get-PlainItem $Source
            if (-not $item) { throw "Missing update path: $Source" }
            if ($item.PSIsContainer) {
                [IO.Directory]::Move($Source, $Destination)
            } else {
                [IO.File]::Move($Source, $Destination)
            }
            return
        } catch {
            if ($attempt -eq 29) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Remove-WithRetry([string]$Path) {
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            if (Get-PlainItem $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
            return
        } catch {
            if ($attempt -eq 29) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

function Write-Marker([string]$Path) {
    $temporary = "$Path.tmp"
    $stream = [IO.FileStream]::new($temporary, [IO.FileMode]::Create, [IO.FileAccess]::Write,
                                  [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Move($temporary, $Path)
}

function Start-Yecatz([string]$UpdateError = '') {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $target 'Yecatz.exe'
    $startInfo.WorkingDirectory = $target
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.EnvironmentVariables['PYINSTALLER_RESET_ENVIRONMENT'] = '1'
    if ($UpdateError) { $startInfo.EnvironmentVariables['YECATZ_UPDATE_ERROR'] = $UpdateError }
    return [System.Diagnostics.Process]::Start($startInfo)
}

function Remove-CommittedTransaction {
    # Retain the recovery script and durable markers until all backups are removed.
    Remove-WithRetry $backup
    $finished = "$transactionRoot.finished-$($config.token)"
    Move-WithRetry $transactionRoot $finished
    Remove-WithRetry $finished
}

function Restore-Runtime {
    foreach ($directory in @($incoming, $backup, $failed)) {
        $item = Get-PlainItem $directory
        if ($item -and -not $item.PSIsContainer) { throw "Invalid update directory: $directory" }
    }
    [IO.Directory]::CreateDirectory($failed) | Out-Null
    foreach ($name in $runtime) {
        $current = Join-Path $target $name
        $saved = Join-Path $backup $name
        $staged = Join-Path $incoming $name
        $rejected = Join-Path $failed $name

        if (Get-PlainItem $saved) {
            if (Get-PlainItem $current) { Move-WithRetry $current $rejected }
            Move-WithRetry $saved $current
        } elseif ($name -eq 'update-version.json' -and (Test-Path -LiteralPath $oldMetadataAbsent)) {
            # A legacy installation had no version file. Remove only the staged version file.
            if (-not (Get-PlainItem $staged) -and (Get-PlainItem $current)) {
                Move-WithRetry $current $rejected
            }
        } elseif (-not (Get-PlainItem $current)) {
            throw "Cannot restore missing runtime entry: $current"
        }
    }
    # Keep the diagnostics and stage until the next update. This records completed rollback
    # even if the helper is interrupted before opening the restored app.
    Write-Marker $rolledBack
}

function Write-Result([string]$Message) {
    [IO.File]::WriteAllText((Join-Path $transactionRoot 'result.txt'), $Message)
}

# Both entry points and Python cleanup serialize access to this transaction.
$mutex = [Threading.Mutex]::new($false, "Global\Yecatz-Update-$($config.token)")
$locked = $false
$oldProcess = $null
$newProcess = $null
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'An update or recovery is already running.' }
    # Another helper may have finished between reading config and acquiring the lock.
    $currentConfig = Get-Content -LiteralPath (Join-Path $transactionRoot 'config.json') -Raw | ConvertFrom-Json
    if ($currentConfig.token -cne $config.token) { throw 'The update transaction has changed.' }

    if ($Recover) {
        if (Test-Path -LiteralPath $committed) {
            Remove-CommittedTransaction
            exit 0
        }
        if (-not (Test-Path -LiteralPath $applying)) { throw 'Installation has not started.' }
        $running = Get-Process -Name 'Yecatz' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq (Join-Path $target 'Yecatz.exe') }
        if ($running) { throw 'Please close Yecatz before restoring the old version.' }
        if (-not (Test-Path -LiteralPath $rolledBack)) {
            Restore-Runtime
            Write-Result '更新中断，已恢复旧版本。'
        }
        $null = Start-Yecatz '更新中断，已恢复旧版本。'
        exit 0
    }

    if ((Test-Path -LiteralPath $applying) -or (Test-Path -LiteralPath $backup)) {
        throw 'Invalid or unfinished update. Run Restore-Yecatz.cmd to recover.'
    }
    if (-not (Get-PlainItem $incoming).PSIsContainer) { throw 'Invalid update package.' }
    foreach ($item in Get-ChildItem -LiteralPath $incoming -Force) {
        if ($item.Name -notin $runtime) { throw "Unexpected entry in update package: $($item.Name)" }
    }
    foreach ($name in $runtime) {
        $staged = Get-PlainItem (Join-Path $incoming $name)
        $current = Get-PlainItem (Join-Path $target $name)
        $directory = $name -eq '_internal'
        if (-not $staged -or $staged.PSIsContainer -ne $directory -or
            ($current -and $current.PSIsContainer -ne $directory) -or
            (-not $current -and $name -ne 'update-version.json')) {
            throw "Invalid runtime entry: $name"
        }
    }
    $oldProcess = Get-Process -Id $config.parent_pid -ErrorAction SilentlyContinue
    if ($oldProcess -and $oldProcess.Path -ne (Join-Path $target 'Yecatz.exe')) {
        throw 'The running application path does not match the installation.'
    }

    [IO.File]::WriteAllText((Join-Path $transactionRoot 'helper-ready'), 'ready')
    $oldExited = $false
    try {
        if ($oldProcess -and -not $oldProcess.WaitForExit(60000)) {
            throw 'Yecatz did not exit within 60 seconds.'
        }
        $oldExited = $true
        if (-not (Get-PlainItem (Join-Path $target 'update-version.json'))) {
            Write-Marker $oldMetadataAbsent
        }
        Write-Marker $applying
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($name in $runtime) {
            $current = Join-Path $target $name
            if (Get-PlainItem $current) { Move-WithRetry $current (Join-Path $backup $name) }
            Move-WithRetry (Join-Path $incoming $name) $current
        }
        Write-Marker (Join-Path $transactionRoot 'installed')

        $newProcess = Start-Yecatz
        $healthy = $false
        for ($attempt = 0; $attempt -lt 120; $attempt++) {
            if (Test-Path -LiteralPath $ready) {
                $ack = Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
                if ($ack.token -ceq $config.token -and $ack.tag -ceq $config.tag -and $ack.pid -eq $newProcess.Id) {
                    Start-Sleep -Seconds 2
                    $newProcess.Refresh()
                    $healthy = -not $newProcess.HasExited
                    break
                }
            }
            $newProcess.Refresh()
            if ($newProcess.HasExited) { break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $healthy) { throw 'The new version did not confirm a successful startup.' }
        Write-Marker $committed
    } catch {
        $failure = $_.Exception.Message
        $line = [Environment]::NewLine
        try {
            if ($newProcess) {
                $newProcess.Refresh()
                if (-not $newProcess.HasExited) {
                    Stop-Process -Id $newProcess.Id -Force
                    $newProcess.WaitForExit()
                }
            }
            if (Test-Path -LiteralPath $applying) { Restore-Runtime }
            Write-Result "更新失败，已恢复旧版本。$line$failure"
            if ($oldExited) {
                $null = Start-Yecatz "更新失败，已恢复旧版本。详细记录保存在 $transactionRoot。$failure"
            }
        } catch {
            Write-Result "恢复未完成。请退出 Yecatz，再运行 Restore-Yecatz.cmd。$line$failure$line$($_.Exception.Message)"
        }
        exit 1
    }

    try {
        Remove-CommittedTransaction
    } catch {
        if (Test-Path -LiteralPath $transactionRoot) {
            Write-Result "更新成功，清理未完成。可运行 Restore-Yecatz.cmd 重试。$($_.Exception.Message)"
        }
        throw
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
