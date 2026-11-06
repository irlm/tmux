$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot
foreach ($file in @('install.ps1', 'setup-windows.ps1', 'scripts\herdr-config.ps1', 'scripts\status_right.ps1')) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    Write-Output "$file syntax passed"
}
# install.ps1 is run as `irm ... | iex`: a byte-order mark would reach iex as
# the first character of the first command and the script would never start.
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $RepoRoot 'install.ps1'))
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'install.ps1 must not start with a byte-order mark (irm | iex breaks on it)' }
if ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1) { throw 'install.ps1 must be ASCII only (no BOM, so no encoding hint for Windows PowerShell)' }
Write-Output 'install.ps1 is ASCII without a byte-order mark'
# Execute only the clone helper against temporary configs and a fake Git command.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'install.ps1'), [ref]$tokens, [ref]$errors)
$definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Clone-OrPull' }, $true)
Invoke-Expression $definition.Extent.Text
$repoBase = 'https://github.com/irlm'
$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $Scratch | Out-Null
$script:FailClone = $true
function git {
    if ($args[0] -eq 'clone') {
        if ($script:FailClone) { $global:LASTEXITCODE = 1; return }
        New-Item -ItemType Directory (Join-Path $args[2] '.git') -Force | Out-Null
        Set-Content (Join-Path $args[2] 'managed') 'new config'
        $global:LASTEXITCODE = 0
    } else { throw "Unexpected Git operation: $args" }
}
try {
    $Dest = Join-Path $Scratch 'config'
    New-Item -ItemType Directory $Dest | Out-Null
    Set-Content (Join-Path $Dest 'personal') 'keep this'
    $Threw = $false
    try { Clone-OrPull tmux.git $Dest tmux } catch { $Threw = $true }
    if (-not $Threw -or (Get-Content (Join-Path $Dest 'personal') -Raw).Trim() -ne 'keep this') {
        throw 'Failed clone did not preserve the original config.'
    }
    $script:FailClone = $false
    Clone-OrPull tmux.git $Dest tmux
    $Backups = @(Get-ChildItem $Scratch -Filter 'config.backup.*' -Directory)
    if ($Backups.Count -ne 1 -or (Get-Content (Join-Path $Backups[0].FullName 'personal') -Raw).Trim() -ne 'keep this') {
        throw 'Successful replacement did not retain a backup.'
    }
    if (-not (Test-Path (Join-Path $Dest 'managed'))) { throw 'New config was not activated.' }
    Write-Output 'Windows clone failure/success preservation passed'
} finally {
    Remove-Item $Scratch -Recurse -Force
}

# Render the Herdr config the Windows way, without Herdr or Git Bash installed:
# the keys, the popups through the named bash, the theme, the user's own file.
$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $Scratch | Out-Null
try {
    $env:TMUX_THEME_DIR = $Scratch
    $env:HERDR_CONFIG_PATH = Join-Path $Scratch 'config.toml'
    $env:HERDR_BASH = 'C:\Program Files\Git\bin\bash.exe'
    Set-Content (Join-Path $Scratch 'theme') 'catppuccin'
    Set-Content (Join-Path $Scratch 'options.env') 'popup_size=70%'
    Set-Content (Join-Path $Scratch 'herdr.toml') '[theme.custom.light]' -NoNewline
    $rendered = & pwsh -NoProfile -NonInteractive -File (Join-Path $RepoRoot 'scripts\herdr-config.ps1') -Print | Out-String
    foreach ($expected in @('prefix = "ctrl+a"', 'split_vertical = "prefix+|"', 'name = "catppuccin"', 'overlay1 = "#cad3f5"',
                            'key = "prefix+g"', 'width = "70%"', '[theme.custom.light]', 'status_right.ps1', 'interval_seconds = 15')) {
        if ($rendered -notmatch [regex]::Escape($expected)) { throw "Windows Herdr render is missing: $expected" }
    }
    # Commands name bash by its 8.3 path on Windows (no quotes survive cmd.exe) and by the quoted path elsewhere.
    foreach ($pattern in @('bash\.exe\\?"? "?.*actions\.sh\\?"? run git', 'bash\.exe\\?"? "?.*herdr-navigate\.sh\\?"? left')) {
        if ($rendered -notmatch $pattern) { throw "Windows Herdr render is missing a command: $pattern" }
    }
    # Line endings are the platform's: CRLF when rendered on Windows.
    if ($rendered -notmatch 'run info"\r?\nwidth = 100\r?\nheight = 36') { throw 'Windows Herdr render did not size the info popup.' }
    if ($rendered -match 'run new-session' -or $rendered -match '@@') { throw 'Windows Herdr render kept a native prompt or a placeholder.' }
    if ($rendered -match 'type = "hostname"') { throw 'Windows Herdr render still uses the hostname entry instead of the readings.' }
    # On Windows the readings script must answer with a CPU and memory figure.
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $line = & pwsh -NoProfile -NonInteractive -File (Join-Path $RepoRoot 'scripts\status_right.ps1') -Ascii | Out-String
        if ($line -notmatch 'CPU \d+(\.\d+)?%' -or $line -notmatch 'RAM \d+%') { throw "Windows status line is incomplete: $line" }
        Write-Output 'Windows status line passed'
    }
    # A palette taken from a Herdr theme selects that theme as Herdr ships it,
    # and the next pick replaces it: the installed name is the previous pick.
    Set-Content $env:HERDR_CONFIG_PATH $rendered -NoNewline
    Set-Content (Join-Path $Scratch 'theme') 'tokyo-night'
    $rendered = & pwsh -NoProfile -NonInteractive -File (Join-Path $RepoRoot 'scripts\herdr-config.ps1') -Print | Out-String
    $block = ($rendered -split '\[terminal\]')[0]
    foreach ($expected in @('name = "tokyo-night"', 'overlay1 = "#c0caf5"', '# Theme written by the renderer: tokyo-night')) {
        if ($block -notmatch [regex]::Escape($expected)) { throw "Windows Herdr theme is missing: $expected" }
    }
    if ($block -match '(?m)^text = ') { throw 'A Herdr theme picked by name must keep its own colours.' }
    if ((Get-Content (Join-Path $Scratch 'options.env') -Raw) -match 'herdr_theme') { throw 'The previous pick was read as one made in Herdr.' }
    # A name Herdr's own settings wrote since is kept.
    Set-Content $env:HERDR_CONFIG_PATH ($rendered -replace 'name = "tokyo-night"', 'name = "dracula"') -NoNewline
    $rendered = & pwsh -NoProfile -NonInteractive -File (Join-Path $RepoRoot 'scripts\herdr-config.ps1') -Print | Out-String
    if ($rendered -notmatch 'name = "dracula"' -or (Get-Content (Join-Path $Scratch 'options.env') -Raw) -notmatch 'herdr_theme=dracula') { throw 'A theme picked in Herdr was not kept.' }
    $plugin = & pwsh -NoProfile -NonInteractive -File (Join-Path $RepoRoot 'scripts\herdr-config.ps1') -PrintPlugin | Out-String
    if ($plugin -notmatch 'id = "palette"' -or $plugin -notmatch '"windows"') { throw 'Windows Herdr plugin manifest is incomplete.' }
    Write-Output 'Windows Herdr render passed'
} finally {
    Remove-Item Env:TMUX_THEME_DIR, Env:HERDR_CONFIG_PATH, Env:HERDR_BASH -ErrorAction SilentlyContinue
    Remove-Item $Scratch -Recurse -Force
}
