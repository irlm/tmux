# ─── Tmux-like Shell Bootstrap for Windows ──────────────
# Run in PowerShell (Admin recommended):
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#   .\setup-windows.ps1
#
# Requires: Windows 10/11 with Windows Terminal + winget
# ─────────────────────────────────────────────────────────
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ─── Colors & Logging ──────────────────────────────────
function Info  { param($m) Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $m }
function Ok    { param($m) Write-Host "[OK]   " -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn  { param($m) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Err   { param($m) Write-Host "[ERR]  " -ForegroundColor Red -NoNewline; Write-Host $m }

# ─── Ensure winget is available ────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err "winget not found. Install 'App Installer' from the Microsoft Store."
    exit 1
}
Ok "winget available"

# ─── Install packages via winget ───────────────────────
$Packages = @(
    @{ Id = "JanDeDobbeleer.OhMyPosh";    Name = "Oh My Posh"   }
    @{ Id = "junegunn.fzf";               Name = "fzf"          }
    @{ Id = "JesseDuffield.lazygit";       Name = "lazygit"      }
    @{ Id = "aristocratos.btop4win";       Name = "btop"         }
    @{ Id = "Fastfetch-cli.Fastfetch";     Name = "fastfetch"    }
    @{ Id = "GitHub.cli";                  Name = "gh"           }
    @{ Id = "BurntSushi.ripgrep.MSVC";     Name = "ripgrep"      }
    @{ Id = "sharkdp.fd";                  Name = "fd"           }
    @{ Id = "sharkdp.bat";                 Name = "bat"          }
    @{ Id = "eza-community.eza";           Name = "eza"          }
    @{ Id = "ajeetdsouza.zoxide";          Name = "zoxide"       }
    @{ Id = "stedolan.jq";                 Name = "jq"           }
    @{ Id = "tldr-pages.tlrc";             Name = "tlrc"         }
    @{ Id = "Neovim.Neovim";              Name = "neovim"       }
)

Info "Installing packages..."
foreach ($pkg in $Packages) {
    $installed = winget list --id $pkg.Id --accept-source-agreements 2>$null | Select-String $pkg.Id
    if ($installed) {
        Ok "$($pkg.Name) already installed"
    } else {
        Info "Installing $($pkg.Name)..."
        winget install --id $pkg.Id --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -eq 0) { Ok "$($pkg.Name) installed" }
        else { Warn "Failed to install $($pkg.Name) — install manually" }
    }
}

# ─── Nerd Font ─────────────────────────────────────────
$FontName = "JetBrainsMono"
$FontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$FontExists = Get-ChildItem $FontDir -Filter "*JetBrains*Nerd*" -ErrorAction SilentlyContinue

if ($FontExists) {
    Ok "Nerd Font already installed"
} else {
    Info "Installing JetBrains Mono Nerd Font..."
    $FontVersion = "v3.3.0"
    $FontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/$FontVersion/JetBrainsMono.zip"
    $FontZip = "$env:TEMP\JetBrainsMono.zip"
    $FontExtract = "$env:TEMP\JetBrainsMono"

    Invoke-WebRequest -Uri $FontUrl -OutFile $FontZip -UseBasicParsing
    Expand-Archive -Path $FontZip -DestinationPath $FontExtract -Force

    # Install fonts for current user
    $ShellApp = New-Object -ComObject Shell.Application
    $FontsFolder = $ShellApp.NameSpace(0x14)  # Windows Fonts folder

    Get-ChildItem "$FontExtract\*.ttf" | ForEach-Object {
        if (-not (Test-Path "$FontDir\$($_.Name)")) {
            Copy-Item $_.FullName $FontDir -Force
            # Register the font
            $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
            New-ItemProperty -Path $RegPath -Name $_.BaseName -Value $_.FullName -Force | Out-Null
        }
    }

    Remove-Item $FontZip, $FontExtract -Recurse -Force -ErrorAction SilentlyContinue
    Ok "Nerd Font installed"
    Warn "You may need to restart Windows Terminal for the font to appear"
}

# ─── Oh My Posh theme ─────────────────────────────────
$OmpThemeDir = "$env:USERPROFILE\.config\tmux"
if (-not (Test-Path $OmpThemeDir)) { New-Item -ItemType Directory -Path $OmpThemeDir -Force | Out-Null }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ThemeFiles = @("nord.omp.json", "catppuccin.omp.json")
foreach ($theme in $ThemeFiles) {
    $src = Join-Path $ScriptDir $theme
    $dst = Join-Path $OmpThemeDir $theme
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Ok "$theme installed"
    }
}

