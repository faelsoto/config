# Ubuntu setup

What I do on a fresh Ubuntu install. Last done on **Ubuntu 26.04 LTS**, using the GNOME Flashback + Compiz session (step 9).

Step 0 is manual. Everything after it is automated by [`setup.sh`](setup.sh), which follows the same order and is safe to re-run:

```bash
./setup.sh   # run as your normal user, from a terminal in the desktop session
```

If Firefox is open, the script pauses until you close it, because step 3 copies its profile. If any step fails, the script stops and prints which step. Log out and back in when it finishes, so fish becomes the login shell.

> Keep this file and `setup.sh` in sync when adding a step.

---

## 0. In the installer (manual)

- **Encrypt the disk** (LUKS + LVM).
- **Install recommended proprietary software**: tick both third-party drivers *and* extra media formats. On this machine that pulled in `nvidia-driver-595-open` (RTX 3060 Ti) and `ubuntu-restricted-addons` (codecs).
- Keyboard: **Latin American**. Timezone: **America/Mexico_City**.

## 1. Base tools: curl and git

Neither is installed by default. `curl` is needed for the Claude Code installer.

```bash
sudo apt update
sudo apt install -y curl git
git config --global user.name  "Rafael Soto"
git config --global user.email "rafael@osom.so"
```

## 2. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Installs to `~/.local/bin/claude`. Make sure `~/.bashrc` has this line (fish gets its own in step 5):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Turn off its desktop notifications ("Claude is waiting for your input"). The setting is `preferredNotifChannel` in `~/.claude/settings.json`, shown as *Local notifications* in `/config`:

```bash
jq '.preferredNotifChannel = "notifications_disabled"' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

To paste images (like screenshots) into Claude Code, install the clipboard tools it uses, `xclip` on X11 and `wl-paste` on Wayland:

```bash
sudo apt install -y xclip wl-clipboard
```

## 3. Remove snap

Removes snapd and every snap, and pins apt so snapd never comes back. What that changes:

- **Firefox** moves to Mozilla's own apt repo. The repo is pinned at priority 1000 so it beats Ubuntu's `firefox` package, which is only a wrapper that installs the snap. The snap profile is copied to `~/.mozilla` first, so bookmarks and logins carry over.
- **App Center, Firmware Updater, Security Center** are snaps, so they go away. No replacement: apps come from apt. Firmware updates still work from the terminal: `fwupdmgr refresh && fwupdmgr update`.
- **Dock**: the Firefox launcher is pointed at the deb, and the other snap launchers are dropped.

```bash
# Firefox from Mozilla (key fingerprint must be 35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3)
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null
gpg --show-keys /etc/apt/keyrings/packages.mozilla.org.asc
sudo tee /etc/apt/sources.list.d/mozilla.sources <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' | sudo tee /etc/apt/preferences.d/mozilla
cp -a ~/snap/firefox/common/.mozilla ~/        # keep the profile (close Firefox first)
sudo apt update && sudo apt install --allow-downgrades firefox

# Remove every snap (apps before the runtimes they use), then snapd itself
snap list
sudo snap remove --purge <name>...
sudo apt purge snapd
rm -rf ~/snap && sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# Never install snapd again
printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' | sudo tee /etc/apt/preferences.d/no-snap.pref
```

## 4. Ubuntu Pro: silence apt

```bash
sudo pro config set apt_news=false
sudo dpkg-divert --rename --divert /etc/apt/apt.conf.d/20apt-esm-hook.conf.disabled \
                 --add /etc/apt/apt.conf.d/20apt-esm-hook.conf
```

The first command stops the "apt news" ads. The second disables the hook that prints *"Get more security updates through Ubuntu Pro…"* during `apt upgrade`. Using `dpkg-divert` instead of deleting the file means it stays disabled when `ubuntu-pro-client` updates. To undo: `sudo dpkg-divert --rename --remove /etc/apt/apt.conf.d/20apt-esm-hook.conf`.

## 5. Shell and terminal: fish, `j`, Ghostty

All three are in Ubuntu's own repos.

```bash
sudo apt install -y fish zoxide ghostty

