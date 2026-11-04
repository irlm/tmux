#!/usr/bin/env bash
# Update configs/plugins and report every failed component.
set -uo pipefail
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="" SSH_ASKPASS=""
TMUX_DIR="${TMUX_CONFIG_DIR:-$HOME/.config/tmux}"
NVIM_DIR="${NVIM_CONFIG_DIR:-$HOME/.config/nvim}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MODE=full; AUTO_FIX=0
for arg in "$@"; do
    case "$arg" in
        --quick|-q) MODE=quick ;;
        --check|-c) MODE=check ;;
        --fix|-f) AUTO_FIX=1 ;;
        --help|-h)
            printf '%s\n' 'update.sh [--quick | --check] [--fix]' \
                '  default: repos, tmux/Neovim plugins, gh extensions, managed brew upgrades' \
                '  --quick: repos and plugins (including Neovim); skip package upgrades' \
                '  --check: read-only repository and environment diagnostics' \
                '  --fix: repair missing required tools after updating'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
failures=0
failed() { printf '  FAILED: %s\n' "$*" >&2; failures=$((failures + 1)); }
update_repo() {
    local name=$1 dir=$2 remote head changes
    printf '\n── %s ──\n' "$name"
    if [ ! -d "$dir/.git" ] && [ ! -f "$dir/.git" ]; then failed "$name repo missing — run install.sh"; return; fi
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || { failed "$name has no origin remote"; return; }
    case "${remote%.git}" in
        "https://github.com/irlm/$name"|"git@github.com:irlm/$name"|"ssh://git@github.com/irlm/$name") ;;
        *) failed "$dir has a custom origin; update it manually"; return ;;
    esac
    if [ "$MODE" = check ]; then
        head=$(git -C "$dir" -c http.lowSpeedLimit=100 -c http.lowSpeedTime=15 ls-remote origin refs/heads/main 2>/dev/null) || {
            failed "Cannot check $name origin"; return;
        }
        head=${head%%$'\t'*}
        if [ -z "$head" ]; then failed "$name origin has no main branch";
        elif [ "$(git -C "$dir" rev-parse HEAD)" = "$head" ]; then echo '  Up to date.';
        else printf '  Update available or local history differs; run dotup in %s.\n' "$dir"; fi
    else
        if [ "$name" = nvim ]; then
            changes=$(git -C "$dir" status --porcelain --untracked-files=normal) || {
                failed "$name status; existing files preserved"; return;
            }
            case "$changes" in
                ' M lazy-lock.json'|'M  lazy-lock.json'|'MM lazy-lock.json')
                    # Lazy sync rewrites this generated file. Keep both its index
                    # and working versions in Git before taking upstream's lock.
                    if ! git -C "$dir" stash push -m "dotup: generated Neovim lock $(date -u +%Y%m%dT%H%M%SZ)" -- lazy-lock.json; then
                        failed "$name lock backup; existing files preserved"; return
                    fi
                    printf '  Backed up generated Neovim lock in its Git stash.\n'
                    ;;
            esac
        fi
        # All other local edits retain normal Git merge protection.
        git -C "$dir" -c http.lowSpeedLimit=100 -c http.lowSpeedTime=15 pull --ff-only origin main || failed "$name pull; resolve local changes in $dir"
    fi
}

# Re-exec the installed updater after a successful self-update, including curl use.
before=$(cksum "$TMUX_DIR/update.sh" 2>/dev/null) || before=""
update_repo tmux "$TMUX_DIR"
after=$(cksum "$TMUX_DIR/update.sh" 2>/dev/null) || after=""
if [ "$MODE" != check ] && [ "$failures" -eq 0 ] && [ -z "${DOTFILES_UPDATE_REEXEC:-}" ] &&
   { { [ "$SELF" = "$TMUX_DIR/update.sh" ] && [ "$before" != "$after" ]; } || [ ! -f "$0" ]; } &&
   [ -f "$TMUX_DIR/update.sh" ]; then
    DOTFILES_UPDATE_REEXEC=1 exec bash "$TMUX_DIR/update.sh" "$@"
