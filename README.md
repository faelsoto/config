# Ubuntu setup

What I do on a fresh Ubuntu install. Last done on **Ubuntu 26.04 LTS**, using the GNOME Flashback + Compiz session (step 9).

Step 0 is manual. Everything after it is automated by [`setup.sh`](setup.sh), which follows the same order and is safe to re-run:

```bash
./setup.sh   # run as your normal user, from a terminal in the desktop session
```

Re-running never upgrades anything: packages that are already installed are skipped (`apt install` on an installed package upgrades it when there's a newer version; upgrading is `uu`'s job). If Firefox is open, the script pauses until you close it, because step 3 copies its profile. If any step fails, the script stops and prints which step. Log out and back in when it finishes, so fish becomes the login shell.

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

# Aliases and settings
git config --global alias.st status
git config --global alias.ci commit
git config --global alias.co checkout
git config --global alias.su '!git branch --set-upstream-to=origin/$(git branch --show-current)'
git config --global alias.pr 'pull --rebase'
git config --global push.default current
git config --global rebase.autoStash true
```

### .localignore: keep local-only changes out of commits

A global pre-commit hook, `~/.githooks/pre-commit`, reads `.localignore` at the repo root and unstages every path it lists. The commit goes ahead without them and the changes stay in the working tree: edits to tracked files stay modified, new files go back to untracked. One path per line, relative to the repo root; each line is a git pathspec, so folders (`notes/`) and globs (`*.local.md`) work, and a leading `#` switches a line off. `.localignore` itself is kept out of every repo by the global excludes file.

```bash
mkdir -p ~/.githooks   # then save the hook from setup.sh (step 1) as ~/.githooks/pre-commit
chmod +x ~/.githooks/pre-commit
git config --global core.hooksPath ~/.githooks
git config --global core.excludesFile ~/.gitignore_global
echo .localignore >> ~/.gitignore_global
```

With a global hooks path, a repo's own `.git/hooks` stop running (none of the repos in `~/www` had any). A repo that sets its own `core.hooksPath` (husky does) skips this hook, and so does `git commit --no-verify`.

`git su` points the current branch at the branch of the same name on origin. In fish, `git co` <Tab> offers branch names only (step 5); `git checkout` still completes everything. From the old setup, `color.ui true` is left out because it's been git's default since 1.8.4, and `pull.default` because it isn't a git setting.

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

### Firefox settings

`setup.sh` writes them as an enterprise policy, `/etc/firefox/policies/policies.json`. Firefox reads it at startup, so restart Firefox after changing it. It works on a fresh install before any profile exists, and the policies only set defaults, so everything except translation can still be changed in Settings. `about:policies` shows what's active.

| Setting | Policy |
|---|---|
| No sponsored shortcuts or stories on the New Tab page | `FirefoxHome`: `SponsoredTopSites`, `SponsoredStories` off |
| No sponsored suggestions in the address bar | `FirefoxSuggest`: `SponsoredSuggestions` off |
| No New Tab widgets (lists, timer, clocks…) or weather | `FirefoxHome`: `Widgets.Enabled` and `Weather` off, plus every widget in `Widgets.Blocked`. The master switch alone isn't enough: New Tab updates itself apart from Firefox (`extensions/newtab@mozilla.org.xpi` in the profile), and Mozilla's remote config for it can turn widgets back on. Blocking locks each widget's own pref off, and unknown names are ignored |
| A separate search bar next to the address bar | `SearchBar: "separate"` |
| Keep that search bar | `browser.search.widget.removeAfterDaysUnused` = 36500. Firefox removes the search bar after 120 days unused; 0 would remove it at once |
| Open the previous windows and tabs at startup | `Homepage.StartPage: "previous-session"` |
| No page translation | `TranslateEnabled: false`. This one is locked, so Settings can't turn it back on |
| Don't offer to save passwords (KeePassXC handles them) | `OfferToSaveLoginsDefault: false` (`signon.rememberSignons`). Already saved logins stay and still autofill |
| No spell checker | `layout.spellcheckDefault` = 0 |
| A plain tooltip when hovering a tab, not the big preview card | `browser.tabs.hoverPreview.enabled` = false |
| The address bar always shows the full URL, `https://` included | `browser.urlbar.trimURLs` = false. It's the master switch: with it off Firefox trims nothing, whatever `trimHttps` or Mozilla's experiments say |
| Kagi as the default search engine | `SearchEngines`: add Kagi, make it `Default` |