mkdir -p ~/.config/fish/conf.d
echo 'fish_add_path ~/.local/bin'        > ~/.config/fish/conf.d/path.fish     # claude etc.
echo 'zoxide init fish --cmd j | source' > ~/.config/fish/conf.d/zoxide.fish   # j <dir>
echo 'eval "$(zoxide init bash --cmd j)"' >> ~/.bashrc                         # j in bash too

sudo chsh -s /usr/bin/fish "$USER"                                  # login shell, next login
echo com.mitchellh.ghostty.desktop > ~/.config/xdg-terminals.list   # default terminal

# Ghostty: new windows open in ~
mkdir -p ~/.config/ghostty
printf 'window-inherit-working-directory = false\nworking-directory = home\n' > ~/.config/ghostty/config.ghostty
```

- **`j <dir>`** is [zoxide](https://github.com/ajeetdsouza/zoxide), a maintained successor to autojump. It jumps to the best match among directories you've visited, ranked by how often and how recently. It learns as you `cd`, so it starts empty. It works in both fish and bash, with one shared history. `ji` opens an interactive picker if `fzf` is installed. Note that `which j` prints nothing because `j` is a shell function, not a program on disk; use `type j` to check it.
- **Default terminal**: Ctrl+Alt+T, Nautilus's *Open in Terminal*, and terminal apps all launch through `xdg-terminal-exec`. The user list in `~/.config` overrides Ubuntu's, which lists Ptyxis.
- **New windows open in `~`**: by default Ghostty opens a new window in the directory of the last window you used. Tabs and splits still do that, which is usually what you want there. After changing the config, press Ctrl+Shift+, in Ghostty to reload it.

## 6. Desktop settings

| Setting | Where in Settings | Value |
|---|---|---|
| Style + accent | Appearance | **Dark**, accent **red** |
| Keyboard layout | Keyboard → Input Sources | **Spanish (Latin American)** |
| Block Ctrl+Q | Keyboard → View and Customize Shortcuts → Custom Shortcuts | name *Block Ctrl+Q*, command `true`, shortcut **Ctrl+Q** |
| Night Light | Displays → Night Light | **On**, sunset to sunrise, warmest (1700 K) |
| Location services | Privacy & Security → Location | **On** (lets Night Light follow local sunset/sunrise) |
| Automatic suspend | Power → Automatic Suspend | **Plugged in: 20 min** |
| Num Lock | *(no UI, GNOME remembers last state)* | **On** at login |

**Block Ctrl+Q**: GNOME grabs a global shortcut before any app sees the key, so binding Ctrl+Q to `true` (a command that does nothing) means no app can be quit with it. That includes terminal programs that use Ctrl+Q, such as nano's backward search.

Same thing from the terminal:

```bash
# Appearance: dark + red accent
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface accent-color 'red'
gsettings set org.gnome.desktop.interface gtk-theme    'Yaru-red-dark'
gsettings set org.gnome.desktop.interface icon-theme   'Yaru-red-dark'

# Keyboard
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'latam')]"
gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true

# Block Ctrl+Q (also append the path to ...media-keys custom-keybindings, see setup.sh)
kb=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/block-ctrl-q/
gsettings set "$kb" name    'Block Ctrl+Q'
gsettings set "$kb" command 'true'
gsettings set "$kb" binding '<Control>q'

# Night Light
gsettings set org.gnome.system.location enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 1700