# ─── Windows Terminal settings ─────────────────────────
# Keybindings mapped from tmux C-a prefix to Alt-based shortcuts
$WtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
# Also check for non-Store version
if (-not (Test-Path $WtSettingsPath)) {
    $WtSettingsPath = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
}

if (Test-Path $WtSettingsPath) {
    Info "Configuring Windows Terminal..."

    # Backup existing settings
    $BackupPath = "$WtSettingsPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $WtSettingsPath $BackupPath
    Ok "Backed up settings to $BackupPath"

    $settings = Get-Content $WtSettingsPath -Raw | ConvertFrom-Json

    # ── Nord color scheme ──
    $nordScheme = @{
        name        = "Nord"
        background  = "#2E3440"
        foreground  = "#D8DEE9"
        cursorColor = "#D8DEE9"
        selectionBackground = "#434C5E"
        black       = "#3B4252"; brightBlack   = "#4C566A"
        red         = "#BF616A"; brightRed     = "#BF616A"
        green       = "#A3BE8C"; brightGreen   = "#A3BE8C"
        yellow      = "#EBCB8B"; brightYellow  = "#EBCB8B"
        blue        = "#81A1C1"; brightBlue    = "#81A1C1"
        purple      = "#B48EAD"; brightPurple  = "#B48EAD"
        cyan        = "#88C0D0"; brightCyan    = "#8FBCBB"
        white       = "#E5E9F0"; brightWhite   = "#ECEFF4"
    }

    # Add/update Nord scheme
    if (-not $settings.schemes) { $settings | Add-Member -NotePropertyName "schemes" -NotePropertyValue @() }
    $existingNord = $settings.schemes | Where-Object { $_.name -eq "Nord" }
    if ($existingNord) {
        $idx = [array]::IndexOf($settings.schemes, $existingNord)
        $settings.schemes[$idx] = [PSCustomObject]$nordScheme
    } else {
        $settings.schemes += [PSCustomObject]$nordScheme
    }

    # ── Default profile settings ──
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue @{} -Force
    }
    $defaults = $settings.profiles.defaults
    # Set as PSCustomObject properties
    $defaultProps = @{
        colorScheme = "Nord"
        font        = @{
            face = "JetBrainsMono Nerd Font"
            size = 12
        }
        cursorShape   = "bar"
        padding       = "8"
        opacity       = 90
        useAcrylic    = $false
    }
    foreach ($key in $defaultProps.Keys) {
        if ($defaults -is [PSCustomObject]) {
            if ($defaults.PSObject.Properties[$key]) {
                $defaults.$key = $defaultProps[$key]
            } else {
                $defaults | Add-Member -NotePropertyName $key -NotePropertyValue $defaultProps[$key] -Force
            }
        }
    }

    # ── Keybindings (tmux-like with Alt as modifier) ──
    # Maps tmux C-a <key> to Alt+<key> in Windows Terminal
    $keybindings = @(
        # ── Splits (tmux: C-a | and C-a -) ──
        @{ command = @{ action = "splitPane"; split = "horizontal"; splitMode = "duplicate" }; keys = "alt+shift+\\" }
        @{ command = @{ action = "splitPane"; split = "vertical";   splitMode = "duplicate" }; keys = "alt+-" }

        # ── Pane navigation (tmux: C-a h/j/k/l) ──
        @{ command = @{ action = "moveFocus"; direction = "left"  }; keys = "alt+h" }
        @{ command = @{ action = "moveFocus"; direction = "down"  }; keys = "alt+j" }
        @{ command = @{ action = "moveFocus"; direction = "up"    }; keys = "alt+k" }
        @{ command = @{ action = "moveFocus"; direction = "right" }; keys = "alt+l" }

        # ── Pane resizing (tmux: C-a H/J/K/L) ──
        @{ command = @{ action = "resizePane"; direction = "left"  }; keys = "alt+shift+h" }
        @{ command = @{ action = "resizePane"; direction = "down"  }; keys = "alt+shift+j" }
        @{ command = @{ action = "resizePane"; direction = "up"    }; keys = "alt+shift+k" }
        @{ command = @{ action = "resizePane"; direction = "right" }; keys = "alt+shift+l" }

        # ── Pane actions (tmux: C-a x, C-a z) ──
        @{ command = "closePane";       keys = "alt+x" }
        @{ command = "togglePaneZoom";  keys = "alt+z" }

        # ── Tabs (tmux: C-a c, C-a X) ──
        @{ command = @{ action = "newTab" };  keys = "alt+c" }
        @{ command = "closeTab";              keys = "alt+shift+x" }

        # ── Tab navigation (tmux: C-a <n>) ──
        @{ command = @{ action = "switchToTab"; index = 0 }; keys = "alt+1" }
        @{ command = @{ action = "switchToTab"; index = 1 }; keys = "alt+2" }
        @{ command = @{ action = "switchToTab"; index = 2 }; keys = "alt+3" }
        @{ command = @{ action = "switchToTab"; index = 3 }; keys = "alt+4" }
        @{ command = @{ action = "switchToTab"; index = 4 }; keys = "alt+5" }
        @{ command = @{ action = "switchToTab"; index = 5 }; keys = "alt+6" }
        @{ command = @{ action = "switchToTab"; index = 6 }; keys = "alt+7" }
        @{ command = @{ action = "switchToTab"; index = 7 }; keys = "alt+8" }
        @{ command = @{ action = "switchToTab"; index = 8 }; keys = "alt+9" }

        # ── Tab reorder (tmux: C-a < and C-a >) ──
        @{ command = @{ action = "moveTab"; direction = "backward" }; keys = "alt+shift+," }
        @{ command = @{ action = "moveTab"; direction = "forward"  }; keys = "alt+shift+." }

        # ── Quick tools (tmux popups: C-a g/t/i) ──
        @{ command = @{ action = "newTab"; commandline = "lazygit";   tabTitle = "lazygit"   }; keys = "alt+g" }
        @{ command = @{ action = "newTab"; commandline = "btop";      tabTitle = "btop"      }; keys = "alt+t" }
        @{ command = @{ action = "newTab"; commandline = "fastfetch"; tabTitle = "fastfetch" }; keys = "alt+i" }
        @{ command = @{ action = "newTab"; commandline = "gh dash";   tabTitle = "gh dash"   }; keys = "alt+shift+g" }

        # ── Search (tmux: C-a /) ──
        @{ command = "find"; keys = "alt+/" }

        # ── Rename tab (tmux: C-a ,) ──
        @{ command = @{ action = "renameTab" }; keys = "alt+," }

        # ── Scrollback / copy mode ──
        @{ command = "scrollUpPage";   keys = "alt+[" }
        @{ command = "scrollDownPage"; keys = "alt+]" }
    )

    # Convert to PSCustomObject array
    $actions = @()
    foreach ($kb in $keybindings) {
        $actions += [PSCustomObject]$kb
    }

    # Set keybindings (use "actions" for newer WT versions)
    if ($settings.PSObject.Properties["actions"]) {
        $settings.actions = $actions
    } else {
        $settings | Add-Member -NotePropertyName "actions" -NotePropertyValue $actions -Force
    }

    # Save settings
    $settings | ConvertTo-Json -Depth 10 | Set-Content $WtSettingsPath -Encoding UTF8
    Ok "Windows Terminal configured with Nord theme + keybindings"
} else {
    Warn "Windows Terminal settings not found — install Windows Terminal first"
    Warn "Then re-run this script to configure keybindings"
}