Kagi's URLs come from its OpenSearch file (`https://kagi.com/opensearch.xml`): results from `https://kagi.com/search?q={searchTerms}`, suggestions from `https://kagisuggest.com/api/autosuggest?q={searchTerms}`. Searches only work while you're signed in to Kagi in Firefox.

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

# Aliases and small functions, one file per shell with the same list (Ubuntu's
# .bashrc loads ~/.bash_aliases). setup.sh (step 5) writes both: aliases for uu,
# ai, opn, s, rt; functions for cc, rtt, pgup, pgdn and gitg.

sudo chsh -s /usr/bin/fish "$USER"                                  # login shell, next login
echo com.mitchellh.ghostty.desktop > ~/.config/xdg-terminals.list   # default terminal

# Ghostty: new windows open in ~
mkdir -p ~/.config/ghostty
printf 'window-inherit-working-directory = false\nworking-directory = home\nkeybind = super+shift+k=clear_screen\n' > ~/.config/ghostty/config.ghostty
```

- **`j <dir>`** is [zoxide](https://github.com/ajeetdsouza/zoxide), a maintained successor to autojump. It jumps to the best match among directories you've visited, ranked by how often and how recently. It learns as you `cd`, so it starts empty. It works in both fish and bash, with one shared history. `ji` opens an interactive picker if `fzf` is installed. Note that `which j` prints nothing because `j` is a shell function, not a program on disk; use `type j` to check it.
- **Aliases**, the same in fish and bash:

  | Alias | Runs |
  |---|---|
  | `cc` | `claude --continue`, or plain `claude` when that fails (there's no conversation to continue in this folder) |
  | `uu` | `sudo apt update && sudo apt upgrade` |
  | `ai` | `sudo apt install` |
  | `opn` | `xdg-open .`: open the current folder in Files |
  | `s` | `subl .`: open the current folder in Sublime Text |
  | `pgup` / `pgdn` | Start / stop the local Postgres, through the systemd user service `postgresql@<major>` (step 7). Each major version has its own data folder, `~/.local/share/postgres/<major>`, because a data folder only opens with the major version that created it. `pgup` starts the version of the project you're in (mise's `pg_ctl` tells which) and returns once Postgres accepts connections. If a server is already running it says so: "already running" for the same version, "run pgdn first" for another one, since all versions use port 5432. `pgdn` works from any folder: it finds the running server (`postmaster.pid` whose process is alive), reads its version from `PG_VERSION` and stops that service; a server started outside the service gets a fast `pg_ctl stop` with its own version's `pg_ctl`. Logs: `journalctl --user -u postgresql@17`. The first time a major version is used, `pgup` asks whether to create its data folder (`initdb --encoding=UTF8 --locale=C.UTF-8 --auth=trust`) and then starts it |
  | `rt` | `rails test -d`; arguments pass through, e.g. `rt test/models/user_test.rb:42`. `-d` (`--defer-output`) prints failures and errors after the run instead of in between the progress dots |
  | `rtt` | `env HEADLESS=no rails test -d` for exactly one test: it takes a single `path/file.rb:LINE` (e.g. `rtt test/system/login_test.rb:42`) and refuses anything else, so a whole suite never runs in a visible browser. The browser only shows in apps whose `application_system_test_case.rb` reads `HEADLESS` |
  | `gitg` | `setsid -f gitg …`: gitg detached from the terminal. The prompt comes back at once, closing the terminal doesn't close gitg, and its log output is dropped. It's a function, not an alias, so the output can be redirected after the arguments |

  `claude --continue` exits with "No conversation found to continue" when the folder has none, so `cc` falls back to plain `claude`. The fallback also runs if a continued session itself exits with an error. `cc` hides the C compiler only when you type it yourself; `make` and scripts still find `/usr/bin/cc`.
- **`git co` completes branches only.** Fish completes a git alias like the command it stands for, so `git co` <Tab> would also offer changed files, tags and recent commits. `~/.config/fish/completions/git.fish` loads fish's own git completions, then removes the `co` → checkout mapping (`set -e __fish_git_alias_co`) and gives `co` the local branches plus the remote branches checkout can track by name. `origin/HEAD` is left out.
- **Default terminal**: Ctrl+Alt+T, Nautilus's *Open in Terminal*, and terminal apps all launch through `xdg-terminal-exec`. The user list in `~/.config` overrides Ubuntu's, which lists Ptyxis.
- **New windows open in `~`**: by default Ghostty opens a new window in the directory of the last window you used. Tabs and splits still do that, which is usually what you want there. After changing the config, press Ctrl+Shift+, in Ghostty to reload it.
- **Super+Shift+K clears the terminal**, screen and scrollback (Ghostty's `clear_screen`, which has no default key on Linux).

## 6. Desktop settings

| Setting | Where in Settings | Value |
|---|---|---|
| Style + accent | Appearance | **Dark**, accent **red** |
| Keyboard layout | Keyboard → Input Sources | **Spanish (Latin American)** |
| Block Ctrl+Q | Keyboard → View and Customize Shortcuts → Custom Shortcuts | name *Block Ctrl+Q*, command `true`, shortcut **Ctrl+Q** |
| Files on Super+E | Keyboard → View and Customize Shortcuts → Custom Shortcuts | name *Files*, command `nautilus --new-window`, shortcut **Super+E** |
| Volume up / down | Keyboard → View and Customize Shortcuts → Sound and Media | **Super+Delete** / **Super+Insert** |
| Mic mute | Keyboard → View and Customize Shortcuts → Sound and Media | **Super+F1** (Help's Super+F1 removed) |
| Play / pause | Keyboard → View and Customize Shortcuts → Sound and Media | **Super+F4** |
| Night Light | Displays → Night Light | **On**, sunset to sunrise, 2800 K (Ubuntu session only; Flashback uses gammastep, step 9) |
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

# Super+E opens Files (same way, path .../custom-keybindings/files/)
kb=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/files/
gsettings set "$kb" name    'Files'
gsettings set "$kb" command 'nautilus --new-window'
gsettings set "$kb" binding '<Super>e'

# Volume and mic (Super+F1 was Help, so clear that first)
gsettings set org.gnome.settings-daemon.plugins.media-keys help "[]"
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-up "['<Super>Delete']"
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-down "['<Super>Insert']"
gsettings set org.gnome.settings-daemon.plugins.media-keys mic-mute "['<Super>F1']"

# Super+F4: play/pause
gsettings set org.gnome.settings-daemon.plugins.media-keys play "['<Super>F4']"

# Night Light
gsettings set org.gnome.system.location enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 2800

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
sudo apt install -y imagemagick   # convert / magick

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

No versions are installed globally; each project picks its own (for example `mise use ruby@3.4 node@22 postgres@18`). Postgres runs with `pgup` / `pgdn` (step 5), one data folder per major version; MySQL the old way, `mysqld_safe --datadir=…`.

**Postgres as a systemd user service.** `setup.sh` writes the template unit `~/.config/systemd/user/postgresql@.service`; `postgresql@17` runs mise's newest installed 17.x on `~/.local/share/postgres/17`. Started from a terminal with `pg_ctl`, Postgres stays in that terminal's systemd scope. At power-off systemd sends SIGTERM to every process in it at once and kills what's left after 90 seconds, so Postgres often doesn't shut down cleanly and the next start runs crash recovery. The unit follows the PostgreSQL docs for systemd: `KillMode=mixed` with `KillSignal=SIGINT` sends a fast shutdown to the main process only, which disconnects clients and stops its own background processes in order, and systemd stops it the same way at power-off. `ExecStartPost` waits for `pg_isready`, so `systemctl --user start` (and `pgup`) return only once Postgres accepts connections, recovery included. It starts only through `pgup`; `systemctl --user enable postgresql@17` would start it at login. A power cut or hard reset still triggers recovery, which is normal and safe. With `libpq-dev` installed, the pg gem builds without the old `bundle config build.pg --with-pg-config=…`. `bundle` on its own keeps meaning `bundle install`: `setup.sh` sets Bundler's `default_cli_command` to `install` in `~/.bundle/config` (`BUNDLE_DEFAULT_CLI_COMMAND: "install"`), which also stops the "In a future version of Bundler…" notice. It's a plain YAML file, so it's written before any Ruby is installed.

## 8. Apps

### Browsers: Google Chrome (for testing) and Brave

Chromium is left out: on Ubuntu it only comes as a snap, and snapd is pinned out.

```bash
curl -fLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y /tmp/chrome.deb    # also adds Google's apt repo for updates

sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
sudo apt update && sudo apt install -y brave-browser

# Brave: Rewards off for every profile (Brave's admin policy; restart Brave)
sudo install -d -m 0755 /etc/brave/policies/managed
echo '{ "BraveRewardsDisabled": true }' | sudo tee /etc/brave/policies/managed/setup.json
```

Brave Rewards is turned off with Brave's `BraveRewardsDisabled` policy, which also removes its toolbar button. Check it in `brave://policy`. The same file can hold Brave's other switches if wanted: `BraveWalletDisabled`, `BraveVPNDisabled`, `BraveNewsDisabled`, and `"BraveAIChatEnabled": false` for Leo.

For system tests, Selenium 4.11+ downloads the matching chromedriver itself, so the old chromedriver install script isn't needed.

### Ulauncher and Flameshot

```bash
sudo add-apt-repository -y ppa:agornostal/ulauncher   # Ulauncher isn't in Ubuntu's repos
sudo apt install -y ulauncher flameshot
systemctl --user enable --now ulauncher.service       # start at login
```

Ulauncher opens with **Alt+Space**. That key normally opens the window menu (Move, Resize, Close…), so the setup unbinds it there first: `activate-window-menu` in GNOME, and `window-menu-key` in Compiz (step 9). On Wayland, Ulauncher can't grab its own hotkey, so a GNOME custom shortcut (*Ulauncher*, command `ulauncher-toggle`) handles it. On X11, Ulauncher's own hotkey (`hotkey-show-app` in `~/.config/ulauncher/settings.json`) works too. Whichever program grabs the key first wins, and both open Ulauncher. `setup.sh` sets all of this.

