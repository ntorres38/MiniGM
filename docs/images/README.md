# Screenshots

| File | Used by | Shows |
|---|---|---|
| `hud.png` | README, header | The panel on the HUD tab |
| `tele.png` | README, header | The teleport picker — continent, zone and location columns |
| `altlist.png` | README, features | The Add alt flyout with remembered characters |
| `tele-tab.png` | README, features | The Tele tab — Self / Target / Party / Raid |
| `minimap.png` | README, features | The minimap icon tooltip |

## Retaking them

- **`/mgm reset` first.** Anything above scale 1.0 goes soft when GitHub downscales it.
- **Clear the chat frame.** MiniGM echoes every command it sends in gold, and those lines land in the shot — a screenshot of a GM tool with `.die` and `.modify money` visible reads badly.
- **Stand somewhere lit.** A dark cave makes a dark panel unreadable.
- For `tele.png`, pick a zone with plenty of locations so the third column looks full. Elwynn Forest, Stormwind or Dun Morogh all work.
- **PNG, not JPG** — UI text goes mushy under JPEG compression. Crop rather than downscale.
- **Check for character names you would rather not publish.** The chat frame, the player frame and the alt list all show them.

`PrintScreen` writes to `<World of Warcraft>\Screenshots\`.
