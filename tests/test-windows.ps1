$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot
foreach ($file in @('install.ps1', 'setup-windows.ps1')) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    Write-Output "$file syntax passed"
}
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