Flameshot opens with **Ctrl+Shift+Delete** (custom shortcut *Flameshot*, command `flameshot gui`, also added by `setup.sh`). Because it's a global shortcut, browsers no longer get that key; it normally opens *Clear browsing data*. On Wayland, the first capture asks for permission to take screenshots; click **Allow**.

In the capture screen, **Enter** copies the selection to the clipboard and closes. By default that's Ctrl+C, and Flameshot's "accept" action doesn't copy. Flameshot allows one key per action, so Ctrl+C no longer copies there. `setup.sh` writes this to `~/.config/flameshot/flameshot.ini`:

```ini
[Shortcuts]
TYPE_COPY=Return
```

Flameshot's tray icon starts at login. That's Flameshot's own switch, `flameshot config --autostart true`, which writes `~/.config/autostart/Flameshot.desktop`. Captures work without the tray process too.

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

**Sublime key bindings** go in `~/.config/sublime-text/Packages/User/Default (Linux).sublime-keymap` (Preferences → Key Bindings), the same ones as my old setup:

| Keys | Does |
|---|---|
| Ctrl+Tab / Ctrl+Shift+Tab | next / previous tab, in tab order |
| Ctrl+PgUp / Ctrl+PgDn, also with Shift | next / previous tab |
| Ctrl+T | Goto Anything with files (Sublime's Ctrl+P) |
| Ctrl+Shift+7 | toggle line comment: Ctrl+/ on the Latin American layout, where `/` is Shift+7 |
| Ctrl+K Ctrl+K | JsPrettier. It's a package, so the chord does nothing until JsPrettier is installed, and it replaces Sublime's default (delete to end of line) |
| Ctrl+I | autocomplete |
| Ctrl+Shift+] / Ctrl+Shift+[ | indent / unindent |

### gitg

A GUI for browsing a repo's history, from Ubuntu's repos: `sudo apt install -y gitg`. Run `gitg` inside a repo; the shell function in step 5 runs it detached from the terminal.

### Steam and Slack

Steam comes from Ubuntu's multiverse section as `steam-installer`. It needs 32-bit packages. On NVIDIA it also needs the 32-bit build of the driver's OpenGL library (`libnvidia-gl-595:i386` here), or games won't start. `setup.sh` takes that name from the driver that's installed.

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install -y steam-installer libnvidia-gl-595:i386
```

The package is only an installer: the launcher is called **Install Steam**. Opening it asks for confirmation (click **Install**, not Cancel), then downloads the actual Steam client into `~/.steam/debian-installation`. It also replaces the launcher with a **Steam** one in `~/.local/share/applications`. That first run is per user and needs a click, so `setup.sh` leaves it for you.

Slack isn't in Ubuntu's repos. Install its `.deb`, then run the daily cron job it ships (`/etc/cron.daily/slack`) once. That job adds Slack's apt repo (`/etc/apt/sources.list.d/slack.list`) and keeps it up to date, so updates come through `apt upgrade`. Don't add a second source for the same repo yourself: apt rejects the duplicate with "Conflicting values set for option Signed-By". The job puts Slack's keys in `/etc/apt/trusted.gpg.d/`, which apt trusts for every repo; that's Slack's own method.

```bash
# setup.sh picks the newest .deb from https://packagecloud.io/slacktechnologies/slack/debian
sudo apt install -y ./slack-desktop_<version>_amd64.deb
sudo /etc/cron.daily/slack
```

### OnlyOffice (instead of LibreOffice)

OnlyOffice Desktop Editors handles documents, spreadsheets, slides and PDFs in one app. It has a tabbed, Microsoft Office-like interface and the best handling of Word/Excel/PowerPoint files among the free suites. LibreOffice isn't installed on a minimal Ubuntu install, so there's nothing to remove. It's about 1 GB installed.

```bash
# OnlyOffice's key fingerprint must be E09CA29F6E178040EF22B4098320CA65CB2DE8E5
sudo curl -fsSLo /etc/apt/keyrings/onlyoffice.asc https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
sudo tee /etc/apt/sources.list.d/onlyoffice.sources <<'EOF'
Types: deb
URIs: https://download.onlyoffice.com/repo/debian
Suites: squeeze
Components: main
Signed-By: /etc/apt/keyrings/onlyoffice.asc
EOF
sudo apt update && sudo apt install -y --no-install-recommends onlyoffice-desktopeditors
```

It's installed without its recommended packages. Those include `ttf-mscorefonts-installer`, which stops the install for Microsoft's license prompt and downloads the fonts from SourceForge; if that download fails, the install fails. The fonts OnlyOffice requires already include stand-ins with the same metrics: Carlito for Calibri, and Liberation for Arial and Times New Roman. So documents keep their layout. For the exact Microsoft fonts, run `sudo apt install ttf-mscorefonts-installer` separately and accept the license.

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
  compiz-plugins-extra compizconfig-settings-manager gammastep

# Only if Flashback's wallpaper file is missing (see "Black desktop" below): use
# the Ubuntu session's instead. On 26.04 that's ubuntu-wallpaper-d.png for dark mode.
k=picture-uri-dark
gsettings set org.gnome.desktop.background $k "$(XDG_CURRENT_DESKTOP=ubuntu:GNOME GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background $k)"
```

`setup.sh` checks before touching the wallpaper or the lock screen picture, and leaves a picture you chose alone as long as its file exists. It reads each key the way Flashback does (`XDG_CURRENT_DESKTOP=GNOME-Flashback:GNOME gsettings get …`), which gives your own pick if you made one and Flashback's default otherwise, then tests the file with `gio info`. Only a missing file is replaced: the desktop gets the Ubuntu session's wallpaper, and the lock screen gets the desktop's dark-mode wallpaper. If the replacement is missing too, it uses a plain color (`picture-options 'none'`), which needs no image file.

Log out, click your name on the login screen, then use the gear icon to pick **GNOME Flashback (Compiz)**. The login screen remembers the choice. Set up effects with CompizConfig Settings Manager (`ccsm`).

**Desktop cube, 4 faces.** `setup.sh` sets four viewports side by side (`hsize 4`, `vsize 1`), turns on the `cube` and `rotate` plugins, and turns off `wall`, which uses the same keys to slide between viewports:

| Keys | Does |
|---|---|
| Ctrl+Alt+Left / Right | rotate the cube |
| Ctrl+Alt+Shift+Left / Right | rotate and take the current window along |
| Ctrl+Alt + drag with the mouse | spin the cube freely |
| Super+S | overview of all four faces (expo) |
| Alt+Tab / Ctrl+Alt+Tab | switch windows on this face / on all faces (`switcher` plugin) |
| Alt + drag / Alt + middle-drag / Alt + right-click | move / resize / window menu |
| Super + mouse wheel up / down | magnify in / out (`ezoom`; Ubuntu ships its bindings disabled) |

The plugin order follows the plugins' declared dependencies: `cube` after `decor` and before `scale`/`expo`, and `rotate` after `cube`. Everything else in the active list stays as it was.

**Compiz's GNOME integration is turned off.** Compiz's settings library can read some Compiz options from GNOME's settings instead, and rotate's keys are among them, taken from GNOME's "switch to workspace" shortcuts. GNOME stores those as lists, but the integration expects a single string. It logs `compizconfig - Error: Expected string value`, and the cube gets no keys at all. `setup.sh` sets `integration = false` in `~/.config/compiz-1/compizconfig/config`, so Compiz uses its own settings, which are mostly Compiz's defaults (the table above). The exception is Compiz's own terminal and screenshot keys, which are disabled. They would run `gnome-terminal` and `gnome-screenshot`, which aren't installed, so Flashback keeps handling Ctrl+Alt+T and Print.

The plugin list also gets `switcher`, which handles Alt+Tab. Ubuntu's stock Flashback list includes it, but this machine's list didn't. It goes at the end because it has to load after `cube`.

Things to know:

- **Black desktop and window trails** mean the wallpaper is missing. Ubuntu sets its wallpaper only for its own session, so Flashback falls back to GNOME's default, `adwaita-d.jxl`, which isn't installed. With no image, the desktop draws nothing and Compiz keeps showing old frames. Setting a wallpaper whose file exists (above) fixes it.
- **A solid black lock screen** (the Password / Switch User / Unlock dialog) is the same problem. Flashback's lock screen draws the *screensaver* background, `org.gnome.desktop.screensaver picture-uri`, which falls back to GNOME's `adwaita-timed.xml`, also not installed. If that picture is missing, `setup.sh` points it at the desktop's dark-mode wallpaper, like GNOME Shell's lock screen in the Ubuntu session. This isn't the login screen, which is GDM, a separate program with its own theme and a `#222222` background.
- **Super+S is also the panel's session-menu key.** The indicator applet at the right of the top panel (`indicator-complete`) has Super+S hard-coded to open the Log Out / Suspend menu, with no setting to turn it off. X gives a key to whichever program grabs it first. At login, Compiz loads expo about a second before the panel loads its applets, so expo wins. If Super+S ever opens that menu instead of expo, log out and back in. To fix it without logging out, unload expo, run `systemctl --user stop gnome-panel.service`, load expo again, then start the panel.
- **Desktop icons can be dragged anywhere, and snap to the grid.** Flashback's default `placement` is `auto-arrange-icons`, which keeps them in a sorted grid. `setup.sh` sets it to `align-icons-to-grid`; `free` would skip the snapping.
- **A full-color monitor icon at the far right of the panel** is the session indicator (log out, shut down). It asks for ubuntu-mono's `system-*-panel` icons, which Yaru doesn't have. `setup.sh` links them into the panel folders that Yaru's theme index lists, under `~/.local/share/icons/<theme>/`, which gives a flat panel icon. The battery icon next to it is the UPS.
- **The workspace switcher marks the current face in red.** It draws the current face in GTK's *selected* state, which Yaru doesn't style for this panel, so all four faces looked the same. `setup.sh` adds one rule to `~/.config/gtk-3.0/gtk.css`: `wnck-pager:selected { background-color: @theme_selected_bg_color; }`, the theme's own red. Apps read that file when they start, so restart the panel to see it: `systemctl --user restart gnome-panel.service`.
- **Night Light doesn't tint the screen in Flashback.** GNOME computes it, but only GNOME Shell applies it to the screen. gammastep (redshift's successor) does it instead, with the values from my old redshift config: 4000 K by day, and 2800 K at 55% brightness at night. Redshift's `transition` is called `fade` now. Day and night follow the actual sunset and sunrise, using the location from GeoClue, whose agent Ubuntu starts in Flashback. No coordinates are stored. The config is `~/.config/gammastep/config.ini`. It's started through `gammastep-indicator`, which adds a tray icon for switching it on and off, by `~/.config/autostart/gammastep.desktop`. That entry has `OnlyShowIn=GNOME-Flashback`, so it never runs in the Ubuntu session. Changing Night Light in Settings doesn't affect Flashback; edit that file instead.
- **It's X11 only.** Ubuntu's own session is Wayland-only now, but the login screen can still start other X11 sessions, and Flashback is one of them. A future release could drop that support.
- **Compiz gets no new development.** There have been no upstream releases since 0.9.14.2; Ubuntu keeps rebuilding it because Ubuntu Unity still uses it.
- **Flashback replaces GNOME Shell**, so gnome-panel takes the place of the dock and top bar, and GNOME extensions don't run. Step 6's settings and the custom shortcuts still apply, and on X11 Ulauncher can grab its own hotkey.
