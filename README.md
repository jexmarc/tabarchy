# Tabarchy

Single-letter Tab commands on Omarchy's Super+Space menu.

Normal typing still fuzzy-searches apps and the Omarchy command tree. Tab is a
toggle: one letter plus Tab switches into a command, and Tab again returns to
that letter in ordinary search.

```
Super+Space
m Tab
1600 Pennsylvania Ave
Enter
```

opens Google Maps in your default browser. Super+V pastes the clipboard into
the query (Omarchy's universal paste, which the stock menu ignored).

Plugins run unsandboxed inside the long-lived `omarchy-shell` process, with
your user permissions. Review the source before you enable it.

## Install

```bash
omarchy plugin add https://github.com/jexmarc/tabarchy.git --enable
```

From a local checkout:

```bash
omarchy plugin add /path/to/tabarchy --enable
```

Enabling Tabarchy stands in for the stock Omarchy menu so Super+Space, the bar
icon, and `omarchy menu` keep working. This is reversible. Omarchy still has
the original menu; Tabarchy just sits in front of it. See [Restore the stock
menu](#restore-the-stock-menu) if you want it back.

If you previously installed the un-namespaced `tabarchy` id, remove that first:

```bash
omarchy plugin remove tabarchy --yes
```

## Restore the stock menu

Tabarchy does not delete or overwrite Omarchy's menu. The first-party
`omarchy.menu` plugin stays on the machine the whole time. While Tabarchy is
enabled, Omarchy routes Super+Space, the bar icon, and `omarchy menu` to
Tabarchy. When Tabarchy is off, those same bindings go back to the original
menu.

You can check at any time:

```bash
omarchy plugin list
```

With Tabarchy on you should see Tabarchy **enabled** and `omarchy.menu`
**disabled**. That disabled line is the stock menu, waiting to be restored.

### Turn Tabarchy off, keep the files

```bash
omarchy plugin disable io.github.jexmarc.tabarchy
```

Omarchy re-enables `omarchy.menu`. Super+Space is the stock menu again. The
Tabarchy checkout stays under `~/.config/omarchy/plugins/` so you can turn it
back on later:

```bash
omarchy plugin enable io.github.jexmarc.tabarchy
```

### Uninstall Tabarchy

```bash
omarchy plugin remove io.github.jexmarc.tabarchy
```

The CLI disables Tabarchy first, prints `Restored omarchy.menu.`, then deletes
the plugin checkout. Super+Space, the bar icon, and `omarchy menu` are the
stock Omarchy menu again. No Omarchy restart is required.

That also removes the `~/.local/bin/omarchy-tabarchy-search` symlink Tabarchy
created.

### What is left on disk

These are your files. Tabarchy does not create them unless you did, and
removal does not delete them:

```
~/.config/omarchy/tabarchy.jsonc      # optional bang overrides
~/.config/omarchy/defaults/search     # search provider, if you set one
```

They have no effect while Tabarchy is gone. Delete them by hand if you want a
clean slate.

## Use

| Type | Tab | Then |
|---|---|---|
| `m` | maps | an address, Enter |
| `w` | web | a URL, an alias, **or** a search, Enter |
| `f` | files | a filename, Enter to open |
| `i` | install | a package name; pick a result, Enter to install |
| `r` | remove | an installed package; pick a result, Enter to uninstall |
| `?` | help | the command list; Enter opens the highlighted command |

- Tab with a matching letter enters the command; Tab again leaves it.
- Escape clears the argument, then leaves the command, then closes the menu.
- Backspace on an empty argument also leaves the command.
- Super+V or Ctrl+V pastes clipboard text into the current query.
- Ctrl+J / Ctrl+K move the selection down / up while the menu is open
  (same as Down / Up). They are handled only by this overlay, not globally.

Two or more characters never trigger a command, so `ma` still searches the menu.

`w Tab` lists matching aliases as you type, then a URL or a search. Enter
opens the highlighted row. Defaults include `amazon` → amazon.com,
`discord` → discord.com, and `gh` → github.com. Type `amazon.com` or `https://…` to open a URL
directly. Anything else is a web search. The default provider is Google.

Aliases live in `~/.config/omarchy/tabarchy.jsonc` (watched live):

```jsonc
{
  "aliases": {
    "amazon": "https://amazon.com/",
    "discord": "https://discord.com/",
    "gh": "https://github.com/"
  }
}
```

Set an alias to `false` to drop a default. Tabarchy does not read browser
bookmarks; aliases are the supported shortcut list.

Enabling the plugin puts `omarchy-tabarchy-search` on your PATH (`~/.local/bin`).
That symlink is removed when you disable or uninstall Tabarchy. If you already
had a command with that name, enabling Tabarchy replaces the symlink.

The stock `omarchy` dispatcher only loads packaged binaries, so this is the
plugin CLI rather than `omarchy tabarchy search`. The value is stored in
`~/.config/omarchy/defaults/search` and the menu picks it up live.

```
omarchy-tabarchy-search                 # print current provider
omarchy-tabarchy-search google
omarchy-tabarchy-search ddg
omarchy-tabarchy-search brave
omarchy-tabarchy-search --list
omarchy-tabarchy-search 'https://example.com/search?q=%s'
```

## Configure

User config, watched live, optional. Without this file the built-in defaults
still apply:

```
~/.config/omarchy/tabarchy.jsonc
```

A starter file ships in this repo as `tabarchy.jsonc`. Copy it only if you want
to change commands. Tabarchy does not write that file for you. Set a letter to
`false` to disable a default, or add another letter:

```jsonc
{
  "g": {
    "name": "google",
    "icon": "󰊭",
    "placeholder": "search",
    "action": "omarchy-launch-browser \"https://www.google.com/search?q={{query_encoded}}\""
  },
  "i": false
}
```

Placeholders in `action`:

| Token | Meaning |
|---|---|
| `{{query}}` | the rest of the line, shell-quoted |
| `{{query_encoded}}` | URL-encoded |
| `{{url}}` | `https://` prepended if there is no scheme, quoted |

`"kind": "files"` lists `fd` matches under `$HOME` instead of running a command.
The menu is double-wide so longer filenames and paths stay readable.
Enter uses a GUI app when one is registered; markdown and other text open
in the Omarchy editor (`nvim` in a terminal by default) because `xdg-open`
cannot attach a terminal from this overlay.
`"kind": "help"` lists every enabled command (`? Tab`). Enter on a row
opens that command. `"kind": "web"` lists aliases, opens a URL, or falls back to the configured search provider.
Top-level `"aliases"` (or `"aliases"` on the web command) maps names to URLs.
`"kind": "packages"` searches Arch, the Omarchy repo, and the AUR, then
installs the selected package (`omarchy pkg add` or `omarchy pkg aur add`).
`"kind": "remove-packages"` searches only packages already on the machine,
then uninstalls the selected name (`omarchy pkg drop`, which is `pacman -Rns`).

`i Tab` does not install whatever you typed. Official matches (core, extra,
multilib, omarchy) are listed first, then AUR. Already-installed packages stay
in the list with an accent-colored Installed badge and are skipped when moving
through results. The menu is double-wide, matching file search. Every result
stays the same row height, and the highlighted package's description sits in a
pane under the list. Enter opens a terminal to install the selected name.

`r Tab` is the same list, except it only matches installed packages and Enter
removes the selected one. Every hit is selectable.

## Dependencies

Already present on a normal Omarchy install:

- `fd` — file search (`f Tab`)
- `wl-paste` — clipboard paste
- `omarchy-launch-browser` — URLs, maps, and web search
- `xdg-open` / `uwsm-app` — opening files that have a GUI handler
- `omarchy-launch-editor` — markdown, source, and other text when `xdg-open` would launch a terminal editor with no terminal
- `python3`, `pacman`, `yay` — package search (`i Tab`, `r Tab`)
- `omarchy-pkg-add` / `omarchy-pkg-aur-add` — install the selected package (may prompt for sudo)
- `omarchy-pkg-drop` — remove the selected package (`r Tab`, may prompt for sudo)

## Why this stands in for the Omarchy menu

Omarchy's Super+Space menu is `omarchy.menu`. It has no prefix/Tab API, so a
third-party plugin cannot intercept one letter plus Tab without standing in for
that menu. Tabarchy therefore sets `clonedFrom: omarchy.menu`: Super+Space,
`omarchy menu`, and the bar icon keep working. The stock menu is not removed;
see [Restore the stock menu](#restore-the-stock-menu).

That is a stand-in, not a second launcher. Tabarchy-specific code is `Bangs.js`,
`Cli.qml`, `bin/omarchy-tabarchy-search`, and `patches/menu.patch`.
`MenuModel.js` and `BarWidget.qml` are unmodified copies of Omarchy's. `Menu.qml`
is Omarchy's menu plus that patch.

`omarchy plugin update io.github.jexmarc.tabarchy` fast-forwards **this** git
repo. It does not pull Omarchy menu fixes. The menu stays loaded in
`omarchy-shell`, so after an update run `omarchy restart shell` or Super+Space
will still be the previous Tabarchy. After an Omarchy update, rebase the
stand-in onto the new menu:

```bash
~/.config/omarchy/plugins/io.github.jexmarc.tabarchy/scripts/refresh-from-omarchy.sh
omarchy restart shell
```

If the patch no longer applies, the script leaves `Menu.qml` unchanged and
exits non-zero. The plugin keeps working with the last patched menu until the
patch is updated for that Omarchy version.

## License

MIT. Menu files derived from Omarchy's `omarchy.menu` (David Heinemeier Hansson).
Tabarchy additions © 2026 jexmarc.
