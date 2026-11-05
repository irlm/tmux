# dotfiles installer for Windows (PowerShell)
# Run as Administrator:  irm https://raw.githubusercontent.com/irlm/workbench/main/install.ps1 | iex

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== dotfiles installer (Windows) ===" -ForegroundColor Cyan
Write-Host ""

# ─── Free space ──────────────────────────────────────────
# Everything below lands on the profile drive (Scoop, the checkout, Docker
# Desktop's 500 MB installer). A full drive fails half-way with misleading
# errors, so stop early instead.
function Get-FreeGB {
    try { [math]::Round((Get-PSDrive -Name $env:USERPROFILE.Substring(0, 1)).Free / 1GB, 1) } catch { $null }
}
$freeGB = Get-FreeGB
if ($null -ne $freeGB -and $freeGB -lt 2) {
    Write-Host "Only $freeGB GB free on the $($env:USERPROFILE.Substring(0, 2)) drive; the install needs at least 2 GB (10 GB with Docker Desktop)." -ForegroundColor Red
    Write-Host "Free some space and run the installer again. Nothing was changed." -ForegroundColor Red
    return
}

# ─── Ensure git is available ─────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via winget..."
    winget install Git.Git --accept-package-agreements --accept-source-agreements --source winget
    # Refresh PATH from registry (picks up git without restarting terminal)
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
    # Fallback: add common git paths manually
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        foreach ($p in @("$env:ProgramFiles\Git\cmd", "${env:ProgramFiles(x86)}\Git\cmd")) {
            if (Test-Path $p) { $env:PATH += ";$p" }
        }
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Error: git still not found. Please restart your terminal and run this script again." -ForegroundColor Red
        return
    }
}
Write-Host "Git: $(git --version)"

# ─── Install Scoop if missing ─────────────────────────────
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..."
    # A process- or machine-level policy may already override this; that is fine.
    try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } catch {}
    # Scoop's installer refuses an elevated shell unless told it is intended,
    # and this script is normally run as Administrator.
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $scoopInstaller = Join-Path $env:TEMP "scoop-install.ps1"
    Invoke-RestMethod -Uri https://get.scoop.sh -OutFile $scoopInstaller
    if ($elevated) { & $scoopInstaller -RunAsAdmin } else { & $scoopInstaller }
    Remove-Item $scoopInstaller -ErrorAction SilentlyContinue
    $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "Scoop did not install; see the messages above." }
}

# ─── Add buckets ──────────────────────────────────────────
Write-Host "Adding scoop buckets..."
scoop bucket add extras 2>$null
scoop bucket add nerd-fonts 2>$null
scoop bucket add java 2>$null       # openjdk lives here, not in main

# ─── Install dependencies ────────────────────────────────
Write-Host ""
Write-Host "Installing dependencies..."

$manifestPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot "tools.tsv" } else { "" }
if ($manifestPath -and (Test-Path $manifestPath)) {
    $toolManifest = Import-Csv $manifestPath -Delimiter "`t"
} else {
    $toolManifest = (Invoke-RestMethod "https://raw.githubusercontent.com/irlm/workbench/main/tools.tsv") | ConvertFrom-Csv -Delimiter "`t"
}
# Neovim is the optional second editor (Helix is the managed one): set
# INSTALL_NVIM=1, or keep an existing %LOCALAPPDATA%\nvim checkout, to get it.
$nvimPath = "$env:LOCALAPPDATA\nvim"
$wantNvim = ($env:INSTALL_NVIM -eq "1") -or (Test-Path "$nvimPath\init.lua")
# The default is the workbench (Herdr, Helix, the tools, popups and agent
# keys). INSTALL_FULL=1 adds the language toolchains and Docker Desktop.
$wantFull = ($env:INSTALL_FULL -eq "1")
$required = @($toolManifest | Where-Object { $_.scoop -ne "-" -and $_.profile -ne "nvim" } | ForEach-Object { $_.scoop })
$nvimTools = @($toolManifest | Where-Object { $_.scoop -ne "-" -and $_.profile -eq "nvim" } | ForEach-Object { $_.scoop })
$extras = if ($wantFull) { @("nodejs", "go", "openjdk") } else { @() }   # language toolchains: wanted, not required
if ($wantNvim) { $extras = $nvimTools + $extras }
# Windows on ARM: Neovim compiles its treesitter parsers with gcc, which only
# exists for x86_64 there, and the tree-sitter tool must match the parsers it
# loads. The x86_64 Neovim and tree-sitter run under emulation, consistently.
$x64Only = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { @("neovim", "tree-sitter") } else { @() }

