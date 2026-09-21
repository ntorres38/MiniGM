# Installing MiniGM

## Requirements

| | |
|---|---|
| Client | WoW **3.3.5a** (build 12340). The `.toc` declares Interface **30300**; do not change it. **This project does not link to, host or help you obtain a game client.** MiniGM is an interface addon — plain Lua that runs inside a client you already have. |
| Server | **AzerothCore**. Other WotLK cores use different command syntax and are untested. |
| Account | A gmlevel high enough for the commands you use — see [COMMANDS.md](COMMANDS.md). |
| Optional | **mod-playerbots** for the Bots section and Party/Raid teleport. |

No libraries, no dependencies.

---

## Install

### 1. Put the folder in place

The addon folder must be named exactly **`MiniGM`** and sit directly inside `Interface\AddOns\`:

```
<World of Warcraft>\Interface\AddOns\MiniGM\
    MiniGM.toc
    MiniGM.lua
    Tele\
        TeleportDB.lua
```

The `Tele` subfolder is **not optional** — the teleport directory lives there, and the `.toc` loads it before the main file.

A very common mistake is ending up with `AddOns\MiniGM\MiniGM\MiniGM.toc` after unzipping. WoW will not find that. The `.toc` must be one level inside `AddOns\MiniGM\`.

### PowerShell

```powershell
$src = "<path to the MiniGM folder you downloaded>"
$dst = "C:\Games\<YourClient>\Interface\AddOns\MiniGM"
New-Item -ItemType Directory -Force -Path "$dst\Tele" | Out-Null
Copy-Item -Force "$src\MiniGM.lua","$src\MiniGM.toc" $dst
Copy-Item -Force "$src\Tele\TeleportDB.lua" "$dst\Tele"
```

`LICENSE`, `README.md`, `CHANGELOG.md` and `docs\` do **not** need to be copied — WoW ignores them.

### 2. Restart the client

**A new addon needs a full client restart.** `/reload` will not find it. Exit to desktop and start the game again.

### 3. Enable it

At the character-select screen, click **AddOns** (bottom-left) and confirm **MiniGM** is listed and ticked. If "Load out of date AddOns" is available, it should not be needed — the interface version is correct for 3.3.5a.

### 4. Verify

Log in. You should see:

```
MiniGM: v1.0 loaded. /mgm to show/hide.
```

Type `/mgm`, then click the **Tele** tab. It should report:

```
loaded - 1306 locations in 143 zones
```

If it says **`FAILED: Tele\TeleportDB.lua did not load`** in red, the `Tele` subfolder did not copy. Go back to step 1.

---

## Updating

For a `.lua`-only update, copy the file over and `/reload` in game:

```powershell
Copy-Item -Force "<src>\MiniGM.lua" "C:\Games\<YourClient>\Interface\AddOns\MiniGM\"
```

If the `.toc` changed, or a file was added or removed from it, you need a **full client restart** instead. The changelog says which.

Your settings live in `WTF\Account\<ACCOUNT>\SavedVariables\MiniGM.lua` and survive updates.

---

## Uninstalling

Delete `Interface\AddOns\MiniGM\`.

To remove your settings too, also delete `WTF\Account\<ACCOUNT>\SavedVariables\MiniGM.lua` and `MiniGM.lua.bak`. Do this with the game closed.

---

## Troubleshooting

### The addon does not appear in the AddOns list

- The folder is named something other than `MiniGM`, or is nested one level too deep.
- `MiniGM.toc` is missing or was renamed. The `.toc` filename must match the folder name exactly.

### It loads, but the Tele tab says the database did not load

The `Tele\TeleportDB.lua` file is missing. Re-copy it. WoW loads it because of this line in the `.toc`:

```
Tele\TeleportDB.lua
```

Note the **backslash** — WoW requires backslashes in `.toc` load lists even on non-Windows clients.

### Buttons do nothing and there is no error

Your gmlevel is below that command's gate. Type `.commands` in game to list what your account may use, and `.help <command>` for one. This is a server permission, not an addon fault.

### "In combat: self-targeting is blocked"

Expected. Speed, Full heal and Revive all are `SecureActionButtonTemplate` macros that self-target with `/target [noexists] player`, which Blizzard forbids while you are in combat. Target yourself manually first, or wait until combat ends.

### Nothing at all happens when I click, and no chat line appears

Every outgoing message is queued at one per 0.4 seconds. If you clicked several buttons quickly, they are still draining. This queue exists because the 3.3.5a client silently drops multiple `SendChatMessage` calls issued in the same frame.

### A Lua error on login

Please open an issue with the full error text and your client build. If you are modifying the addon yourself, syntax-check before loading:

```
luac5.1 -p MiniGM.lua
```

### My layout reset

Saved variables are written on logout or `/reload`, not as you change things. A hard client crash loses anything changed since the last write. `/mgm reset` deliberately clears both windows' position and size.