# ─── PowerShell Profile ───────────────────────────────
$ProfileDir = Split-Path $PROFILE
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null }

# Backup existing profile
if (Test-Path $PROFILE) {
    $ProfBackup = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $PROFILE $ProfBackup
    Ok "Backed up existing profile to $ProfBackup"
}

Info "Configuring PowerShell profile..."

$ProfileContent = @'
# ─── Oh My Posh prompt ──────────────────────────────────
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "$env:USERPROFILE\.config\tmux\nord.omp.json" | Invoke-Expression
}

# ─── PSReadLine (vi mode + better history) ──────────────
if (Get-Module -ListAvailable PSReadLine) {
    Set-PSReadLineOption -EditMode Vi
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Chord Ctrl+r -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -Chord Ctrl+f -Function ForwardSearchHistory
}

# ─── fzf integration ────────────────────────────────────
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    # Set fzf Nord colors
    $env:FZF_DEFAULT_OPTS = "--color=fg:#d8dee9,bg:#2e3440,hl:#88c0d0 --color=fg+:#eceff4,bg+:#434c5e,hl+:#5e81ac --color=info:#ebcb8b,prompt:#81a1c1,pointer:#bf616a --color=marker:#a3be8c,spinner:#b48ead,header:#88c0d0"

    # Install PSFzf module if missing
    if (-not (Get-Module -ListAvailable PSFzf)) {
        Install-Module PSFzf -Scope CurrentUser -Force -SkipPublisherCheck
    }
    if (Get-Module -ListAvailable PSFzf) {
        Import-Module PSFzf
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    }
}

# ─── zoxide (smart cd) ──────────────────────────────────
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ─── Modern CLI aliases ─────────────────────────────────
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls  { eza --icons @args }
    function ll  { eza -la --icons --git @args }
    function tree { eza --tree --icons @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat --style=plain @args }
}

