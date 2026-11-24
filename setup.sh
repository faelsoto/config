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

# --- helpers ----------------------------------------------------------------

# install_apt_key URL DEST FINGERPRINT: fetch a repo signing key, refuse it unless
# its fingerprint matches, then install it where a .sources file can point at it.
install_apt_key() {
  local tmp fpr
  tmp=$(mktemp)
  curl -fsSL "$1" -o "$tmp"
  fpr=$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')
  if [[ $fpr != "$3" ]]; then
    echo "Key from $1 has fingerprint '$fpr', expected $3. Aborting." >&2
    rm -f "$tmp"
    exit 1
  fi
  sudo install -d -m 0755 "$(dirname "$2")"
  sudo install -m 0644 "$tmp" "$2"
  rm -f "$tmp"
}

# is_installed PACKAGE: true if dpkg has it installed (an arch suffix like :i386 works).
is_installed() {
  [[ $(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null) == ?i* ]]
}

# apt_install [APT OPTIONS] PACKAGE...: install only the packages that are missing.
# `apt install` on a package that's already there upgrades it when a newer version
# is out, which re-running this script shouldn't do (that's what `uu` is for).
apt_install() {
  local opts=() pkgs=() missing=() p
  for p in "$@"; do
    if [[ $p == -* ]]; then opts+=("$p"); else pkgs+=("$p"); fi
  done
  for p in "${pkgs[@]}"; do is_installed "$p" || missing+=("$p"); done
  if (( ${#missing[@]} )); then
    sudo apt install -y "${opts[@]}" "${missing[@]}"
  else
    echo "Already installed: ${pkgs[*]}"
  fi
}

# install_deb_from_url URL: download a .deb and install it with apt (pulls in its deps).
install_deb_from_url() {
  local deb
  deb=$(mktemp --suffix=.deb)
  curl -fsSL -o "$deb" "$1"
  chmod 644 "$deb"   # readable by apt's sandbox user
  sudo apt install -y "$deb"
  rm -f "$deb"
}

# add_shortcut ID NAME COMMAND BINDING: GNOME custom keyboard shortcut (idempotent).
add_shortcut() {
  local path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$1/
  local schema=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$path
  local list
  gsettings set "$schema" name    "$2"
  gsettings set "$schema" command "$3"
  gsettings set "$schema" binding "$4"
  list=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
  if [[ $list != *"$path"* ]]; then
    if [[ $list == "@as []" || $list == "[]" ]]; then
      list="['$path']"
    else
      list="${list%]}, '$path']"
    fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$list"
  fi
}

# ---------------------------------------------------------------------------
step "1. Base tools: curl, git"
sudo apt update
apt_install curl git
git config --global user.name  "Rafael Soto"
git config --global user.email "rafael@osom.so"
# Aliases and settings from my old setup
git config --global alias.st status
git config --global alias.ci commit
git config --global alias.co checkout
git config --global alias.su '!git branch --set-upstream-to=origin/$(git branch --show-current)'
git config --global alias.pr 'pull --rebase'
git config --global push.default current
git config --global rebase.autoStash true

# .localignore: a global pre-commit hook unstages every path listed in a repo's
# .localignore, so local-only changes never reach a commit (they stay in the
# working tree). With a global hooksPath, a repo's own .git/hooks stop running.
mkdir -p "$HOME/.githooks"
cat > "$HOME/.githooks/pre-commit" <<'EOF'
#!/bin/sh
set -e

IGNORE_LIST=".localignore"

if [ -f "$IGNORE_LIST" ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue  # Skip empty lines
    # If this file is staged, unstage it (remove from commit)
    if ! git diff --cached --quiet -- "$file"; then
      git restore --staged -- "$file" 2>/dev/null || true
    fi
  done < "$IGNORE_LIST"
fi

exit 0
EOF
chmod +x "$HOME/.githooks/pre-commit"
git config --global core.hooksPath "$HOME/.githooks"
# Keep .localignore itself out of every repo
if [[ -z $(git config --global --get core.excludesFile) ]]; then
  git config --global core.excludesFile "$HOME/.gitignore_global"
fi
excludes=$(git config --global --get core.excludesFile)
excludes=${excludes/#\~/$HOME}
grep -qxF .localignore "$excludes" 2>/dev/null || echo .localignore >> "$excludes"

# ---------------------------------------------------------------------------
step "2. Claude Code"
if [[ -x "$HOME/.local/bin/claude" ]]; then
  echo "Already installed: $("$HOME/.local/bin/claude" --version)"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

path_line='export PATH="$HOME/.local/bin:$PATH"'
grep -qxF "$path_line" "$HOME/.bashrc" || echo "$path_line" >> "$HOME/.bashrc"

# No desktop notifications ("Claude is waiting for your input"); other settings kept
claude_settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[[ -s $claude_settings ]] || echo '{}' > "$claude_settings"
tmp_settings=$(mktemp)
jq '.preferredNotifChannel = "notifications_disabled"' "$claude_settings" > "$tmp_settings"
mv "$tmp_settings" "$claude_settings"

# Claude Code reads clipboard images through xclip (X11) or wl-paste (Wayland)
apt_install xclip wl-clipboard

# ---------------------------------------------------------------------------
step "3. Remove snap (Firefox moves to Mozilla's apt repo)"

# 3a. Mozilla's apt repo, pinned above Ubuntu's snap-wrapper 'firefox' package
install_apt_key https://packages.mozilla.org/apt/repo-signing-key.gpg \
  /etc/apt/keyrings/packages.mozilla.org.asc 35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
sudo tee /etc/apt/sources.list.d/mozilla.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
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
#     Skipped when Mozilla's build is already there (the wrapper's version has
#     "snap" in it).
ff=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' firefox 2>/dev/null || true)
if [[ $ff == ?i* && $ff != *snap* ]]; then
  echo "Firefox from Mozilla already installed."
else
  sudo apt update
  sudo apt install -y --allow-downgrades firefox
fi

# 3d. Remove every snap. snap refuses to remove a base or runtime that an app
#     still uses, so loop until only snapd is left; purging snapd mops up the rest.
if command -v snap >/dev/null; then
  for _ in 1 2 3 4 5; do
    mapfile -t snaps < <(snap list 2>/dev/null | awk 'NR > 1 && $1 != "snapd" {print $1}')
    (( ${#snaps[@]} )) || break
    for s in "${snaps[@]}"; do sudo snap remove --purge "$s" 2>/dev/null || true; done
  done
fi
if is_installed snapd; then sudo apt purge -y snapd; fi
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

# 3g. Firefox settings, as policies (read at startup: restart Firefox to apply).
#     They only set defaults, so everything can still be changed in Settings
#     (except translation, which the policy locks off): no sponsored shortcuts,
#     stories or address-bar suggestions; no New Tab widgets or weather; a separate
#     search bar next to the address bar; restore the previous session; no
#     translation, no offer to save passwords, no spell checker, plain tab
#     tooltips instead of the big hover preview; Kagi as the
#     default search engine. Firefox removes the search bar after 120 days unused,
#     so that limit goes to 100 years. Widgets: the master switch alone isn't
#     enough, because Mozilla's remote New Tab config can override it, so every
#     widget is also blocked (locked off) by name. Unknown names are ignored, so
#     the list can name widgets from any version.
sudo install -d -m 0755 /etc/firefox/policies
sudo tee /etc/firefox/policies/policies.json >/dev/null <<'EOF'
{
  "policies": {
    "FirefoxHome": {
      "SponsoredTopSites": false,
      "SponsoredStories": false,
      "Weather": false,
      "Widgets": {
        "Enabled": false,
        "Blocked": [
          "pictureOfTheDay", "clocks", "lists", "focusTimer", "weather",
          "weatherForecast", "privacy", "crossword", "stocks", "recentSearches",
          "horoscopes", "travel", "solitaire", "wrexhamAFC", "sportsWidget"
        ]
      }
    },
    "FirefoxSuggest": { "SponsoredSuggestions": false },
    "SearchBar": "separate",
    "Homepage": { "StartPage": "previous-session" },
    "TranslateEnabled": false,
    "OfferToSaveLoginsDefault": false,
    "SearchEngines": {
      "Add": [
        {
          "Name": "Kagi",
          "Description": "Kagi Search",
          "URLTemplate": "https://kagi.com/search?q={searchTerms}",
          "SuggestURLTemplate": "https://kagisuggest.com/api/autosuggest?q={searchTerms}",
          "IconURL": "https://kagi.com/favicon-32x32.png",
          "Method": "GET",
          "Alias": "@kagi"
        }
      ],
      "Default": "Kagi"
    },
    "Preferences": {
      "browser.search.widget.removeAfterDaysUnused": { "Value": 36500, "Status": "default" },
      "layout.spellcheckDefault": { "Value": 0, "Status": "default" },
      "browser.tabs.hoverPreview.enabled": { "Value": false, "Status": "default" }
    }
  }
}
EOF

# ---------------------------------------------------------------------------
step "4. Ubuntu Pro: silence apt"
sudo pro config set apt_news=false
sudo dpkg-divert --quiet --rename \
  --divert /etc/apt/apt.conf.d/20apt-esm-hook.conf.disabled \
  --add /etc/apt/apt.conf.d/20apt-esm-hook.conf

# ---------------------------------------------------------------------------
step "5. Shell and terminal: fish, zoxide (j), Ghostty"
apt_install fish zoxide ghostty

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

# Aliases, one list per shell: fish reads conf.d/aliases.fish, and Ubuntu's
# .bashrc loads ~/.bash_aliases. cc continues the last Claude Code conversation in
# this folder. With nothing to continue, `claude --continue` starts a new session
# by itself, so it needs no fallback (`claude --continue || claude` would also
# relaunch after any session that exits with an error).
cat > "$HOME/.config/fish/conf.d/aliases.fish" <<'EOF'
# Written by setup.sh. Same list as ~/.bash_aliases.
alias uu 'sudo apt update && sudo apt upgrade'
alias ai 'sudo apt install'
alias opn 'xdg-open .'
alias s 'subl .'
alias rt 'rails test'
alias rtt 'env HEADLESS=no rails test'

# cc: continue this folder's last Claude Code conversation, or start a new one
# (claude --continue exits with an error when there's nothing to continue)
function cc
    command claude --continue $argv; or command claude $argv
end

# Postgres: one data folder per major version, ~/.local/share/postgres/<major>
# (a data folder only opens with its own major version), run by the systemd user
# service postgresql@<major> (step 7) so it always shuts down cleanly. pgup starts
# the version of the project you're in; pgdn stops whichever server is running,
# from any folder. Only one runs at a time (they all use port 5432).
function __pg_running --description 'Data folders with a live Postgres server'
    for pidfile in ~/.local/share/postgres/*/postmaster.pid
        set -l pid (head -n1 $pidfile)
        test -n "$pid"; and string match -q postgres -- (ps -o comm= -p $pid 2>/dev/null)
        and dirname $pidfile
    end
end

function pgup --description "Start this project's Postgres"
    set -l v (pg_ctl --version 2>/dev/null | string match -r '\d+')
    if test -z "$v"
        echo "pgup: no Postgres in this folder (mise has no postgres version here)" >&2
        return 1
    end
    set -l dir ~/.local/share/postgres/$v
    set -l running (__pg_running)
    if set -q running[1]
        if test "$running[1]" = "$dir"
            echo "Postgres $v is already running."
            return 0
        end
        echo "Postgres "(cat $running[1]/PG_VERSION)" is running ($running[1]). Run pgdn first." >&2
        return 1
    end
    if not test -f $dir/PG_VERSION
        # First use of this major version: offer to create its data folder
        read -l -P "No data folder for Postgres $v yet. Create it now? [y/N] " answer
        string match -qir '^y(es)?$' -- $answer; or return 1
        mkdir -p ~/.local/share/postgres
        initdb -D $dir --encoding=UTF8 --locale=C.UTF-8 --auth=trust >/dev/null; or return 1
        echo "Created $dir"
    end
    # Returns once the server accepts connections (the unit waits for pg_isready)
    systemctl --user start postgresql@$v
    and echo "Postgres $v is up. Logs: journalctl --user -u postgresql@$v"
end

function pgdn --description 'Stop whichever Postgres is running, from any folder'
    set -l running (__pg_running)
    if not set -q running[1]
        echo "No Postgres running."
        return 0
    end
    for dir in $running
        set -l v (cat $dir/PG_VERSION)
        if systemctl --user -q is-active postgresql@$v
            systemctl --user stop postgresql@$v
        else
            # Started outside the service (plain pg_ctl): fast shutdown with its own pg_ctl
            mise exec postgres@$v -- pg_ctl stop -m fast -D $dir
        end
        and echo "Postgres $v stopped."
    end
end

# gitg detached from the terminal: returns right away, survives closing the
# terminal, and its log output is dropped. setsid runs the real /usr/bin/gitg.
function gitg --description 'gitg, detached from the terminal'
    setsid -f gitg $argv >/dev/null 2>&1
end
EOF
cat > "$HOME/.bash_aliases" <<'EOF'
# Written by setup.sh. Same list as ~/.config/fish/conf.d/aliases.fish.
alias uu='sudo apt update && sudo apt upgrade'
alias ai='sudo apt install'
alias opn='xdg-open .'
alias s='subl .'
alias rt='rails test'
alias rtt='env HEADLESS=no rails test'

# cc: continue this folder's last Claude Code conversation, or start a new one
cc() { command claude --continue "$@" || command claude "$@"; }

# Postgres: one data folder per major version, run by the postgresql@<major> user
# service (see aliases.fish for the details)
_pg_running() {
  local pidfile pid
  for pidfile in "$HOME"/.local/share/postgres/*/postmaster.pid; do
    [[ -f $pidfile ]] || continue
    pid=$(head -n1 "$pidfile")
    [[ -n $pid && $(ps -o comm= -p "$pid" 2>/dev/null) == postgres ]] && dirname "$pidfile"
  done
}
pgup() {
  local v dir running
  v=$(pg_ctl --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)
  [[ -n $v ]] || { echo "pgup: no Postgres in this folder (mise has no postgres version here)" >&2; return 1; }
  dir=$HOME/.local/share/postgres/$v
  running=$(_pg_running | head -n1)
  if [[ -n $running ]]; then
    [[ $running == "$dir" ]] && { echo "Postgres $v is already running."; return 0; }
    echo "Postgres $(cat "$running/PG_VERSION") is running ($running). Run pgdn first." >&2
    return 1
  fi
  if [[ ! -f $dir/PG_VERSION ]]; then
    # First use of this major version: offer to create its data folder
    local answer
    read -r -p "No data folder for Postgres $v yet. Create it now? [y/N] " answer
    [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]] || return 1
    mkdir -p "$HOME/.local/share/postgres"
    initdb -D "$dir" --encoding=UTF8 --locale=C.UTF-8 --auth=trust >/dev/null || return 1
    echo "Created $dir"
  fi
  systemctl --user start "postgresql@$v" &&
    echo "Postgres $v is up. Logs: journalctl --user -u postgresql@$v"
}
pgdn() {
  local dirs dir v
  dirs=$(_pg_running)
  [[ -n $dirs ]] || { echo "No Postgres running."; return 0; }
  while read -r dir; do
    v=$(cat "$dir/PG_VERSION")
    if systemctl --user -q is-active "postgresql@$v"; then
      systemctl --user stop "postgresql@$v"
    else
      mise exec "postgres@$v" -- pg_ctl stop -m fast -D "$dir"
    fi && echo "Postgres $v stopped."
  done <<< "$dirs"
}

# gitg detached from the terminal (setsid runs the real /usr/bin/gitg)
gitg() { setsid -f gitg "$@" >/dev/null 2>&1; }
EOF

# `git co` (alias for checkout, step 1) completes branch names only in fish. Fish
# treats an alias like the command it stands for, so `git co` would also offer
# changed files, tags and commits. This loads fish's own git completions, drops
# that mapping for co, and gives co the local branches plus remote branches that
# checkout can track by name (origin/HEAD left out).
mkdir -p "$HOME/.config/fish/completions"
cat > "$HOME/.config/fish/completions/git.fish" <<'EOF'
# Written by setup.sh. Load fish's own git completions, then make `git co` (my
# alias for checkout) complete branch names only: no files, tags or commits.
source $__fish_data_dir/completions/git.fish
set -e __fish_git_alias_co
complete -c git -f -n '__fish_git_using_command co' -ka '(__fish_git_unique_remote_branches | string match -v HEAD)' -d 'Remote branch'
complete -c git -f -n '__fish_git_using_command co' -ka '(__fish_git_local_branches)' -d 'Local branch'
EOF

if [[ $(getent passwd "$USER" | cut -d: -f7) != /usr/bin/fish ]]; then
  sudo chsh -s /usr/bin/fish "$USER"
fi

# Ctrl+Alt+T, Nautilus "Open in Terminal" and terminal apps all go through
# xdg-terminal-exec; this user list overrides Ubuntu's (which says Ptyxis).
echo com.mitchellh.ghostty.desktop > "$HOME/.config/xdg-terminals.list"

# Ghostty: new windows open in ~ (tabs and splits keep the current directory);
# Super+Shift+K clears the terminal
mkdir -p "$HOME/.config/ghostty"
cat > "$HOME/.config/ghostty/config.ghostty" <<'EOF'
# Written by setup.sh.
# New windows start in ~ (tabs and splits still open in the current directory).
window-inherit-working-directory = false
working-directory = home
# Super+Shift+K clears the screen and scrollback
keybind = super+shift+k=clear_screen
EOF

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
add_shortcut block-ctrl-q 'Block Ctrl+Q' 'true' '<Control>q'

# Super+E opens Files
add_shortcut files 'Files' 'nautilus --new-window' '<Super>e'

# Volume keys: Super+Delete up, Super+Insert down, Super+F1 mic mute. Super+F1 was
# Help's shortcut, so unbind that first.
media_keys=org.gnome.settings-daemon.plugins.media-keys
gsettings set "$media_keys" help "[]"
gsettings set "$media_keys" volume-up "['<Super>Delete']"
gsettings set "$media_keys" volume-down "['<Super>Insert']"
gsettings set "$media_keys" mic-mute "['<Super>F1']"

# Super+F4 plays/pauses whatever is playing
gsettings set "$media_keys" play "['<Super>F4']"

# Night Light, for the Ubuntu (GNOME Shell) session; Flashback uses gammastep
# (step 9). 2800 K is the night value from my old redshift config.
gsettings set org.gnome.system.location enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 2800

# Power: suspend after 20 min idle when plugged in
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 1200

# ---------------------------------------------------------------------------
step "7. Dev: mise for Ruby, PHP, Node, Postgres, MySQL"

# Build dependencies. Node and Postgres install as prebuilt binaries. Ruby is
# prebuilt when a binary exists and compiled otherwise (older versions); PHP is
# always compiled. libpq-dev / libmysqlclient-dev let the pg and mysql2 gems
# build, and give PHP its pdo_pgsql extension.
apt_install \
  build-essential autoconf patch pkg-config bison re2c rustc \
  libssl-dev libyaml-dev zlib1g-dev libffi-dev libgmp-dev uuid-dev \
  libreadline-dev libncurses-dev libgdbm-dev libdb-dev \
  libxml2-dev libicu-dev libzip-dev libonig-dev libcurl4-openssl-dev libsqlite3-dev \
  libpng-dev libjpeg-dev libfreetype-dev libwebp-dev libsodium-dev libbz2-dev \
  libpq-dev libmysqlclient-dev

# mise, from its own apt repo (Ubuntu doesn't package it)
install_apt_key https://mise.jdx.dev/gpg-key.pub \
  /etc/apt/keyrings/mise-archive-keyring.asc 24853EC9F655CE80B48E6C3A8B81C9D17413A06D
sudo tee /etc/apt/sources.list.d/mise.sources >/dev/null <<'EOF'
Types: deb
URIs: https://mise.jdx.dev/deb
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/mise-archive-keyring.asc
EOF
sudo apt update
apt_install mise

# Activate in both shells: tool versions then follow mise.toml / .tool-versions
cat > "$HOME/.config/fish/conf.d/mise.fish" <<'EOF'
# Written by setup.sh. Tool versions follow mise.toml / .tool-versions.
mise activate fish | source
EOF
mise_bash='eval "$(mise activate bash)"'
grep -qxF "$mise_bash" "$HOME/.bashrc" || echo "$mise_bash" >> "$HOME/.bashrc"

# Bundler: `bundle` on its own keeps meaning `bundle install`. Setting
# default_cli_command also stops Bundler's "In a future version of Bundler, running
# `bundle` without argument will no longer run `bundle install`" notice. The global
# config is a plain YAML file, so this works before any Ruby is installed.
mkdir -p "$HOME/.bundle"
if ! grep -qs '^BUNDLE_DEFAULT_CLI_COMMAND:' "$HOME/.bundle/config"; then
  [[ -s $HOME/.bundle/config ]] || echo '---' > "$HOME/.bundle/config"
  echo 'BUNDLE_DEFAULT_CLI_COMMAND: "install"' >> "$HOME/.bundle/config"
fi

# Postgres runs as a systemd user service, one instance per major version
# (postgresql@17, ...), started by pgup and stopped by pgdn (step 5). Started from
# a terminal with pg_ctl, Postgres sits in that terminal's scope, and at power-off
# systemd sends SIGTERM to every process there at once, so it often doesn't shut
# down cleanly and the next start runs crash recovery. The service sends SIGINT
# (fast shutdown) to the main process only, which is what the PostgreSQL docs
# recommend under systemd, and systemd stops it the same way at power-off.
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/postgresql@.service" <<'EOF'
[Unit]
Description=PostgreSQL %i (mise, data in ~/.local/share/postgres/%i)

[Service]
Type=simple
# mise picks the newest installed %i.x; exec makes postgres itself the main process
ExecStart=/bin/sh -c 'exec "$$(mise where postgres@%i)/bin/postgres" -D "%h/.local/share/postgres/%i"'
# Block `systemctl start` until the server accepts connections (covers crash recovery too)
ExecStartPost=/bin/sh -c 'until "$$(mise where postgres@%i)/bin/pg_isready" -q; do sleep 0.5; done'
ExecReload=/bin/kill -HUP $MAINPID
# SIGINT = fast shutdown, sent only to the postmaster so it stops its own children cleanly
KillMode=mixed
KillSignal=SIGINT
TimeoutStartSec=10min
TimeoutStopSec=1min

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload

# ---------------------------------------------------------------------------
step "8. Apps"

# Google Chrome (the browser we test with). Its .deb also adds Google's apt repo.
if ! dpkg -s google-chrome-stable &>/dev/null; then
  install_deb_from_url https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
fi

# Brave, from Brave's apt repo (their documented setup: keyring + .sources file)
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
  https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
  https://brave-browser-apt-release.s3.brave.com/brave-browser.sources

# Ulauncher, from its PPA (not in Ubuntu's repos)
sudo add-apt-repository -y -n ppa:agornostal/ulauncher

# KeePassXC, from its PPA (Ubuntu's repos lag a minor version behind)
sudo add-apt-repository -y -n ppa:phoerious/keepassxc

# Sublime Text, from Sublime HQ's apt repo
install_apt_key https://download.sublimetext.com/sublimehq-pub.gpg \
  /etc/apt/keyrings/sublimehq-pub.asc 1EDDE2CDFC025D17F6DA9EC0ADAE6AD28A8F901A
sudo tee /etc/apt/sources.list.d/sublime-text.sources >/dev/null <<'EOF'
Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: /etc/apt/keyrings/sublimehq-pub.asc
EOF

# OnlyOffice Desktop Editors, from OnlyOffice's apt repo (its package doesn't add one)
install_apt_key https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
  /etc/apt/keyrings/onlyoffice.asc E09CA29F6E178040EF22B4098320CA65CB2DE8E5
sudo tee /etc/apt/sources.list.d/onlyoffice.sources >/dev/null <<'EOF'
Types: deb
URIs: https://download.onlyoffice.com/repo/debian
Suites: squeeze
Components: main
Signed-By: /etc/apt/keyrings/onlyoffice.asc
EOF

sudo apt update
apt_install brave-browser ulauncher flameshot keepassxc sublime-text gitg
# Without recommends: OnlyOffice recommends ttf-mscorefonts-installer, which stops
# for Microsoft's license prompt and downloads from SourceForge (a failed download
# fails the install). The fonts it does require include metric-compatible stand-ins
# (Carlito for Calibri, Liberation for Arial/Times), so layouts are kept.
apt_install --no-install-recommends onlyoffice-desktopeditors

# Brave: turn Rewards off for every profile with Brave's admin policy, which also
# removes the Rewards button. Brave reads it at startup; brave://policy lists it.
sudo install -d -m 0755 /etc/brave/policies/managed
echo '{ "BraveRewardsDisabled": true }' | sudo tee /etc/brave/policies/managed/setup.json >/dev/null

# Ulauncher on Alt+Space. Alt+Space normally opens the window menu, so unbind that
# first (here for the GNOME session; Compiz's copy is unbound in step 9). On Wayland
# Ulauncher can't grab keys itself, so a GNOME shortcut runs ulauncher-toggle; on
# X11 Ulauncher's own hotkey works too. Whichever grabs the key first wins, and both
# open Ulauncher.
gsettings set org.gnome.desktop.wm.keybindings activate-window-menu "[]"
systemctl --user enable --now ulauncher.service
add_shortcut ulauncher 'Ulauncher' 'ulauncher-toggle' '<Alt>space'
# Ulauncher writes settings.json with all its defaults on first start and doesn't
# merge a partial file, so wait for that file, then change only the hotkey.
ul_settings="$HOME/.config/ulauncher/settings.json"
for _ in $(seq 15); do [[ -s $ul_settings ]] && break; sleep 1; done
if [[ -s $ul_settings ]]; then
  tmp_ul=$(mktemp)
  jq '.["hotkey-show-app"] = "<Alt>space"' "$ul_settings" > "$tmp_ul"
  mv "$tmp_ul" "$ul_settings"
  systemctl --user restart ulauncher.service
else
  echo "Ulauncher hasn't written its settings yet; set its hotkey to Alt+Space in its preferences." >&2
fi

# Flameshot: Ctrl+Shift+Delete opens the capture UI
add_shortcut flameshot 'Flameshot' 'flameshot gui' '<Control><Shift>Delete'

# Flameshot: Enter copies the capture to the clipboard and closes it. The default
# copy key is Ctrl+C, and Flameshot allows one key per action. Only this key is
# touched; the rest of the file is left alone.
fs_ini="$HOME/.config/flameshot/flameshot.ini"
mkdir -p "$(dirname "$fs_ini")"
touch "$fs_ini"
if grep -q '^TYPE_COPY=' "$fs_ini"; then
  sed -i 's/^TYPE_COPY=.*/TYPE_COPY=Return/' "$fs_ini"
elif grep -q '^\[Shortcuts\]' "$fs_ini"; then
  sed -i '/^\[Shortcuts\]/a TYPE_COPY=Return' "$fs_ini"
else
  printf '[Shortcuts]\nTYPE_COPY=Return\n' >> "$fs_ini"
fi
# Start Flameshot's tray icon at login. This is Flameshot's own switch; it writes
# ~/.config/autostart/Flameshot.desktop and startupLaunch=true.
flameshot config --autostart true

# MEGAsync: MEGA's .deb for this Ubuntu version, which also adds MEGA's apt repo
if dpkg -s megasync &>/dev/null; then
  echo "MEGAsync already installed."
else
  ubuntu_ver=$(. /etc/os-release && echo "$VERSION_ID")
  mega_url="https://mega.nz/linux/repo/xUbuntu_${ubuntu_ver}/amd64/megasync-xUbuntu_${ubuntu_ver}_amd64.deb"
  if curl -fsIo /dev/null "$mega_url"; then
    install_deb_from_url "$mega_url"
  else
    echo "No MEGAsync build for Ubuntu $ubuntu_ver yet (see https://mega.nz/linux/repo/). Skipping." >&2
  fi
fi

# Steam, from Ubuntu's multiverse. It needs 32-bit packages, and on NVIDIA the
# 32-bit build of the installed driver's OpenGL library, or games won't start.
sudo dpkg --add-architecture i386
sudo apt update
steam_pkgs=(steam-installer)
nvidia_gl=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'libnvidia-gl-*' 2>/dev/null |
  awk '$1 == "ii" && $2 ~ /^libnvidia-gl-[0-9]+$/ {print $2; exit}')
if [[ -n $nvidia_gl ]]; then
  steam_pkgs+=("$nvidia_gl:i386")
fi
apt_install "${steam_pkgs[@]}"

# Slack: the newest .deb from Slack's packagecloud repo. The package's daily cron
# job (/etc/cron.daily/slack) adds and maintains that repo (slack.list, with its
# keys in /etc/apt/trusted.gpg.d/), so run it once for updates through apt right
# away. Don't add a second source for the same repo: apt rejects the duplicate
# ("Conflicting values set for option Signed-By").
if ! dpkg -s slack-desktop &>/dev/null; then
  slack_repo=https://packagecloud.io/slacktechnologies/slack/debian
  slack_deb=$(curl -fsSL "$slack_repo/dists/jessie/main/binary-amd64/Packages" |
    awk '/^Package: slack-desktop$/ {p=1} p && /^Filename:/ {print $2; p=0}' | sort -V | tail -1)
  install_deb_from_url "$slack_repo/$slack_deb"
  sudo /etc/cron.daily/slack
fi

# ---------------------------------------------------------------------------
step "9. GNOME Flashback + Compiz (X11 session)"
apt_install gnome-session-flashback compiz compiz-gnome compiz-plugins \
  compiz-plugins-extra compizconfig-settings-manager gammastep

# Wallpaper and lock screen: only step in when the picture is missing. Flashback
# falls back to GNOME's own defaults, adwaita-d.jxl (desktop, dark mode) and
# adwaita-timed.xml (lock screen), which Ubuntu doesn't ship. With no image the
# desktop draws nothing, so Compiz shows black and leaves window trails, and the
# lock screen is solid black. A picture I picked myself is left alone as long as
# its file exists.
#
# The picture Flashback shows for a key: my own pick if I made one, else
# Flashback's default.
flashback_picture() { XDG_CURRENT_DESKTOP=GNOME-Flashback:GNOME gsettings get "$1" "$2" | tr -d "'"; }
picture_exists() { [[ -n $1 ]] && gio info "$1" &>/dev/null; }

bg=org.gnome.desktop.background
for key in picture-uri picture-uri-dark; do
  uri=$(flashback_picture "$bg" "$key")
  picture_exists "$uri" && continue
  ubuntu_uri=$(XDG_CURRENT_DESKTOP=ubuntu:GNOME GSETTINGS_BACKEND=memory gsettings get "$bg" "$key" | tr -d "'")
  if picture_exists "$ubuntu_uri"; then
    echo "Wallpaper $uri is missing; using Ubuntu's, $ubuntu_uri." >&2
    gsettings set "$bg" "$key" "$ubuntu_uri"
  else
    echo "Wallpaper $uri is missing, and so is Ubuntu's; using a solid background color." >&2
    gsettings set "$bg" picture-options 'none'
  fi
done

# Lock screen: Flashback's draws the *screensaver* background. If that's missing,
# use the desktop's dark-mode wallpaper, like GNOME Shell's lock screen does in
# the Ubuntu session, or a plain color if that's missing too.
ss=org.gnome.desktop.screensaver
lock_uri=$(flashback_picture "$ss" picture-uri)
if ! picture_exists "$lock_uri"; then
  dark_uri=$(flashback_picture "$bg" picture-uri-dark)
  if picture_exists "$dark_uri"; then
    echo "Lock screen picture $lock_uri is missing; using the desktop's, $dark_uri." >&2
    gsettings set "$ss" picture-uri "$dark_uri"
  else
    gsettings set "$ss" picture-options 'none'
  fi
fi

# Desktop icons can be dragged anywhere and snap to the grid (Flashback's default
# auto-arranges them into a sorted grid; 'free' would skip the snapping)
gsettings set org.gnome.gnome-flashback.desktop.icons placement 'align-icons-to-grid'

# Alt+Space belongs to Ulauncher (step 8): unbind Compiz's window menu from it
compiz_core=org.compiz.core:/org/compiz/profiles/gnome-flashback/plugins/core/
gsettings set "$compiz_core" window-menu-key 'Disabled'

# Desktop cube with 4 faces: four viewports side by side, drawn by `cube` and spun
# by `rotate` (Ctrl+Alt+Left/Right, Ctrl+Alt+drag). `wall` is dropped because it
# slides between viewports on the same Ctrl+Alt+arrow keys. The plugins' declared
# order: cube after decor and before scale/switcher/expo; rotate after cube. The
# rest of the active list is kept as is.
gsettings set "$compiz_core" hsize 4
gsettings set "$compiz_core" vsize 1
plugins=$(gsettings get "$compiz_core" active-plugins | python3 -I -c '
import ast, sys
p = [x for x in ast.literal_eval(sys.stdin.read()) if x != "wall"]
if "cube" not in p:
    start = p.index("decor") + 1 if "decor" in p else len(p)
    later = [i for i, x in enumerate(p) if i >= start and x in ("animation", "expo", "scale", "switcher")]
    p.insert(min(later) if later else len(p), "cube")
if "rotate" not in p:
    p.insert(p.index("cube") + 1, "rotate")
if "switcher" not in p:        # Alt+Tab; must load after cube, so at the end
    p.append("switcher")
print(p)')
gsettings set "$compiz_core" active-plugins "$plugins"

# Compiz's settings library has a "GNOME integration" that reads some Compiz
# options from GNOME's settings instead, including rotate's keys (taken from
# GNOME's "switch to workspace" shortcuts). GNOME stores those as lists, the
# integration expects one string ("compizconfig - Error: Expected string value"),
# and rotate ends up with no keys at all. Turn the integration off so Compiz uses
# its own settings. Those are Compiz's defaults (Alt+drag moves a window,
# Alt+middle-drag resizes it, Alt+right-click opens the window menu, Super+S is
# expo), except Compiz's own terminal and screenshot keys, which get disabled:
# they'd run gnome-terminal / gnome-screenshot, which aren't installed, and
# Flashback already handles Ctrl+Alt+T and Print.
mkdir -p "$HOME/.config/compiz-1/compizconfig"
cat > "$HOME/.config/compiz-1/compizconfig/config" <<'EOF'
[general]
backend = gsettings
integration = false

[general_gnome-flashback]
backend = gsettings
integration = false
EOF
compiz_plugins=/org/compiz/profiles/gnome-flashback/plugins
for k in run-command-terminal-key run-command-screenshot-key run-command-window-screenshot-key; do
  gsettings set "org.compiz.gnomecompat:$compiz_plugins/gnomecompat/" "$k" 'Disabled'
done

# Magnifier (ezoom): Super+mouse wheel zooms in and out. Ubuntu ships every ezoom
# binding disabled.
gsettings set "org.compiz.ezoom:$compiz_plugins/ezoom/" zoom-in-button  '<Super>Button4'
gsettings set "org.compiz.ezoom:$compiz_plugins/ezoom/" zoom-out-button '<Super>Button5'

# Panel icons: the session indicator (far right) asks for ubuntu-mono's
# system-*-panel icons. Yaru doesn't have them, so it falls back to a full-color
# monitor icon. Link them into the panel folders Yaru's index already lists. Only
# the panel asks for these names, so the GNOME session is unaffected.
icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
for size in 16 22; do
  dest="$HOME/.local/share/icons/$icon_theme/${size}x${size}/panel"
  mkdir -p "$dest"
  for f in /usr/share/icons/ubuntu-mono-dark/{status,actions}/"$size"/system-{devices,shutdown,restart}-panel*.svg; do
    [[ -e $f ]] && ln -sfn "$f" "$dest/"
  done
done

# Workspace switcher (bottom panel): color the current cube face. It draws that face
# in GTK's "selected" state, which Yaru doesn't style, so every face looked the same.
gtk_css="$HOME/.config/gtk-3.0/gtk.css"
mkdir -p "${gtk_css%/*}"
if ! grep -qs 'wnck-pager:selected' "$gtk_css"; then
  cat >> "$gtk_css" <<'EOF'
/* Workspace switcher in the Flashback panel: color the current cube face.
   Yaru leaves it unstyled, so all faces look the same. */
wnck-pager:selected { background-color: @theme_selected_bg_color; }
EOF
fi

# Night light: GNOME computes Night Light, but only GNOME Shell applies it to the
# screen, so in Flashback nothing gets tinted. gammastep (redshift's successor)
# does it there instead, with the values from my old redshift config, started only
# in Flashback. gammastep-indicator runs gammastep and adds a tray icon to toggle it.
mkdir -p "$HOME/.config/gammastep" "$HOME/.config/autostart"
cat > "$HOME/.config/gammastep/config.ini" <<'EOF'
; Written by setup.sh. Night light for the GNOME Flashback session, where GNOME's
; own Night Light is computed but never applied (that's GNOME Shell's job).
; Values from my old redshift config. Day and night follow the sun at the current
; location, via GeoClue (Ubuntu starts GeoClue's agent in Flashback).
[general]
temp-day=4000
temp-night=2800
fade=1
brightness-day=1.0
brightness-night=0.55
location-provider=geoclue2
adjustment-method=randr
EOF
cat > "$HOME/.config/autostart/gammastep.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Gammastep
Comment=Night light for GNOME Flashback (written by setup.sh)
Exec=gammastep-indicator
OnlyShowIn=GNOME-Flashback;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

step "Done. Log out, then at the login screen click your name and pick \"GNOME Flashback (Compiz)\" from the gear icon (it's remembered). Open MEGAsync once to log in."
