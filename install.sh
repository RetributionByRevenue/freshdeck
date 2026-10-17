#!/usr/bin/env bash
set -euo pipefail
# Installer for freshdeck: a Claude Code IDE layout for the fresh editor.
# Copies launcher + watcher to ~/.local/bin and init.ts to ~/.config/fresh/.

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
fresh_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fresh"
own_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/freshdeck"

# ── dependency checks ────────────────────────────────────────────────────
missing=0
need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "MISSING: $1 — $2"
		missing=1
	fi
}
if [[ "$(uname -s)" == Darwin ]]; then
	need fresh "brew install fresh-editor (or https://getfresh.dev)"
	need fswatch "brew install fswatch"
	need python3 "xcode-select --install"
else
	need fresh "grab a build from https://github.com/sinelaw/fresh/releases (tar.xz/AppImage/rpm) or: cargo install fresh-editor"
	need fswatch "apt install fswatch / dnf install fswatch / pacman -S fswatch"
	need python3 "apt install python3 / dnf install python3 / pacman -S python"
	need ps "apt install procps / dnf install procps-ng"
fi
need claude "install Claude Code: https://claude.com/claude-code"
if [[ "$missing" -eq 1 ]]; then
	echo "Install the missing dependencies and re-run." >&2
	exit 1
fi

fresh_version="$(fresh --version | awk '{print $2}')"
case "$fresh_version" in
	0.5.*) ;;
	*) echo "WARNING: tested against fresh 0.5.x, you have $fresh_version — the plugin API may have changed." ;;
esac

# ── scripts ──────────────────────────────────────────────────────────────
mkdir -p "$bin_dir"
install -m 0755 "$repo_dir/bin/freshdeck" "$bin_dir/freshdeck"
install -m 0755 "$repo_dir/bin/freshdeck-watch" "$bin_dir/freshdeck-watch"
echo "Installed freshdeck and freshdeck-watch to $bin_dir"
case ":$PATH:" in
	*":$bin_dir:"*) ;;
	*) echo "NOTE: $bin_dir is not in your PATH — add it to your shell profile." ;;
esac

# ── init.ts ──────────────────────────────────────────────────────────────
mkdir -p "$fresh_config_dir"
target="$fresh_config_dir/init.ts"
if [[ -f "$target" ]] && ! cmp -s "$repo_dir/init.ts" "$target"; then
	backup="$target.bak.$(date +%Y%m%d%H%M%S)"
	cp "$target" "$backup"
	echo "Existing init.ts backed up to $backup"
	echo "NOTE: if it contained your own startup code, merge it back in manually."
fi
cp "$repo_dir/init.ts" "$target"
fresh --cmd init check
echo "Installed $target"

# ── default workspace (optional) ─────────────────────────────────────────
workspace="${FRESHDECK_WORKSPACE:-}"
if [[ -z "$workspace" && -t 0 ]]; then
	printf 'Default workspace dir for `freshdeck` with no argument (empty = current dir at launch): '
	read -r workspace
fi
if [[ -n "$workspace" ]]; then
	mkdir -p "$own_config_dir"
	printf '%s\n' "${workspace/#\~/$HOME}" > "$own_config_dir/workspace"
	echo "Default workspace saved to $own_config_dir/workspace"
fi

echo
echo "Done. Launch with: freshdeck [workspace-dir]"
if [[ "$(uname -s)" == Darwin ]]; then
	echo "macOS new-window:  open -na Ghostty --args -e freshdeck"
else
	echo "Linux new-window:  x-terminal-emulator -e freshdeck   (or: ghostty -e / gnome-terminal -- / kitty)"
	# inotify: fswatch -r takes one watch per directory; big trees can hit the
	# per-user cap and silently stop reporting changes.
	watches="$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
	if [[ "$watches" -lt 65536 ]]; then
		echo "NOTE: fs.inotify.max_user_watches=$watches — raise it for big repos:"
		echo "      echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/60-freshdeck.conf && sudo sysctl --system"
	fi
fi