# Power: suspend after 20 min idle when plugged in
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'suspend'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 1200
```

Tip: to find the key for any new tweak, run `dconf watch /`, change the setting in the Settings app, and copy the path it prints.

## 7. Dev: mise for Ruby, PHP, Node, Postgres, MySQL

[mise](https://mise.jdx.dev) replaces asdf. It reads existing `.tool-versions` files as they are, so old projects keep working.

| Tool | How mise installs it | Needs the build packages? |
|---|---|---|
| Node | prebuilt binary | no |
| Postgres | prebuilt binary (via conda) | no |
| MySQL | MySQL's generic binary | no (mise offers to install any missing shared libraries) |
| Ruby | prebuilt when one exists, otherwise compiled (common for older versions) | as a fallback |
| PHP | always compiled | yes |

```bash
# Build packages for Ruby and PHP, plus client libraries so the pg / mysql2 gems
# build and PHP gets pdo_pgsql
sudo apt install -y \
  build-essential autoconf patch pkg-config bison re2c rustc \
  libssl-dev libyaml-dev zlib1g-dev libffi-dev libgmp-dev uuid-dev \
  libreadline-dev libncurses-dev libgdbm-dev libdb-dev \
  libxml2-dev libicu-dev libzip-dev libonig-dev libcurl4-openssl-dev libsqlite3-dev \
  libpng-dev libjpeg-dev libfreetype-dev libwebp-dev libsodium-dev libbz2-dev \
  libpq-dev libmysqlclient-dev

# mise from its own apt repo (key fingerprint must be 24853EC9F655CE80B48E6C3A8B81C9D17413A06D)
sudo curl -fsSLo /etc/apt/keyrings/mise-archive-keyring.asc https://mise.jdx.dev/gpg-key.pub
sudo tee /etc/apt/sources.list.d/mise.sources <<'EOF'
Types: deb
URIs: https://mise.jdx.dev/deb
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/mise-archive-keyring.asc
EOF
sudo apt update && sudo apt install -y mise

echo 'mise activate fish | source'  > ~/.config/fish/conf.d/mise.fish
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
```

No versions are installed globally; each project picks its own (for example `mise use ruby@3.4 node@22 postgres@18`). Databases run per project, the same way the old `pgup` / `mysqlup` aliases did: `initdb` + `pg_ctl start`, or `mysqld_safe --datadir=…`. With `libpq-dev` installed, the pg gem builds without the old `bundle config build.pg --with-pg-config=…`.

## 8. Apps

### Browsers: Google Chrome (for testing) and Brave

Chromium is left out: on Ubuntu it only comes as a snap, and snapd is pinned out.

```bash
curl -fLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y /tmp/chrome.deb    # also adds Google's apt repo for updates

sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
sudo apt update && sudo apt install -y brave-browser
```

For system tests, Selenium 4.11+ downloads the matching chromedriver itself, so the old chromedriver install script isn't needed.

### Ulauncher and Flameshot

```bash
sudo add-apt-repository -y ppa:agornostal/ulauncher   # Ulauncher isn't in Ubuntu's repos
sudo apt install -y ulauncher flameshot
systemctl --user enable --now ulauncher.service       # start at login
```

Ulauncher opens with **Alt+Space**. That key normally opens the window menu (Move, Resize, Close…), so the setup unbinds it there first: `activate-window-menu` in GNOME, and `window-menu-key` in Compiz (step 9). On Wayland, Ulauncher can't grab its own hotkey, so a GNOME custom shortcut (*Ulauncher*, command `ulauncher-toggle`) handles it. On X11, Ulauncher's own hotkey (`hotkey-show-app` in `~/.config/ulauncher/settings.json`) works too. Whichever program grabs the key first wins, and both open Ulauncher. `setup.sh` sets all of this.

Flameshot opens with **Ctrl+Shift+Delete** (custom shortcut *Flameshot*, command `flameshot gui`, also added by `setup.sh`). Because it's a global shortcut, browsers no longer get that key; it normally opens *Clear browsing data*. On Wayland, the first capture asks for permission to take screenshots; click **Allow**.

### KeePassXC and Sublime Text

KeePassXC comes from its PPA, because Ubuntu's repos are a minor version behind (2.7 vs 2.8). Sublime Text comes from Sublime HQ's own apt repo.

```bash
sudo add-apt-repository -y ppa:phoerious/keepassxc

