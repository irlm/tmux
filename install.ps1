# dotfiles installer for Windows (PowerShell)
# Run: irm https://raw.githubusercontent.com/irlm/tmux/main/install.ps1 | iex

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== dotfiles installer (Windows) ===" -ForegroundColor Cyan
Write-Host ""

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
    "fzf",
    "zoxide",
    "bat",
    "gh",
    "fastfetch",
    "btop",
    "oh-my-posh",
    "git"
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

# ─── Clone configs ────────────────────────────────────────
Write-Host ""
Write-Host "Setting up configs..."

$repoBase = "https://github.com/irlm"
$nvimPath = "$env:LOCALAPPDATA\nvim"

# neovim
if (-not (Test-Path "$nvimPath\.git")) {
    Write-Host "Cloning nvim config..."
    if (Test-Path $nvimPath) { Remove-Item $nvimPath -Recurse -Force }
    git clone "$repoBase/nvim.git" $nvimPath
} else {
    Write-Host "nvim config already exists, pulling..."
    Push-Location $nvimPath
    git pull --ff-only
    Pop-Location
}

# tmux config (for reference/WSL usage)
$tmuxPath = "$env:USERPROFILE\.config\tmux"
if (-not (Test-Path "$tmuxPath\.git")) {
    Write-Host "Cloning tmux config (for WSL)..."
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.config" -Force | Out-Null
    git clone "$repoBase/tmux.git" $tmuxPath
} else {
    Write-Host "tmux config already exists, pulling..."
    Push-Location $tmuxPath
    git pull --ff-only
    Pop-Location
}

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

# oh-my-posh
if ($profileContent -notmatch "oh-my-posh") {
    Write-Host "  Adding oh-my-posh to profile..."
    Add-Content $PROFILE "`n# ─── oh-my-posh prompt ─────────────────────────────────"
    Add-Content $PROFILE "oh-my-posh init pwsh --config `"$tmuxPath\nord.omp.json`" | Invoke-Expression"
}

# zoxide
if ($profileContent -notmatch "zoxide") {
    Write-Host "  Adding zoxide to profile..."
    Add-Content $PROFILE "`n# ─── zoxide (smart cd) ─────────────────────────────────"
    Add-Content $PROFILE "Invoke-Expression (& { (zoxide init powershell | Out-String) })"
}

# fzf keybindings
if ($profileContent -notmatch "PSFzf") {
    Write-Host "  Adding fzf integration..."
    Add-Content $PROFILE "`n# ─── fzf integration ──────────────────────────────────"
    Add-Content $PROFILE "Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock { Invoke-FzfHistory }"
}

# aliases
if ($profileContent -notmatch "lazygit") {
    Write-Host "  Adding aliases..."
    Add-Content $PROFILE "`n# ─── aliases ──────────────────────────────────────────"
    Add-Content $PROFILE "Set-Alias -Name lg -Value lazygit"
    Add-Content $PROFILE "Set-Alias -Name g -Value git"
    Add-Content $PROFILE "Set-Alias -Name vim -Value nvim"
}

# ─── Done ─────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Install complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal"
Write-Host "  2. Run: nvim (plugins auto-install on first launch)"
Write-Host "  3. Set your terminal font to 'MesloLGM Nerd Font'"
Write-Host "  4. For tmux: use WSL or install Windows Terminal + WSL"
Write-Host ""