# ─── Git aliases ─────────────────────────────────────────
function gs  { git status @args }
function gl  { git log --oneline --graph --decorate -20 @args }
function gp  { git push @args }
function gpl { git pull @args }

if (Get-Command lazygit -ErrorAction SilentlyContinue) {
    Set-Alias lg lazygit
}

if (Get-Command tlrc -ErrorAction SilentlyContinue) {
    Set-Alias tl tlrc
}

# ─── Fastfetch greeting ─────────────────────────────────
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch -l small --structure Title:OS:Host:Kernel:Shell:Terminal:CPU:Memory
}
'@

Set-Content -Path $PROFILE -Value $ProfileContent -Encoding UTF8
Ok "PowerShell profile configured at $PROFILE"

# ─── PSFzf module ─────────────────────────────────────
if (-not (Get-Module -ListAvailable PSFzf -ErrorAction SilentlyContinue)) {
    Info "Installing PSFzf module..."
    Install-Module PSFzf -Scope CurrentUser -Force -SkipPublisherCheck
    Ok "PSFzf installed"
}

# ─── Cheatsheet ───────────────────────────────────────
$CheatsheetPath = "$env:USERPROFILE\.config\tmux\cheatsheet-windows.txt"
$CheatsheetContent = @'
CHEATSHEET v3.0.0 (Windows Terminal)
─────────────────────────────────────────────────────────────────
SPLITS                 PANES                  TABS
 Alt+Shift+\  horiz    Alt+h  focus left      Alt+c      new tab
 Alt+-         vert    Alt+j  focus down      Alt+,      rename
                       Alt+k  focus up        Alt+Shift+X kill tab
RESIZE                 Alt+l  focus right     Alt+1-9    switch
 Alt+Shift+H  left    Alt+x  close pane      Alt+Shift+< reorder
 Alt+Shift+J  down    Alt+z  zoom pane       Alt+Shift+> reorder
 Alt+Shift+K  up
 Alt+Shift+L  right   QUICK TOOLS            SCROLLBACK
                       Alt+g  lazygit          Alt+[  page up
SEARCH                 Alt+Shift+G gh dash    Alt+]  page down
 Alt+/  find           Alt+t  btop            Ctrl+Shift+F search
                       Alt+i  fastfetch

SHELL (PowerShell)     GIT ALIASES            FZF
 z      smart cd       gs   status            Ctrl+r  history
 cat    bat            gl   log graph         Ctrl+t  files
 ls     eza            gp   push
 ll     eza -la        gpl  pull
 lg     lazygit        tl   tldr
─────────────────────────────────────────────────────────────────
TMUX KEYBIND MAPPING:  C-a <key>  →  Alt+<key>
'@

Set-Content -Path $CheatsheetPath -Value $CheatsheetContent -Encoding UTF8
Ok "Cheatsheet saved to $CheatsheetPath"

# ─── Done ──────────────────────────────────────────────
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host " Setup complete! (Windows)" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:"
Write-Host "  1. Restart Windows Terminal"
Write-Host "  2. Font should auto-apply (JetBrains Mono Nerd Font)"
Write-Host "  3. Open a new tab to see the Oh My Posh prompt"
Write-Host ""
Write-Host "  Keybinding cheat:"
Write-Host "    Alt+h/j/k/l         navigate panes (like tmux C-a h/j/k/l)"
Write-Host "    Alt+Shift+H/J/K/L   resize panes   (like tmux C-a H/J/K/L)"
Write-Host "    Alt+Shift+\          split horiz    (like tmux C-a |)"
Write-Host "    Alt+-                split vert     (like tmux C-a -)"
Write-Host "    Alt+x               close pane      (like tmux C-a x)"
Write-Host "    Alt+z               zoom pane       (like tmux C-a z)"
Write-Host "    Alt+c               new tab         (like tmux C-a c)"
Write-Host "    Alt+g               lazygit         (like tmux C-a g)"
Write-Host "    Alt+t               btop            (like tmux C-a t)"
Write-Host "    Alt+1-9             switch tab      (like tmux C-a 1-9)"
Write-Host ""
Write-Host "  What you got:"
Write-Host "    - Oh My Posh prompt with Nord theme"
Write-Host "    - Windows Terminal with Nord colors + tmux-like keybindings"
Write-Host "    - PSReadLine vi mode + prediction"
Write-Host "    - fzf (Ctrl+r history, Ctrl+t files)"
Write-Host "    - lazygit, btop, gh, fastfetch"
Write-Host "    - eza/bat/zoxide replacing ls/cat/cd"
Write-Host "    - tlrc (quick man pages), jq (JSON)"
Write-Host ""
