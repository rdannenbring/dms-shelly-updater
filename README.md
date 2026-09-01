# Shelly Updater

## Type: DankBar Widget

A comprehensive system-update widget for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
backed by the [Shelly (ALPM)](https://github.com/Seafoam-Labs/Shelly-ALPM) CLI.

It unifies **pacman**, **AUR**, **Flatpak** and **AppImage** updates into a single
DankBar pill with a detailed updates view and an action menu.

It also counts things Shelly doesn't manage. **DMS plugins** and **device firmware** are
built in and have their own settings toggles. Everything else is **defined in a config
file** — no code, no rebuild: name a command that lists what's outdated, say how to read
its output, say how to apply an update. The shipped config comes with **mise** and
**Rust toolchains** enabled, plus **npm globals** and a **Flatpak remote** entry switched
off as worked examples to copy. See [Adding your own sources](#adding-your-own-sources).

> ⚠️ **Requires Shelly v3 or newer.** Shelly 3.0 reworked its command-line grammar
> (`shelly <verb> <type>` instead of `shelly <type> <verb>`), which **breaks plugin
> versions before 2.0.0**. If your updates suddenly stop appearing after a Shelly
> upgrade, update this plugin to **2.0.0+**. Conversely, 2.0.0 targets the v3 CLI and
> will not work on Shelly v2. The widget detects an unsupported Shelly and shows a
> clear "requires Shelly v3" banner instead of silently failing.

## Screenshots

| Updates view | Action menu |
|:---:|:---:|
| ![Updates view](preview/updates.png) | ![Action menu](preview/menu.png) |
| **Control-center panel** | **AI failure analysis** |
| ![Control-center panel](preview/control-center.png) | ![AI failure analysis](preview/ai-suggestion.png) |
| **Update history** | **Hover tooltip** |
| ![Update history](preview/history.png) | ![Tooltip](preview/tooltip.png) |

## Features

- One pill for all update sources (pacman always on; AUR / Flatpak / AppImage toggleable),
  with an option to exclude devel / `-git` AUR packages
- **Two built-in non-Shelly sources**, each with its own settings toggle, on by default, and each
  hidden automatically when its command isn't installed:
  - **DMS plugins** (`dms`) — updates to your installed DankMaterialShell plugins. Checkouts an
    update can't actually move are skipped by default (**Ignore plugins you've customized**): one on
    a branch with no counterpart on `origin`, tracking a fork, or carrying local edits or unpushed
    commits. `dms plugins update` pulls the branch you're *on*, so for these it reports success and
    changes nothing, leaving them listed as updatable forever. Only local git refs are consulted, so
    the test costs no network. Shelly Updater lists **its own** updates too
    (**Offer updates to Shelly Updater**, on by default) — otherwise someone using this widget as
    their one place to see what needs updating would never learn the widget itself is behind.
    Updating it rewrites its own folder and DMS reloads it, so it is never included in *Update All*;
    it is updated deliberately from its own row. Switch it off and the updates view still tells you
    when a new version is out
  - **Device firmware** (`fwupdmgr`) — fwupd/LVFS updates. **Listing only**: firmware is never applied
    silently and is never swept up by *Update All*. Applying it always opens a terminal and runs
    `fwupdmgr`'s own prompts, because a bad flash is the one update here that can brick hardware
- **Any other source, defined in config** — `~/.config/DankMaterialShell/shelly-updater-sources.json`
  describes a source with a command, a way to read its output (a regex or a JSON field map), and a
  way to apply an update. These have no settings toggle: the file *is* their configuration, and each
  entry carries its own `enabled` flag. Entries whose command isn't installed are skipped silently,
  so a file can safely cover tools you only have on some machines. Ships with **mise** and **rustup**
  enabled, and **npm globals** plus a **Flatpak remote** entry disabled as templates.
  See [Adding your own sources](#adding-your-own-sources)
- Configurable automatic checks (15 min, 30 min, 1 hr, 4 hr, once a day) and check-at-startup
- **Updates view** (default left click) — every pending update grouped with descriptions and
  download size, an **Update All** button, and a per-item update button
  - **Text filter** to search by name / description / version / source
  - **Sort** by type (pacman → aur → devel → flatpak → appimage) or name
  - Click a package for an extended **detail view** (info, clickable URL, hold/unhold,
    downgrade, update-this-package); right-click a pacman/AUR row to **hold** (ignore) it
- **Menu** (default right click) — Update All, Update System (Pacman), Update AUR / Flatpak /
  AppImage (hidden when disabled), one row per enabled non-Shelly source, **Held Packages**, **Update History**, Clean Package Cache, Remove Orphans,
  Open Shelly UI, **Reset** (clear a stuck refresh/upgrade state), and Settings
- **Hold anything** — right-click an update (or use **Hold** in its details) to pin it out of the
  count and list. pacman and AUR packages go through `shelly mark ignore`; everything else is held
  locally by the plugin. Useful for a source that keeps reporting something it can't actually
  apply — a plugin checked out on a feature branch, say. All of them appear together under
  **Held Packages**, unholdable in one click
- **Update History** — successful upgrades/downgrades (from `/var/log/pacman.log`) merged with
  the plugin's own failed-update log; text filter, sort by date or name, and a **failed-only** toggle
- **Failed-update detection** — after an upgrade, packages that didn't apply are flagged in red and stay
  surfaced until actually resolved (updated, held, dismissed, or succeeded on a later run); each failure
  keeps a captured log excerpt and is clickable for detail. History retention is bounded by **age (days)
  or size (MB)**, whichever is hit first
- **AI failure analysis** (optional) — plug in your own AI CLI (e.g. `claude -p`, `opencode run`, `ollama`,
  `gemini`) to suggest a fix for a failure. Suggested shell commands get **copy** and **run-inline** buttons
  (with streamed output), and you can hold a short follow-up conversation. CLI-based by design — no API keys
  are stored, and subscription CLIs work without API credits. The prompt is fully user-editable
- **Interactive re-run** — when an update needs review (e.g. a changed AUR PKGBUILD that a non-interactive
  run silently skips), a button re-runs that package in a terminal that **stays open** so you can read the
  output and answer any prompts. Available in the failure detail and on each update row
- **Arch news banner** — surfaces unread [Arch Linux news](https://archlinux.org/news/) (manual-intervention
  notices, etc.) in the updates view *before* you upgrade, so breaking changes don't catch you out
- **Control-center widget** — a compound tile with an in-panel **Menu | Updates** view (plus drill-in to
  history and failure detail) for the DankMaterialShell control center
- Optional desktop **notifications** — when a background check finds new updates (minimum-count threshold),
  and when an upgrade leaves failures (with actions to view details or get an AI explanation)
- **Performance** — optionally run updates at lower CPU/IO priority (`nice`/`ionice`) and cap parallel
  build jobs, so large AUR builds don't peg the machine
- Configurable left / middle / right click actions
- **Per-source logos** — each source is drawn with its own mark (Pac-Man-style disc for pacman,
  Arch for AUR, Flatpak, AppImage, Dank for DMS plugins, mise, Rust) in the menu and on each update
  row, bundled locally so the widget never fetches anything to draw itself. **Tint source logos with
  theme color** (on by default) maps each mark onto your accent so they move with your palette;
  turn it off for the original brand colors. Warning chips (`failed` / `kernel` / `devel`) always
  win over the logo, since a brand mark would bury them
- Custom icons for the up-to-date and updates-available states
- Optional update count text with configurable position (horizontal: left/right, vertical: top/bottom)
- Optional hover tooltip with per-source counts and (optionally) package names
- Runs updates in your preferred terminal (defaults to `$TERMINAL`), with an option to close it when done
- Confirmation prompts toggle (off ⇒ `--no-confirm`), plus an always-confirm-kernel-updates option
- Multi-monitor aware — checks and the "updating" state stay in sync across every bar instance

## Prerequisites

Install the Shelly CLI (**v3 or newer** — see the requirement note above):

```sh
sudo pacman -S shelly        # official repo
# or
yay -S shelly                # AUR helper
```

The GUI entry (`Open Shelly UI`) launches `shelly-ui`, which ships with the same package.
If updates ever get wedged behind a stale package-database lock, clear it with
`shelly utility --repair-db`.

### Running updates without password prompts (optional)

Applying updates needs root. To skip the terminal password prompt, add a passwordless
sudoers rule for Shelly (review carefully — this grants passwordless root package management):

```sh
echo "$USER ALL=(root) NOPASSWD: /usr/bin/shelly" | sudo tee /etc/sudoers.d/shelly-nopasswd
sudo chmod 440 /etc/sudoers.d/shelly-nopasswd
```

Then run `shelly utility --fix-permissions` once.

## How it queries Shelly

The widget shells out to Shelly's JSON mode, using the **Shelly v3 grammar**
(`shelly <verb> <type>`):

| Source   | Check command                          | Apply command             |
|----------|----------------------------------------|---------------------------|
| pacman   | `shelly list-updates standard --json`  | `shelly upgrade standard` |
| AUR      | `shelly list-updates aur --json`       | `shelly upgrade aur`      |
| Flatpak  | `shelly list-updates flatpak --json`   | `shelly upgrade flatpak`  |
| AppImage | `shelly list-updates appimage --json`  | `shelly upgrade appimage` |
| All      | —                                      | `shelly upgrade all`      |

Per-item updates use `shelly update standard|aur|flatpak <pkg>` (an interactive
re-run drops `--no-confirm` so review prompts appear). Package detail comes from
`shelly search standard|aur <pkg> --json`, holding from `shelly mark ignore`,
downgrades from `shelly downgrade`, cache/orphan cleanup from
`shelly purify standard -c` / `-o`, and the pre-upgrade news banner from
`shelly news -a --json`. Update History is read directly from `/var/log/pacman.log`
(Shelly has no history command), with failed updates recorded by the plugin itself.

> **Upgrading from Shelly v2?** Everything above changed in Shelly 3.0 — older
> plugin versions call the v2 forms (`shelly aur list-updates`, `shelly upgrade-all`,
> `shelly ignore`, …) which no longer exist, so they silently show nothing. Plugin
> **2.0.0** is the release that targets the v3 grammar.

## Sources beyond Shelly

A source is defined by its command, how to read that command's output, how to apply an
update, and how long results stay cached — the same four things whether it ships with the
plugin or you add it yourself. Only **two** are built in; everything else is config.

**Built in** — settings toggle, on by default:

| Source      | Check command                        | Apply command                |
|-------------|--------------------------------------|------------------------------|
| DMS plugins | `dms plugins update --all --check`   | `dms plugins update --all`   |
| Firmware    | `fwupdmgr get-updates --json`        | `fwupdmgr update` *(manual)* |

**In the config file** — no settings toggle; switched with each entry's `enabled` flag, and
editable or removable like anything else you add:

| Source          | Check command                                | Apply command                          | Ships as |
|-----------------|----------------------------------------------|----------------------------------------|----------|
| mise            | `mise outdated --json`                       | `mise upgrade`                         | enabled  |
| rustup          | `rustup check`                               | `rustup update`                        | enabled  |
| npm (global)    | `npm --global outdated --json`               | `npm --global install <pkg>@latest`    | disabled |
| Flatpak remotes | `flatpak remote-ls --updates`                | *(listing only)*                       | disabled |

The two disabled entries are templates: enable one, or copy it as the starting point for a
tool of your own.

Two design points apply to every source above, built-in or config:

- **Results are file-backed, not per-widget.** A bar widget exists once per monitor, and
  `dms plugins update --check` is a ~40 s network call — so a refresh runs *once* under a
  lock, writes each source's raw output under `~/.cache/shelly-updater/`, and every
  instance simply reads those files. How long a source's results stay cached is per-source
  (`minIntervalHours`, default 6); firmware, a local daemon query, refreshes every cycle.
  Applying an update clears that source's cache immediately, and the refresh button forces
  a real re-check — so an item never lingers after you have actually updated it.
- **Failure detection and AI analysis stay Shelly-only.** Those parse pacman/makepkg build
  logs and would mis-read a firmware or plugin run, so external sources are excluded from
  them by design.

Each source disappears entirely when its command isn't installed, so leaving one enabled
costs nothing on a machine that doesn't have the tool.

### Adding your own sources

Extra sources live in `~/.config/DankMaterialShell/shelly-updater-sources.json`, seeded on first
run from [`examples/shelly-updater-sources.json`](examples/shelly-updater-sources.json). An
existing file is never overwritten, so your edits survive upgrades. Reload after editing:

```sh
dms ipc call plugins reload shellyUpdater
```

> ⚠️ **`listCmd`, `applyAll` and `applyOne` are executed as you.** Treat a sources file from
> someone else exactly like a shell script from someone else.

A source names a command, says how to read its output, and says how to apply an update:

```json
{
  "id": "npmGlobal",
  "label": "npm (global)",
  "icon": "javascript",
  "bin": "npm",
  "listCmd": ["npm", "--global", "outdated", "--json"],
  "parse": { "type": "json", "iterate": "object",
             "name": "$key", "current": "current", "latest": "latest" },
  "applyAll": ["npm", "--global", "update"],
  "applyOne": ["npm", "--global", "install", "{id}@latest"],
  "minIntervalHours": 12,
  "enabled": true
}
```

| Field | Meaning |
|---|---|
| `id` | Short unique name; also the chip label. Can't collide with a built-in source |
| `bin` | Command that must exist — if it doesn't, the source is hidden entirely |
| `listCmd` | argv that prints what's outdated |
| `parse` | How to read that output (below) |
| `applyAll` | argv updating everything. Omit to make the source listing-only |
| `applyOne` | argv updating one item; `{id}` `{name}` `{current}` `{latest}` are substituted |
| `env` | `NAME: value` pairs prepended to the command. Values are emitted inside double quotes, so `$HOME` and `$PATH` expand — keep them simple, nested quoting won't work |
| `minIntervalHours` | How long results stay cached. Keep this high for anything hitting the network (default 6) |
| `readOnly` | `true` = never applied in-widget or by *Update All*, only handed to a terminal |
| `note` | One-line caveat shown under the menu row |
| `enabled` | `false` keeps an entry on file without using it |

**Two parse shapes** cover essentially every update tool, because they all print either one line
per outdated thing or a JSON collection of them:

```json
{ "type": "regex", "pattern": "^(\\S+) - update available: (.+?) -> (.+)$",
  "name": 1, "current": 2, "latest": 3, "strip": "\\s*\\(.*\\)\\s*$" }
```
Scans stdout line by line; `name` / `id` / `current` / `latest` are capture-group **numbers**.
`strip` is a second pattern removed from both versions (for tools that append build metadata),
and `exclude` drops matching ids.

```json
{ "type": "json", "root": "Devices", "iterate": "array",
  "name": "Name", "current": "Version", "latest": "Releases.0.Version",
  "require": "Releases.0.Version" }
```
Field values are **dotted paths** resolved per record, so `Releases.0.Version` reaches into
nested arrays. `$key` yields the object key when iterating an object, `root` is a path to the
collection, and `require` skips records missing that path. Records whose `latest` equals their
`current` are dropped automatically.

#### Your shell's environment is not the widget's

The commands above run in the **DMS service environment**, not in your shell — nothing sources
your `~/.zshrc`. For system-wide tools that's fine. For anything installed by a version manager
(nvm, pyenv, rbenv, asdf) it is not: the widget resolves a *different* install than your terminal
does, and you get updates reported for a package set you never touch.

The symptom is distinctive: **you update something, it succeeds, and it's still listed.**

Fix it by pinning the toolchain with `env`, which applies to both the check and the apply so the
two can't disagree:

```json
"env": { "PATH": "$HOME/.config/nvm/versions/node/v24.14.0/bin:$PATH" }
```

The shipped `npmGlobal` example does this. Point it at your own bin directory, and update it when
you change node versions. Avoid globbing the version out (`.../node/*/bin`) — values are emitted
inside double quotes, so the inner quoting a glob needs doesn't survive, and a glob that matches
nothing silently leaves an empty entry on `PATH`.

A bad entry is skipped **on its own** — one typo can't take the other sources down — and the
reason appears in the updates view, naming the entry and what's wrong with it. A source whose
`bin` isn't installed is skipped silently, which is what makes it safe to keep entries on file
for tools you only have on some machines.

### Logo assets

`assets/` holds one SVG per source. Marks drawn in plain ink (mise, Rust) ship as a
light/dark pair — the base file is inked dark for light backgrounds, the `-dark` file
inked light for dark ones — and are selected via `Theme.isLightMode`. Everything else is
a single brand-colored file that reads on either. `assets/pacman.svg` is original artwork
(a circle with a wedge removed, plus two pellets), not traced from any game asset.

Every mark is drawn in a **single color with its detail as negative space**, so tinting is a
straight color replacement (`ColorOverlay`) that keeps only the alpha. That matters: the
obvious alternative, `MultiEffect` colorization, shifts hue and saturation but *preserves
lightness*, which means pure-ink marks can't move at all (white stays white) and every other
mark comes out as dim as its own brand color happens to be — Arch and Flatpak have under half
the relative luminance of Pac-Man's yellow and rendered visibly darker than their neighbours.
With color replacement they all land on exactly the accent. Colorization remains as the
fallback for any future multi-tone asset added without `flat: true`.

`assets/appimage.svg` is redrawn for this reason: upstream it's a gradient-shaded plate with
the arrow and cog painted on top, which can't be flat-tinted. Here those are knocked out of
the plate instead (`fill-rule="evenodd"`), which both fixes the tinting and keeps the shapes
legible at 22px.

Dropping a source from the `sourceAssets` map in `ShellyUpdater.qml` makes it fall back to a
Material Symbol, which is also what firmware uses (no vendor mark suits it).

Logos are the trademarks of their respective projects and are used here only to identify
those projects.

## Installation (development)

Symlink this directory into the DankMaterialShell plugins folder:

```sh
ln -s "$PWD" ~/.config/DankMaterialShell/plugins/shellyUpdater
```

Then enable **Shelly Updater** from DankMaterialShell → Settings → Plugins, and add the
widget to a DankBar section.

## License

MIT
