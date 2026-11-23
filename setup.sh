#!/usr/bin/env bash
# Applies the steps in README.md (same numbering). Safe to re-run.
# Run as your normal user from a terminal in the GNOME session, not with sudo.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not root. It calls sudo where needed." >&2
  exit 1
fi

current_step="start"
step() { current_step=$*; printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# Any failure stops the script, so say loudly where it stopped.
trap 'rc=$?; if (( rc )); then printf "\n\033[1;31msetup.sh stopped during \"%s\" (exit %s). Later steps did not run. Fix the error above and re-run.\033[0m\n" "$current_step" "$rc" >&2; fi' EXIT

# ---------------------------------------------------------------------------
step "1. Base tools: curl, git"
sudo apt update
sudo apt install -y curl git

# ---------------------------------------------------------------------------
step "2. Claude Code"
if [[ -x "$HOME/.local/bin/claude" ]]; then
  echo "Already installed: $("$HOME/.local/bin/claude" --version)"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

path_line='export PATH="$HOME/.local/bin:$PATH"'
grep -qxF "$path_line" "$HOME/.bashrc" || echo "$path_line" >> "$HOME/.bashrc"

# ---------------------------------------------------------------------------
step "3. Remove snap (Firefox moves to Mozilla's apt repo)"

# 3a. Mozilla's apt repo, pinned above Ubuntu's snap-wrapper 'firefox' package
mozilla_key=/etc/apt/keyrings/packages.mozilla.org.asc
mozilla_fpr=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
tmp_key=$(mktemp)
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o "$tmp_key"
fpr=$(gpg --show-keys --with-colons "$tmp_key" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')
if [[ $fpr != "$mozilla_fpr" ]]; then
  echo "Mozilla signing key fingerprint is '$fpr', expected $mozilla_fpr. Aborting." >&2
  rm -f "$tmp_key"
  exit 1
fi
sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 "$tmp_key" "$mozilla_key"
rm -f "$tmp_key"

sudo tee /etc/apt/sources.list.d/mozilla.sources >/dev/null <<EOF
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $mozilla_key
EOF
sudo tee /etc/apt/preferences.d/mozilla >/dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

# 3b. Keep the existing Firefox profile: it lives inside ~/snap, which gets deleted
if [[ -d $HOME/snap/firefox/common/.mozilla && ! -e $HOME/.mozilla ]]; then
  while pgrep -x firefox >/dev/null; do
    read -rp "Firefox is open. Close it so its profile can be copied, then press Enter... "
  done
  cp -a "$HOME/snap/firefox/common/.mozilla" "$HOME/"
fi

# 3c. Swap in the real deb. Ubuntu's wrapper has a higher version (epoch), so
#     replacing it counts as a downgrade, which -y refuses without the flag.
sudo apt update
sudo apt install -y --allow-downgrades firefox

# 3d. Remove every snap. snap refuses to remove a base or runtime that an app
#     still uses, so loop until only snapd is left; purging snapd mops up the rest.
if command -v snap >/dev/null; then
  for _ in 1 2 3 4 5; do
    mapfile -t snaps < <(snap list 2>/dev/null | awk 'NR > 1 && $1 != "snapd" {print $1}')
    (( ${#snaps[@]} )) || break
    for s in "${snaps[@]}"; do sudo snap remove --purge "$s" 2>/dev/null || true; done
  done
fi
sudo apt purge -y snapd
rm -rf "$HOME/snap"
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# 3e. Never let apt reinstall snapd
sudo tee /etc/apt/preferences.d/no-snap.pref >/dev/null <<'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

# 3f. Dock: point the Firefox launcher at the deb, drop other snap launchers
#     (snap launchers are named <snap>_<app>.desktop)
favs=$(gsettings get org.gnome.shell favorite-apps | sed -E \
  "s/'firefox_firefox\.desktop'/'firefox.desktop'/; s/'[^']*_[^']*\.desktop'//g; s/(, )+/, /g; s/\[, /[/; s/, \]/]/")
gsettings set org.gnome.shell favorite-apps "$favs"

# ---------------------------------------------------------------------------
step "4. Ubuntu Pro: silence apt"
sudo pro config set apt_news=false
sudo dpkg-divert --quiet --rename \
  --divert /etc/apt/apt.conf.d/20apt-esm-hook.conf.disabled \
  --add /etc/apt/apt.conf.d/20apt-esm-hook.conf

# ---------------------------------------------------------------------------
step "5. Shell and terminal: fish, zoxide (j), Ghostty"
sudo apt install -y fish zoxide ghostty

mkdir -p "$HOME/.config/fish/conf.d"
cat > "$HOME/.config/fish/conf.d/path.fish" <<'EOF'
# Written by setup.sh. ~/.local/bin holds claude and other per-user installs.
fish_add_path ~/.local/bin
EOF
cat > "$HOME/.config/fish/conf.d/zoxide.fish" <<'EOF'
# Written by setup.sh. `j <dir>` jumps; `ji` picks interactively (needs fzf).
zoxide init fish --cmd j | source
EOF
# Same `j` in bash (shares zoxide's history with fish)
zoxide_bash='eval "$(zoxide init bash --cmd j)"'
grep -qxF "$zoxide_bash" "$HOME/.bashrc" || echo "$zoxide_bash" >> "$HOME/.bashrc"

if [[ $(getent passwd "$USER" | cut -d: -f7) != /usr/bin/fish ]]; then
  sudo chsh -s /usr/bin/fish "$USER"
fi

# Ctrl+Alt+T, Nautilus "Open in Terminal" and terminal apps all go through
# xdg-terminal-exec; this user list overrides Ubuntu's (which says Ptyxis).
echo com.mitchellh.ghostty.desktop > "$HOME/.config/xdg-terminals.list"

# ---------------------------------------------------------------------------
step "6. Desktop settings"

# Appearance: dark + red accent
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface accent-color 'red'
gsettings set org.gnome.desktop.interface gtk-theme    'Yaru-red-dark'
gsettings set org.gnome.desktop.interface icon-theme   'Yaru-red-dark'

# Keyboard
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'latam')]"
gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true

# Block Ctrl+Q: a global shortcut that runs `true` swallows the key before apps see it
kb_path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/block-ctrl-q/
kb=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb_path
gsettings set "$kb" name    'Block Ctrl+Q'
gsettings set "$kb" command 'true'
gsettings set "$kb" binding '<Control>q'
kb_list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
if [[ $kb_list != *"$kb_path"* ]]; then
  if [[ $kb_list == "@as []" || $kb_list == "[]" ]]; then
    kb_list="['$kb_path']"
  else
    kb_list="${kb_list%]}, '$kb_path']"
  fi
  gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$kb_list"
fi

# Night Light
gsettings set org.gnome.system.location enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 1700

# Power: suspend after 20 min idle when plugged in
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 1200

# ---------------------------------------------------------------------------
step "7. Apps"

# MEGAsync: MEGA's .deb, which also adds MEGA's apt repo for updates
if dpkg -s megasync &>/dev/null; then
  echo "MEGAsync already installed."
else
  ubuntu_ver=$(. /etc/os-release && echo "$VERSION_ID")
  mega_url="https://mega.nz/linux/repo/xUbuntu_${ubuntu_ver}/amd64/megasync-xUbuntu_${ubuntu_ver}_amd64.deb"
  mega_deb=$(mktemp --suffix=.deb)
  if ! curl -fsSL -o "$mega_deb" "$mega_url"; then
    echo "No MEGAsync build for Ubuntu $ubuntu_ver yet (see https://mega.nz/linux/repo/). Skipping." >&2
  else
    chmod 644 "$mega_deb"   # readable by apt's sandbox user
    sudo apt install -y "$mega_deb"
  fi
  rm -f "$mega_deb"
fi

step "Done. Log out and back in so fish becomes your login shell. Open MEGAsync once to log in."
