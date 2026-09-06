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

## Install

From this checkout:

```bash
omarchy plugin add /home/mgallagher/dev/tabarchy --enable
```

From git once the repo is on GitHub:

```bash
omarchy plugin add https://github.com/<you>/tabarchy.git --enable
```

Enabling Tabarchy stands in for the stock Omarchy menu. Super+Space, the bar
icon, and `omarchy menu` keep working. Disable or remove it to get the stock
menu back:

```bash
omarchy plugin disable tabarchy
omarchy plugin remove tabarchy --yes
```

## Use

| Type | Tab | Then |
|---|---|---|
| `m` | maps | an address, Enter |
| `w` | url | `amazon.com`, Enter |
| `f` | files | a filename, Enter to open |
| `i` | install | a package name, Enter |

- Tab with a matching letter enters the command; Tab again leaves it.
- Escape clears the argument, then leaves the command, then closes the menu.
- Backspace on an empty argument also leaves the command.
- Super+V or Ctrl+V pastes clipboard text into the current query.

Two or more characters never trigger a command, so `ma` still searches the menu.

## Configure

User config, watched live:

```
~/.config/omarchy/tabarchy.jsonc
```

A starter file ships in this repo as `tabarchy.jsonc`. Set a letter to `false`
to disable a default, or add another letter:

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

## Why this is a menu plugin

Omarchy's Super+Space menu is `omarchy.menu`. Tab has to be handled in that
surface, so Tabarchy replaces it the same way `omarchy plugin clone omarchy.menu`
does (`clonedFrom: omarchy.menu`). The command tree, apps search, and dmenu
select/input modes stay intact.