fi
# A dev checkout may be used to repair an older installed copy.
ASSET_DIR=${SELF%/*}
[ -f "$ASSET_DIR/scripts/lib.sh" ] || ASSET_DIR="$TMUX_DIR"
# shellcheck source=scripts/lib.sh
source "$ASSET_DIR/scripts/lib.sh"
export TMUX_CONFIG_DIR="$TMUX_DIR"
for path in "$HOME/.local/bin" "$HOME/.cargo/bin" /opt/homebrew/bin /usr/local/bin \
    /opt/homebrew/opt/openjdk/bin /usr/local/opt/openjdk/bin \
    "$HOME/Library/Application Support/Coursier/bin" "$HOME/.local/share/coursier/bin"; do
    if [ -d "$path" ]; then
        case ":$PATH:" in *":$path:"*) ;; *) PATH="$PATH:$path" ;; esac
    fi
done
export PATH
profile=desktop
[ ! -f "$NVIM_DIR/.server" ] || profile=server
nvim_repo_ready=0
if [ -f "$NVIM_DIR/init.lua" ]; then
    # Neovim is the optional second editor: only an existing checkout is updated.
    before_nvim=$failures
    update_repo nvim "$NVIM_DIR"
    [ "$failures" -ne "$before_nvim" ] || nvim_repo_ready=1
fi

if [ "$MODE" = check ]; then
    "$ASSET_DIR/scripts/doctor.sh" || failed 'environment health check'
    [ "$failures" -eq 0 ] || exit 1
    echo 'Check complete (nothing changed).'
    exit 0
fi
private_dir "$TMUX_DATA_DIR" || exit 1
LOG_DIR="$TMUX_DATA_DIR/update-logs"
private_dir "$LOG_DIR" || exit 1
# shellcheck source=scripts/install-lib.sh
source "$ASSET_DIR/scripts/install-lib.sh"
printf '\n── Helix ──\n'
if install_helix_config "$ASSET_DIR/helix/config.toml"; then echo '  OK: config linked'; else failed 'Helix config link'; fi
# The managed shell file is generated; regenerate it so new defaults (EDITOR,
# tool paths) reach existing installs. Personal rc files only get the include.
managed_shell="$HOME/.config/tmux-user/shell.$(install_target_shell 2>/dev/null || echo none)"
if [ -f "$managed_shell" ]; then
    printf '\n── Shell integration ──\n'
    shell_profile=$(sed -n 's/^__TMUX_SHELL_ENV_LOADED=//p' "$managed_shell" | head -1)
    case "$shell_profile" in desktop|server|full) ;; *) shell_profile=$profile ;; esac
    if install_shell_integration "$shell_profile" >/dev/null; then echo "  OK: managed shell file ($shell_profile)"; else failed 'shell integration refresh'; fi
fi
run_logged() {
    local name=$1; shift
    if "$@" > "$LOG_DIR/$name.log" 2>&1; then printf '  OK: %s\n' "$name";
    else failed "$name (log: $LOG_DIR/$name.log)"; fi
}
printf '\n── tmux plugins ──\n'
TPM_DIR="$TMUX_DIR/plugins/tpm"
if [ ! -x "$TPM_DIR/tpm" ]; then
    mkdir -p "$TMUX_DIR/plugins"
    run_logged tpm-clone git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
for action in install_plugins update_plugins clean_plugins; do
    if [ ! -x "$TPM_DIR/bin/$action" ]; then failed "$action unavailable — install TPM"; continue; fi
    args=(); [ "$action" != update_plugins ] || args=(all)
    run_logged "tmux-$action" "$TPM_DIR/bin/$action" ${args[@]+"${args[@]}"}
done
if tmux list-sessions >/dev/null 2>&1; then
    run_logged tmux-reload tmux source-file "$TMUX_DIR/tmux.conf"
fi
if [ -f "$NVIM_DIR/init.lua" ] && command -v nvim >/dev/null 2>&1; then
    if [ "$nvim_repo_ready" -eq 1 ]; then
        run_logged nvim-plugins nvim --headless '+Lazy! sync' +qa
        if grep -F 'You have local changes' "$LOG_DIR/nvim-plugins.log" >/dev/null; then
            failed "Neovim plugins have local changes (log: $LOG_DIR/nvim-plugins.log)"
        fi
    else
        printf '  SKIP: nvim-plugins (repository update failed)\n'
    fi
fi
# Only an installed checkout that ships the Herdr template refreshes a config
# this repo generated; a hand-written Herdr config is left alone.
if [ -f "$TMUX_DIR/herdr/config.toml" ] && command -v herdr >/dev/null 2>&1 &&
   head -3 "${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}" 2>/dev/null | grep -F 'Generated by irlm/tmux' >/dev/null; then
    printf '\n── Herdr ──\n'
    run_logged herdr-config bash "$ASSET_DIR/scripts/herdr-config.sh"
    [ "$MODE" != full ] || run_logged herdr-update herdr update
fi
if [ "$profile" != server ] && command -v gh >/dev/null 2>&1; then
    if gh extension list 2>/dev/null | grep -F 'dlvhdr/gh-dash' >/dev/null; then
        run_logged gh-extensions gh extension upgrade --all
    else run_logged gh-dash gh extension install dlvhdr/gh-dash; fi
fi
if [ "$MODE" = full ] && command -v brew >/dev/null 2>&1; then
    run_logged brew-update brew update --quiet
    outdated=$(brew outdated --quiet) || { failed 'brew outdated'; outdated=""; }
    packages=()
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if brew_tools "$profile" | grep -Fx "$pkg" >/dev/null; then packages+=("$pkg"); fi
    done <<< "$outdated"
    [ "${#packages[@]}" -eq 0 ] || run_logged brew-upgrade brew upgrade "${packages[@]}"
fi
missing=""
while IFS= read -r tool; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done < <(managed_tools "$profile")
if [ -n "$missing" ]; then
    printf 'Required tools missing:%s\n' "$missing"
    answer=n
    if [ "$AUTO_FIX" -eq 1 ]; then answer=y;
    elif [ -t 0 ]; then read -rp 'Repair missing tools now? [y/N] ' answer; fi
    case "$answer" in
        y|Y) args=(); [ "$profile" != server ] || args=(--server)
            run_logged repair bash "$TMUX_DIR/install.sh" ${args[@]+"${args[@]}"} ;;
        *) failed 'missing required tools; run update.sh --fix' ;;
    esac
fi
"$ASSET_DIR/scripts/doctor.sh" || failed 'environment health check'
if [ "$failures" -gt 0 ]; then
    printf '\nUpdate incomplete: %s component(s) failed. Logs: %s\n' "$failures" "$LOG_DIR"
    exit 1
fi
printf '\nAll requested updates and required health checks passed. Logs: %s\n' "$LOG_DIR"
