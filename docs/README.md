# Documentation

This folder contains the full documentation for the workbench: Herdr on the desktop, tmux on servers, Helix as the editor, one set of keys across them.

The root [`README.md`](../README.md) is the quick-start version. Use the guides here when you want the full picture.

## Start Here

- [Installation guide](installation.md): install modes, platform notes, first-run checklist, and updating
- [Herdr](herdr.md): the desktop multiplexer; what the installer sets up, its keys beside the shared ones, the agent sidebar, the LLM usage popup
- [Usage and keybindings](usage.md): the shared keys, popups, panes and sessions, working on servers over SSH, copy mode, the editor keys, and shell aliases
- [Features and project layout](features.md): what the project includes, how the status bar fits together, and which files do what
- [Customization and diagnostics](customization.md): profiles, local overrides, command palette, health checks, and development checks

## Project Summary

This repo owns the Herdr and tmux configuration, the Helix config, the shell integration, the helper scripts and the installers. It pairs optionally with the separate [irlm/nvim](https://github.com/irlm/nvim) repo for the Neovim configuration.

If you are new to the project, the best path is:

1. Read the root [`README.md`](../README.md)
2. Follow the [installation guide](installation.md)
3. Read the [Herdr guide](herdr.md) once, then keep the [usage guide](usage.md) open for the first few sessions