# Sublime's key fingerprint must be 1EDDE2CDFC025D17F6DA9EC0ADAE6AD28A8F901A
sudo curl -fsSLo /etc/apt/keyrings/sublimehq-pub.asc https://download.sublimetext.com/sublimehq-pub.gpg
sudo tee /etc/apt/sources.list.d/sublime-text.sources <<'EOF'
Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: /etc/apt/keyrings/sublimehq-pub.asc
EOF
sudo apt update && sudo apt install -y keepassxc sublime-text
```

### MEGAsync

Not in Ubuntu's repos. Install MEGA's .deb for this Ubuntu version. Installing it also adds MEGA's apt repo (`/etc/apt/sources.list.d/megaio.sources`, with its own signing key), so later updates come through `apt upgrade`. It also raises the inotify watch limit so it can watch large folders.

```bash
. /etc/os-release   # VERSION_ID, e.g. 26.04
curl -fLo /tmp/megasync.deb "https://mega.nz/linux/repo/xUbuntu_${VERSION_ID}/amd64/megasync-xUbuntu_${VERSION_ID}_amd64.deb"
sudo apt install -y /tmp/megasync.deb
```

Builds are listed at <https://mega.nz/linux/repo/>. MEGA sometimes skips non-LTS releases (there's no 25.10 build, for example). Open MEGAsync once to log in; it adds itself to autostart. Optional: `nautilus-megasync` adds sync-status icons in Files, but its build lags behind MEGAsync itself.

## 9. GNOME Flashback + Compiz

I like gnome-panel so I can run Compiz. On 26.04 that still works, and everything needed is in Ubuntu's repos (universe):

```bash
sudo apt install -y gnome-session-flashback compiz compiz-gnome compiz-plugins \
  compiz-plugins-extra compizconfig-settings-manager

# Use the Ubuntu session's wallpaper everywhere (see "Black desktop" below).
# On 26.04 these are warty-final-ubuntu.png and ubuntu-wallpaper-d.png.
for k in picture-uri picture-uri-dark; do
  gsettings set org.gnome.desktop.background $k "$(XDG_CURRENT_DESKTOP=ubuntu:GNOME GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background $k)"
done
```

If those files are ever missing, `setup.sh` switches to a plain background color (`picture-options 'none'`). A solid color needs no image file, so the bug can't come back.

Log out, click your name on the login screen, then use the gear icon to pick **GNOME Flashback (Compiz)**. The login screen remembers the choice. Set up effects with CompizConfig Settings Manager (`ccsm`).

Things to know:

- **Black desktop and window trails** mean the wallpaper is missing. Ubuntu sets its wallpaper only for its own session, so Flashback falls back to GNOME's default, `adwaita-d.jxl`, which isn't installed. With no image, the desktop draws nothing and Compiz keeps showing old frames. Setting the wallpaper explicitly (above) fixes it.
- **A full-color monitor icon at the far right of the panel** is the session indicator (log out, shut down). It asks for ubuntu-mono's `system-*-panel` icons, which Yaru doesn't have. `setup.sh` links them into the panel folders that Yaru's theme index lists, under `~/.local/share/icons/<theme>/`, which gives a flat panel icon. The battery icon next to it is the UPS.
- **It's X11 only.** Ubuntu's own session is Wayland-only now, but the login screen can still start other X11 sessions, and Flashback is one of them. A future release could drop that support.
- **Compiz gets no new development.** There have been no upstream releases since 0.9.14.2; Ubuntu keeps rebuilding it because Ubuntu Unity still uses it.
- **Flashback replaces GNOME Shell**, so gnome-panel takes the place of the dock and top bar, and GNOME extensions don't run. Step 6's settings and the custom shortcuts still apply, and on X11 Ulauncher can grab its own hotkey.
