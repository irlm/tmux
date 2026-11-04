# The Windows twin of status_right.sh: one line with the network rate, CPU,
# memory and battery for Herdr's tab bar, plain text with the same icons.
#
#   status_right.ps1            whole line
#   status_right.ps1 -Part cpu  one reading (net, cpu, ram, battery)
#
# Everything comes from CIM and the adapter counters, which answer at once;
# the network rate is the difference from the previous run, kept in a small
# cache file. Nerd Font glyphs match the Unix line; -Ascii uses labels.
param([string]$Part = '', [switch]$Ascii, [int]$ProcessThreshold = -1)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) { exit 0 }
# Windows PowerShell writes in the console code page by default, which turns
# the glyphs into question marks before Herdr reads them.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$cacheDir = Join-Path $env:LOCALAPPDATA 'tmux\cache'
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
$cache = Join-Path $cacheDir 'status-net.json'
# Name the busiest process above this CPU percentage, as the Unix line does;
# cpu_process_threshold in ~/.config/tmux-user/options.env, 0 always, off never.
if ($ProcessThreshold -lt 0) {
    $ProcessThreshold = 30
    $options = Join-Path $env:USERPROFILE '.config\tmux-user\options.env'
    if (Test-Path $options) {
        $line = Get-Content $options | Where-Object { $_ -match '^cpu_process_threshold=(.*)$' } | Select-Object -First 1
        if ($line -match '^cpu_process_threshold=(.*)$') { $ProcessThreshold = if ($Matches[1].Trim() -eq 'off') { 1000 } elseif ($Matches[1] -match '^\d+$') { [int]$Matches[1] } else { 30 } }
    }
}
$sep = ' | '
$cpuIcon = if ($Ascii) { 'CPU' } else { [char]::ConvertFromUtf32(0xF061A) }
$ramIcon = if ($Ascii) { 'RAM' } else { [char]::ConvertFromUtf32(0xF035B) }

function Rate($bytesPerSecond) {
    if ($bytesPerSecond -ge 1MB) { return ('{0,4:N1}M/s' -f ($bytesPerSecond / 1MB)) }
    if ($bytesPerSecond -ge 1KB) { return ('{0,4:N0}K/s' -f ($bytesPerSecond / 1KB)) }
    return ('{0,4:N0}B/s' -f $bytesPerSecond)
}

$parts = @()
# Network: sum of all physical adapters, rate since the previous sample.
$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$stats = Get-NetAdapterStatistics | Measure-Object -Property ReceivedBytes, SentBytes -Sum
$rx = ($stats | Where-Object Property -eq 'ReceivedBytes').Sum; $tx = ($stats | Where-Object Property -eq 'SentBytes').Sum
$net = ''
# Per-process CPU seconds are cumulative; the busiest process over the last
# interval is the largest increase since the previous sample.
$procs = @{}
foreach ($proc in Get-Process) { if ($proc.CPU) { $procs[[string]$proc.Id] = @{ n = $proc.ProcessName; c = [double]$proc.CPU } } }
$busiest = ''
if (Test-Path $cache) {
    $prev = Get-Content $cache -Raw | ConvertFrom-Json
    $seconds = ($now - $prev.t) / 1000
    if ($seconds -gt 0 -and $seconds -lt 120 -and $rx -ge $prev.rx -and $tx -ge $prev.tx) {
        $net = ('{0} {1} {2} {3}' -f [char]0x2193, (Rate (($rx - $prev.rx) / $seconds)), [char]0x2191, (Rate (($tx - $prev.tx) / $seconds)))
    }
    if ($prev.p) {
        $best = 0
        foreach ($id in $procs.Keys) {
            $before = $prev.p.$id
            if ($before -and $procs[$id].n -eq $before.n) {
                $delta = $procs[$id].c - $before.c
                if ($delta -gt $best) { $best = $delta; $busiest = $procs[$id].n }
            }
        }
    }
}
@{ t = $now; rx = $rx; tx = $tx; p = $procs } | ConvertTo-Json -Compress -Depth 3 | Set-Content $cache
if ($net) { $parts += @{ kind = 'net'; text = $net } }
# CPU: the processors' current load, with the busiest process when it is high.
$load = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
if ($null -ne $load) {
    $cpu = '{0} {1:N1}%' -f $cpuIcon, $load
    if ($busiest -and $load -ge $ProcessThreshold) { $cpu += ' ' + $busiest.Substring(0, [Math]::Min(14, $busiest.Length)) }
    $parts += @{ kind = 'cpu'; text = $cpu }
}
# Memory: used share of physical memory, as Task Manager shows it.
$os = Get-CimInstance Win32_OperatingSystem
if ($os) { $parts += @{ kind = 'ram'; text = ('{0} {1:N0}%' -f $ramIcon, (100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize)) } }
# Battery, when the machine has one.
$battery = Get-CimInstance Win32_Battery | Select-Object -First 1
if ($battery) {
    $pct = [int]$battery.EstimatedChargeRemaining
    $charging = $battery.BatteryStatus -in 2, 6, 7, 8, 9
    $icon = if ($Ascii) { 'BAT' } elseif ($charging) { [char]0x26A1 } else {
        $glyphs = @(0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079)
        [char]::ConvertFromUtf32($glyphs[[Math]::Min(9, [Math]::Floor($pct / 10))])
    }
    $parts += @{ kind = 'battery'; text = ('{0} {1}%' -f $icon, $pct) }
}
if ($Part) {
    $hit = $parts | Where-Object { $_.kind -eq $Part } | Select-Object -First 1
    if ($hit) { Write-Output $hit.text }
} else {
    Write-Output (($parts | ForEach-Object { $_.text }) -join $sep)
}
