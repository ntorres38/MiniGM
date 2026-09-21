# Contributing to MiniGM

## Before anything else

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), particularly §10 — the 3.3.5a API traps. Most of them cost real debugging time to find, and most are not obvious from modern WoW addon habits.

## A note on how this was built

The Lua and the documentation were written with AI assistance (Claude). The design decisions and testing were the author's. If you find something that looks confidently wrong, that is a real possibility here — two such bugs shipped during development and both were caught by playing the game rather than by reading the code. Report them.

## Ground rules

**Keep it dependency-free.** No Ace3, no LibStub, no LibDBIcon. Two files you can read end to end is the point of this addon. A pull request that adds a library needs to argue why the trade is worth it.

**Keep it client-only.** MiniGM sends chat commands and nothing else. No server module, no addon-message protocol, no chat scraping. If a feature needs to read the server's replies, that is an architectural change — open an issue first.

**Guard before you send.** Every destructive action refuses up front rather than asking afterwards. Anything acting on the user's own character requires typing `Accept`.

**Never hook chat.** Do not hook `AddMessage` or install chat filters. That is how addons end up swallowing other addons' messages.

**Private link prefixes only.** If you add clickable chat links, use `|Hminigm:…|h` and match only that. Matching bare `spell:` or `item:` prefixes hijacks links other people post.

## Working on it

Edit files in place. Do not re-type a file's contents from tool output — it truncates.

**Syntax-check before loading.** A Lua error on login can lock you out of the UI:

```
luac5.1 -p MiniGM.lua
luac5.1 -p Tele/TeleportDB.lua
```

**Reloading.** A `.lua` change needs `/reload`. A `.toc` change, or adding or removing a file from it, needs a **full client restart**.

**Testing is manual, in game.** There is no harness. At minimum, after any change: log in clean, check for Lua errors, open both tabs, resize both windows, `/reload`, and confirm everything came back where you left it.

## Generated files

`Tele/TeleportDB.lua` is generated. **Do not hand-edit it** — the header says so, edits are lost on the next rebuild, and hand-edits are how malformed coordinates get in. To add locations of your own, use a separate file loaded after it; see [docs/TELEPORT-DATA.md](docs/TELEPORT-DATA.md).

## Changelog

**Update `CHANGELOG.md` in the same commit.** Use the existing prefixes: `ADD`, `REMOVE`, `FIX`, `IMPROVE`, `CHANGE`, `NOTE`. Write entries for users, not for the diff — say what changed and, when it was a bug, say what was actually wrong. The 3.2 and 3.0.1 entries are the house style.

Bump `## Version:` in `MiniGM.toc` **and** `local VERSION` in `MiniGM.lua`. They must match.

## Cutting a release

The release zip is **not** the source zip. GitHub's auto-generated one extracts to `MiniGM-main`, which WoW won't load without a rename. Build a proper one:

```powershell
$v = "1.0.0-rc"
$stage = "$env:TEMP\MiniGM-pkg"
Remove-Item -Recurse -Force $stage -EA SilentlyContinue
New-Item -ItemType Directory -Force -Path "$stage\MiniGM\Tele" | Out-Null
Copy-Item MiniGM.toc, MiniGM.lua, LICENSE, README.md "$stage\MiniGM"
Copy-Item Tele\TeleportDB.lua "$stage\MiniGM\Tele"
Compress-Archive -Force -Path "$stage\MiniGM" -DestinationPath "..\MiniGM-Addon-$v.zip"
```

Then draft a release against the matching tag and attach that file.

**The `-Addon-` in the filename is not decoration.** GitHub auto-attaches a "Source code (zip)" to every release, and for tag `v1.0.0-rc` that file is named `MiniGM-1.0.0-rc.zip` — identical to what you would naturally call the packaged one. Two files with the same name on the same page, one of which does not work, is how people end up with a folder called `MiniGM-1.0.0-rc` in their AddOns directory wondering why nothing loaded.

`LICENSE` is in the zip deliberately. A release is distribution, and GPLv3 asks for the licence text to travel with the work. `README.md` is there so anyone who only has the zip knows where it came from. WoW ignores both.

## Licence

MiniGM is **GPLv3**, and not by choice — see [docs/ATTRIBUTION.md](docs/ATTRIBUTION.md). Contributions are accepted under the same licence. Do not paste in code from a non-GPL-compatible source.