foreach ($pkg in $required + $extras) {
    # Check if already installed via scoop (more reliable than checking command name)
    $installed = scoop list $pkg 2>$null | Select-String $pkg
    if ($installed) {
        Write-Host "  $pkg already installed"
    } else {
        Write-Host "  Installing $pkg..."
        if ($pkg -in $x64Only) { scoop install $pkg --arch 64bit } else { scoop install $pkg }
        if ($LASTEXITCODE -ne 0) {
            if ($pkg -in $required) { throw "Failed to install $pkg. Re-run after resolving the error above." }
            Write-Host "  Skipped $pkg (install it later with: scoop install $pkg)" -ForegroundColor Yellow
        }
    }
}

# ─── gh extensions ────────────────────────────────────────
# `gh dash` (Alt+Shift+G / tmux C-a G) is a gh extension, not part of gh itself.
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghDash = gh extension list 2>$null | Select-String "dlvhdr/gh-dash"
    gh auth status 2>&1 | Out-Null
    if ($ghDash) {
        Write-Host "  gh-dash already installed"
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Host "  gh-dash skipped: run 'gh auth login', then 'gh extension install dlvhdr/gh-dash'" -ForegroundColor Yellow
    } else {
        Write-Host "  Installing gh-dash extension..."
        gh extension install dlvhdr/gh-dash
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Warning: gh-dash install failed. Run 'gh auth login', then 'gh extension install dlvhdr/gh-dash'" -ForegroundColor Yellow
        }
    }
}

# Install Nerd Fonts
Write-Host "  Installing Nerd Fonts..."
foreach ($font in @("JetBrainsMono-NF", "Meslo-NF")) {
    try { scoop install "nerd-fonts/$font" 2>$null } catch {}
}
# Also install via winget (registers system-wide, shows in Windows Terminal)
try {
    winget list --name "JetBrainsMono" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Registering JetBrains Mono Nerd Font system-wide..."
        winget install DEVCOM.JetBrainsMonoNerdFont --accept-package-agreements --accept-source-agreements --source winget 2>$null
    }
} catch {}

# Point Windows Terminal at the font when it has none of its own yet.
foreach ($wt in @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json", "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json")) {
    if (-not (Test-Path $wt)) { continue }
    try {
        $settings = Get-Content $wt -Raw | ConvertFrom-Json
        if (-not $settings.PSObject.Properties["profiles"]) { continue }
        if (-not $settings.profiles.PSObject.Properties["defaults"]) { $settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force }
        $defaults = $settings.profiles.defaults
        # Strict mode: a missing property is an error, so look it up by name.
        $font = $defaults.PSObject.Properties["font"]
        if ($font -and $font.Value -and $font.Value.PSObject.Properties["face"] -and $font.Value.face) {
            Write-Host "  Windows Terminal keeps its own font ($($font.Value.face))"
        } else {
            Copy-Item $wt "$wt.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue ([PSCustomObject]@{ face = "JetBrainsMono Nerd Font" }) -Force
            $settings | ConvertTo-Json -Depth 32 | Set-Content $wt -Encoding UTF8
            Write-Host "  Windows Terminal: default font set to JetBrainsMono Nerd Font"
        }
    } catch { Write-Host "  Windows Terminal font not set: $_" -ForegroundColor Yellow }
    break
}

# ─── Language toolchains ─────────────────────────────────
# Wanted for the editors' language servers, not required for the terminal
# setup: a failure here is reported and skipped.
Write-Host ""
if ($wantFull) { Write-Host "Installing language toolchains..." }

# Scoop puts new shims on the user PATH; this process needs them now.
function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";$env:USERPROFILE\scoop\shims"
}

if ($wantNvim) {
    try {
        # Neovim compiles its treesitter parsers on this machine: a C compiler
        # beside the tree-sitter CLI, both from Scoop's main bucket.
        if (-not (scoop list gcc 2>$null | Select-String gcc)) {
            Write-Host "  Installing gcc (treesitter parsers)..."
            scoop install gcc
        }
        Refresh-Path
    } catch { Write-Host "  Skipped the treesitter toolchain: $_" -ForegroundColor Yellow }
}

