# Attribution and licensing

## Short version

MiniGM is **GPLv3**, and that is required rather than chosen.

MiniGM's own code is original. Its teleport data is derived from a GPLv3 work, which makes MiniGM a derivative work, and derivative works carry the same licence. Credit alone does not satisfy the licence — the licence is a licensing obligation, not an attribution one. Both are honoured here.

---

## What is borrowed

| From | What | Licence |
|---|---|---|
| **[AzerothAdmin](https://github.com/superstyro/AzerothAdmin)** | The 1,306 teleport coordinates in `Tele/TeleportDB.lua`, derived from its `Data/TeleportTable.lua` | GPLv3 |

That is the entire list. No AzerothAdmin *code* is used — the UI, the command layer, the queue, the picker and the minimap button are all original. The data was regrouped, nine corrupt coordinate strings were repaired, and one duplicate was dropped; see [TELEPORT-DATA.md](TELEPORT-DATA.md) for the full record.

### The lineage

```
MangAdmin  →  TrinityAdmin  →  AzerothAdmin  →  MiniGM
                                   (data only)
```

AzerothAdmin is credited to the **SuperStyro Dev team + Manground Dev Team** and is itself a derivative of TrinityAdmin/MangAdmin. Its own source headers carry the GPLv3 notice back to the Free Software Foundation, 2007.

---

## What GPLv3 requires of you

If you redistribute MiniGM, modified or not:

- Keep it under **GPLv3**. You cannot relicense it MIT or "free to use".
- Ship the **full licence text** — the `LICENSE` file in this repository.
- Make the **source available** to anyone who receives it. For a Lua addon this is automatic; the source *is* what you shipped.
- **State that you modified it**, and what changed, if you did.
- Keep the existing copyright and licence notices intact, including the header block at the top of `MiniGM.lua`.

If you only use MiniGM yourself and never pass it on, none of this applies. GPLv3 obligations attach to distribution, not to use.

**Nothing here costs money and nothing requires anyone's permission.** GPLv3 grants the right to use, modify and redistribute outright; the only condition is that the result carries the same freedoms forward.

---

## Not affiliated with

MiniGM is an independent project. It is not endorsed by or affiliated with AzerothCore, mod-playerbots, AzerothAdmin, or Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.

---

## Also credited

Not borrowed from, but MiniGM would not exist without them:

- **[AzerothCore](https://www.azerothcore.org/)** — the server, and the [GM command reference](https://www.azerothcore.org/wiki/gm-commands) that documents everything the addon sends.
- **[mod-playerbots](https://github.com/liyunfan1223/mod-playerbots)** — every bot command in the Bots section and the Party/Raid teleport.
