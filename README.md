# Ubuntu setup

What I do on a fresh Ubuntu install. Last done on **Ubuntu 26.04 LTS** (GNOME, Wayland).

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
```

## 2. Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Installs to `~/.local/bin/claude`. Make sure `~/.bashrc` has this line (fish gets its own in step 5):

```bash
export PATH="$HOME/.local/bin:$PATH"
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
```

- **`j <dir>`** is [zoxide](https://github.com/ajeetdsouza/zoxide), a maintained successor to autojump. It jumps to the best match among directories you've visited, ranked by how often and how recently. It learns as you `cd`, so it starts empty. It works in both fish and bash, with one shared history. `ji` opens an interactive picker if `fzf` is installed. Note that `which j` prints nothing because `j` is a shell function, not a program on disk; use `type j` to check it.
- **Default terminal**: Ctrl+Alt+T, Nautilus's *Open in Terminal*, and terminal apps all launch through `xdg-terminal-exec`. The user list in `~/.config` overrides Ubuntu's, which lists Ptyxis.

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

## 7. Apps

### MEGAsync

Not in Ubuntu's repos. Install MEGA's .deb for this Ubuntu version. Installing it also adds MEGA's apt repo (`/etc/apt/sources.list.d/megaio.sources`, with its own signing key), so later updates come through `apt upgrade`. It also raises the inotify watch limit so it can watch large folders.

```bash
. /etc/os-release   # VERSION_ID, e.g. 26.04
curl -fLo /tmp/megasync.deb "https://mega.nz/linux/repo/xUbuntu_${VERSION_ID}/amd64/megasync-xUbuntu_${VERSION_ID}_amd64.deb"
sudo apt install -y /tmp/megasync.deb
```

Builds are listed at <https://mega.nz/linux/repo/>. MEGA sometimes skips non-LTS releases (there's no 25.10 build, for example). Open MEGAsync once to log in; it adds itself to autostart. Optional: `nautilus-megasync` adds sync-status icons in Files, but its build lags behind MEGAsync itself.