if ($wantFull) {
    try {
        # Rust: install rustup + rust-analyzer (rustup reports progress on stderr)
        if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
            Write-Host "  Installing Rust via rustup..."
            scoop install rustup-msvc
            Refresh-Path
        }
        if (Get-Command rustup -ErrorAction SilentlyContinue) {
            $raInstalled = rustup component list 2>$null | Select-String "rust-analyzer.*installed"
            if (-not $raInstalled) {
                Write-Host "  Adding rust-analyzer component..."
                rustup default stable 2>&1 | Out-Null
                rustup component add rust-analyzer 2>&1 | Out-Null
            } else {
                Write-Host "  rust-analyzer already installed"
            }
        }
    } catch { Write-Host "  Skipped Rust toolchain: $_" -ForegroundColor Yellow }

    try {
        # Scala: install coursier + metals
        if (-not (Get-Command metals -ErrorAction SilentlyContinue)) {
            if (-not (Get-Command cs -ErrorAction SilentlyContinue)) {
                Write-Host "  Installing Coursier..."
                scoop install coursier
                Refresh-Path
            }
            if (Get-Command cs -ErrorAction SilentlyContinue) {
                Write-Host "  Installing Metals LSP..."
                cs install metals 2>&1 | Out-Null
            } else {
                Write-Host "  Skipped Metals: coursier (cs) is not on PATH yet; run 'cs install metals' in a new terminal" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  metals already installed"
        }
    } catch { Write-Host "  Skipped Scala toolchain: $_" -ForegroundColor Yellow }

    # ─── Docker Desktop ─────────────────────────────────────
    Write-Host ""
    Write-Host "Checking Docker..."
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        $freeGB = Get-FreeGB
        if ($null -ne $freeGB -and $freeGB -lt 10) {
            Write-Host "  Skipped Docker Desktop: $freeGB GB free, its installer and images need about 10 GB (install later with: winget install Docker.DockerDesktop)" -ForegroundColor Yellow
        } else {
            Write-Host "  Installing Docker Desktop via winget..."
            winget install Docker.DockerDesktop --accept-package-agreements --accept-source-agreements --source winget
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Docker Desktop installed — restart may be required" -ForegroundColor Yellow
            } else {
                # winget refuses an installer whose hash changed upstream when elevated.
                Write-Host "  Docker Desktop not installed (winget exit $LASTEXITCODE, see above); download it from docker.com/products/docker-desktop" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  Docker already installed"
    }
} else {
    Write-Host "  Toolchains (Rust, Scala, Node, Go, Java) and Docker Desktop: run again with `$env:INSTALL_FULL = `"1`""
}

# ─── Backup existing configs ─────────────────────────────
Write-Host ""
$backupDir = "$env:USERPROFILE\.config\dotfiles-backup\$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$tmuxPath = "$env:USERPROFILE\.config\tmux"

# Backup PowerShell profile
if (Test-Path $PROFILE) {
    try {
        New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
        Copy-Item $PROFILE "$backupDir\profile.ps1" -ErrorAction Stop
    } catch {
        throw "Could not back up the PowerShell profile to $backupDir ($_); nothing was changed."
    }
    Write-Host "Backed up PowerShell profile to $backupDir\profile.ps1"
}

# ─── Clone configs ────────────────────────────────────────
Write-Host ""
Write-Host "Setting up configs..."

$repoBase = "https://github.com/irlm"

function Clone-OrPull {
    param($Repo, $Dest, $Name)
    $repoName = $Repo -replace '\.git$', ''
    # The workbench repository was irlm/tmux until November 2026; GitHub redirects the old name.
    $names = if ($repoName -eq "workbench") { @("workbench", "tmux") } else { @($repoName) }
    $managed = foreach ($n in $names) { "https://github.com/irlm/$n"; "https://github.com/irlm/$n.git"; "git@github.com:irlm/$n.git"; "ssh://git@github.com/irlm/$n.git" }
    if (Test-Path "$Dest\.git") {
        $remote = git -C $Dest remote get-url origin 2>$null
        if ($remote -in $managed) {
            git -C $Dest pull --ff-only
            if ($LASTEXITCODE -ne 0) { throw "Failed to update $Name; existing config preserved." }
            return
        }
    }
    $stage = "$Dest.stage.$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path (Split-Path $Dest) -Force | Out-Null
    git clone "$repoBase/$Repo" $stage
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        throw "Failed to clone $Name; existing config preserved."
    }
    $backup = $null
    if (Test-Path $Dest) {
        $backup = "$Dest.backup.$([guid]::NewGuid().ToString('N'))"
        Move-Item -LiteralPath $Dest -Destination $backup -ErrorAction Stop
        Write-Host "  Previous config saved to $backup"
    }
    try { Move-Item -LiteralPath $stage -Destination $Dest -ErrorAction Stop }
    catch {
        if ($backup) { Move-Item -LiteralPath $backup -Destination $Dest -ErrorAction Stop }
        throw
    }
}

if ($wantNvim) { Clone-OrPull -Repo "nvim.git" -Dest $nvimPath -Name "nvim" }

New-Item -ItemType Directory -Path "$env:USERPROFILE\.config" -Force | Out-Null
Clone-OrPull -Repo "workbench.git" -Dest $tmuxPath -Name "workbench"

# ─── Helix config ────────────────────────────────────────
# The repo's Helix config, with its commands handed to Git Bash so the review
# keys run the same scripts as on macOS and Linux.
$helixDir = Join-Path $env:APPDATA "helix"
$helixConfig = Join-Path $helixDir "config.toml"
$helixSource = Join-Path $tmuxPath "helix\config.toml"
if (Test-Path $helixSource) {
    New-Item -ItemType Directory -Path $helixDir -Force | Out-Null
    $existing = if (Test-Path $helixConfig) { Get-Content $helixConfig -Raw } else { "" }
    if ($existing -and $existing -notmatch "Managed by irlm/(workbench|tmux)") {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item $helixConfig "$backupDir\helix-config.toml"
        Write-Host "  Backed up your Helix config to $backupDir\"
    }
    $bashExe = $null
    foreach ($candidate in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe")) {
        if ($candidate -and (Test-Path $candidate)) { $bashExe = $candidate; break }
    }
    $rendered = Get-Content $helixSource -Raw
    if ($bashExe) {
        $shellLine = 'shell = ["' + ($bashExe -replace '\\', '\\') + '", "-c"]'
        $rendered = $rendered -replace '(?m)^\[editor\]\r?$', ("[editor]`n" + $shellLine)
    }
    [System.IO.File]::WriteAllText($helixConfig, $rendered, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  Helix config written to $helixConfig"
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

# fzf requires the PowerShell wrapper module, not just fzf.exe. A fresh
# Windows asks to install the NuGet provider and to trust the gallery first;
# answer both here so the step also works without a prompt.
if (-not (Get-Module -ListAvailable PSFzf)) {
    try {
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -Confirm:$false | Out-Null
        }
        if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        Install-Module PSFzf -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
    } catch { Write-Host "  PSFzf module not installed: $_  (run: Install-Module PSFzf -Scope CurrentUser)" -ForegroundColor Yellow }
}
if ($profileContent -notmatch "Set-PsFzfOption") {
    Add-Content $PROFILE @'

# fzf history and file selection
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
'@
}

