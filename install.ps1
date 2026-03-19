# dotfiles installer for Windows (PowerShell)
# Run as ONE command (installs git via winget if needed, then everything else via scoop):
#   powershell -c "winget install Git.Git --accept-package-agreements --accept-source-agreements; $env:PATH += ';C:\Program Files\Git\cmd'; irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== dotfiles installer (Windows) ===" -ForegroundColor Cyan
Write-Host ""

# ─── Ensure git is available ─────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via winget..."
    winget install Git.Git --accept-package-agreements --accept-source-agreements
    # Add git to PATH for this session
    $env:PATH += ";C:\Program Files\Git\cmd"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Error: git still not found. Please restart your terminal and run this script again." -ForegroundColor Red
        exit 1
    }
}
Write-Host "Git: $(git --version)"

# ─── Install Scoop if missing ─────────────────────────────
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}

# ─── Add buckets ──────────────────────────────────────────
Write-Host "Adding scoop buckets..."
scoop bucket add extras 2>$null
scoop bucket add nerd-fonts 2>$null

# ─── Install dependencies ────────────────────────────────
Write-Host ""
Write-Host "Installing dependencies..."

$packages = @(
    "neovim",
    "lazygit",
    "lazydocker",
    "fzf",
    "zoxide",
    "bat",
    "gh",
    "fastfetch",
    "btop",
    "oh-my-posh"
)

foreach ($pkg in $packages) {
    if (-not (Get-Command $pkg -ErrorAction SilentlyContinue)) {
        Write-Host "  Installing $pkg..."
        scoop install $pkg
    } else {
        Write-Host "  $pkg already installed"
    }
}

# Install a Nerd Font
Write-Host "  Installing Nerd Font (MesloLGM)..."
scoop install nerd-fonts/MesloLGM-NF 2>$null

# ─── Backup existing configs ─────────────────────────────
Write-Host ""
$backupDir = "$env:USERPROFILE\.config\dotfiles-backup\$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$nvimPath = "$env:LOCALAPPDATA\nvim"
$tmuxPath = "$env:USERPROFILE\.config\tmux"

function Backup-IfExists {
    param($Path, $Name)
    if (Test-Path $Path) {
        $isOurRepo = $false
        if (Test-Path "$Path\.git") {
            Push-Location $Path
            $remote = git remote get-url origin 2>$null
            Pop-Location
            if ($remote -match "irlm") { $isOurRepo = $true }
        }
        if (-not $isOurRepo) {
            Write-Host "Found existing $Name config at $Path"
            $answer = Read-Host "  Back up before replacing? [Y/n]"
            if ($answer -eq "" -or $answer -match "^[Yy]") {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                Copy-Item -Path $Path -Destination "$backupDir\$Name" -Recurse
                Write-Host "  Backed up to $backupDir\$Name" -ForegroundColor Green
            }
        }
    }
}

Backup-IfExists -Path $nvimPath -Name "nvim"
Backup-IfExists -Path $tmuxPath -Name "tmux"

# Backup PowerShell profile
if (Test-Path $PROFILE) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item $PROFILE "$backupDir\profile.ps1"
    Write-Host "Backed up PowerShell profile to $backupDir\profile.ps1"
}

# ─── Clone configs ────────────────────────────────────────
Write-Host ""
Write-Host "Setting up configs..."

$repoBase = "https://github.com/irlm"

function Clone-OrPull {
    param($Repo, $Dest, $Name)
    if (Test-Path "$Dest\.git") {
        Push-Location $Dest
        $remote = git remote get-url origin 2>$null
        Pop-Location
        if ($remote -match "irlm") {
            Write-Host "  $Name config exists, pulling..."
            Push-Location $Dest
            git pull --ff-only
            Pop-Location
            return
        }
    }
    Write-Host "  Cloning $Name config..."
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    git clone "$repoBase/$Repo" $Dest
}

Clone-OrPull -Repo "nvim.git" -Dest $nvimPath -Name "nvim"

New-Item -ItemType Directory -Path "$env:USERPROFILE\.config" -Force | Out-Null
Clone-OrPull -Repo "tmux.git" -Dest $tmuxPath -Name "tmux"

# ─── PowerShell profile ──────────────────────────────────
Write-Host ""
Write-Host "Configuring PowerShell profile..."

$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $profileContent) { $profileContent = "" }

# oh-my-posh
if ($profileContent -notmatch "oh-my-posh") {
    Write-Host "  Adding oh-my-posh..."
    Add-Content $PROFILE "`n# ─── oh-my-posh prompt ─────────────────────────────────"
    Add-Content $PROFILE "oh-my-posh init pwsh --config `"$tmuxPath\nord.omp.json`" | Invoke-Expression"
}

# zoxide
if ($profileContent -notmatch "zoxide") {
    Write-Host "  Adding zoxide..."
    Add-Content $PROFILE "`n# ─── zoxide (smart cd) ─────────────────────────────────"
    Add-Content $PROFILE "Invoke-Expression (& { (zoxide init powershell | Out-String) })"
}

# fzf
if ($profileContent -notmatch "FzfHistory") {
    Write-Host "  Adding fzf..."
    Add-Content $PROFILE "`n# ─── fzf integration ──────────────────────────────────"
    Add-Content $PROFILE "Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock { Invoke-FzfHistory }"
}

# aliases
if ($profileContent -notmatch "lazygit") {
    Write-Host "  Adding aliases..."
    Add-Content $PROFILE "`n# ─── aliases ──────────────────────────────────────────"
    Add-Content $PROFILE "Set-Alias -Name lg -Value lazygit"
    Add-Content $PROFILE "Set-Alias -Name ld -Value lazydocker"
    Add-Content $PROFILE "Set-Alias -Name g -Value git"
    Add-Content $PROFILE "Set-Alias -Name vim -Value nvim"
}

# ─── Done ─────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Install complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal"
Write-Host "  2. Set terminal font to 'MesloLGM Nerd Font'"
Write-Host "  3. Run: nvim (plugins auto-install on first launch)"
Write-Host "  4. Run: lazygit, lazydocker, btop, fastfetch"
Write-Host "  5. For tmux: install WSL ('wsl --install' in admin PowerShell)"
Write-Host ""