# aliases
if ($profileContent -notmatch "lazygit") {
    Write-Host "  Adding aliases..."
    Add-Content $PROFILE "`n# ─── aliases ──────────────────────────────────────────"
    Add-Content $PROFILE "Set-Alias -Name lg -Value lazygit"
    Add-Content $PROFILE "Set-Alias -Name ld -Value lazydocker"
    Add-Content $PROFILE "Set-Alias -Name g -Value git"
    Add-Content $PROFILE "Set-Alias -Name vim -Value hx"
}
if ($profileContent -notmatch 'env:EDITOR') {
    Add-Content $PROFILE "`n# ─── editor (Helix; nvim when installed with INSTALL_NVIM=1) ───"
    Add-Content $PROFILE 'if (-not $env:EDITOR) { $env:EDITOR = "hx" }'
}

# ─── Herdr ───────────────────────────────────────────────
# Herdr (herdr.dev) is the desktop multiplexer: installed unless INSTALL_HERDR=0,
# then configured from this repo: same prefix and keys as tmux, the popups
# through Git Bash, the Claude and Codex integrations.
Write-Host ""
if (-not (Get-Command herdr -ErrorAction SilentlyContinue) -and $env:INSTALL_HERDR -ne "0") {
    Write-Host "Installing Herdr..."
    try { Invoke-Expression (Invoke-RestMethod https://herdr.dev/install.ps1) } catch { Write-Host "  Herdr install failed: $_" -ForegroundColor Yellow }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + $env:Path
}
if (Get-Command herdr -ErrorAction SilentlyContinue) {
    # An older Herdr rejects the rendered config (sidebar rows, worktrees),
    # which would leave it on its default ctrl+b prefix: update it first.
    $herdrVersion = ((herdr --version 2>$null) -replace '^herdr\s+', '') -replace '\s.*$', ''
    if ($herdrVersion -and ([version]$herdrVersion -lt [version]'0.9.5')) {
        Write-Host "  Herdr $herdrVersion is older than 0.9.5; updating..."
        herdr update *> $null
        Write-Host "  A Herdr that was already running keeps the old binary: detach (prefix q) and start herdr again." -ForegroundColor Yellow
    }
    Write-Host "Configuring Herdr from this repo..."
    # PowerShell 7 when present, else the Windows PowerShell every machine has.
    $ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    try {
        & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$tmuxPath\scripts\herdr-config.ps1"
        foreach ($agent in @("claude", "codex")) {
            if (Get-Command $agent -ErrorAction SilentlyContinue) { herdr integration install $agent *> $null; Write-Host "  Herdr integration: $agent" }
        }
        # Herdr's own skill for Claude Code, so a Claude in a Herdr pane can
        # drive helper agents. Only Herdr's copy is written or refreshed; a
        # file you edited is left alone.
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            $skillDir = Join-Path ($(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "$HOME\.claude" })) "skills\herdr"
            $skill = Join-Path $skillDir "SKILL.md"
            $fresh = (herdr --skill 2>$null) -join "`n"
            if ($fresh) {
                $write = -not (Test-Path $skill)
                if (-not $write) {
                    $current = (Get-Content $skill -Raw).TrimEnd("`r", "`n")
                    $write = ($current -ne $fresh) -and ($current -match 'Control Herdr, a terminal multiplexer')
                }
                if ($write) {
                    New-Item -ItemType Directory -Force $skillDir | Out-Null
                    [System.IO.File]::WriteAllText($skill, $fresh + "`n", (New-Object System.Text.UTF8Encoding $false))
                    Write-Host "  Herdr skill for Claude Code: $skill"
                }
            }
        }
    } catch { Write-Host "  Herdr setup incomplete: $_  (rerun: $ps $tmuxPath\scripts\herdr-config.ps1)" -ForegroundColor Yellow }
} else {
    Write-Host "Herdr not installed (INSTALL_HERDR=0, or its installer failed). Rerun without it, or see https://herdr.dev"
}

# ─── Done ─────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Install complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal"
Write-Host "  2. Windows Terminal's default font is JetBrainsMono Nerd Font (set here unless it had one); other terminals: pick it in their settings"
if ($wantFull) { Write-Host "  3. Launch Docker Desktop" }
Write-Host "  4. Edit with hx (Helix, configured from this repo; hx --tutor teaches the keys)"
if ($wantNvim) { Write-Host "     Or nvim (plugins + LSPs auto-install on first launch)" }
Write-Host "  5. Run: lazygit, lazydocker, btop, fastfetch"
Write-Host "  6. For tmux: install WSL ('wsl --install' in admin PowerShell)"
if (Get-Command herdr -ErrorAction SilentlyContinue) { Write-Host "  7. Run: herdr (same keys as tmux, agent sidebar; docs\herdr.md)" }
Write-Host ""
Write-Host "What was installed:" -ForegroundColor Cyan
Write-Host "  Editor:      Helix (hx) with this repo's review keys$(if ($wantNvim) { '; Neovim (LazyVim) too' })"
if ($wantFull) { Write-Host "  Dev tools:   Rust, Go, Python, Node.js, Java, Scala (Metals)" }
Write-Host "  Git:         lazygit, gh (GitHub CLI)"
Write-Host "  Containers:  $(if ($wantFull) { 'Docker Desktop, ' })lazydocker"
if (-not $wantFull) { Write-Host "  Toolchains and Docker Desktop: `$env:INSTALL_FULL = `"1`" before the install command" }
Write-Host "  CLI:         fzf, zoxide, bat, btop, fastfetch, oh-my-posh"
Write-Host "  Fonts:       JetBrains Mono Nerd Font, MesloLGM Nerd Font"
Write-Host ""
