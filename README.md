# Steal-a-Dino

A steal-and-collect Roblox game kit in Luau. Eggs travel on a belt — you buy one, it hatches into a dinosaur on your base, the dino earns you money every second, and other players can steal your dinos and carry them home. Above all dinosaurs sit the **dragons**: the supreme breed.

Made by Naçreddine Hasba.

## The core loop

1. **Eggs on the belt** — eggs appear at one end of a long belt and travel to the other. Unbought eggs fall off and disappear.
2. **Buy** — walk up to an egg and buy it with Cash.
3. **Hatch** — the egg lands on a free pad in your base and hatches with a cinematic sequence: the rarer the dino, the longer and wilder the wobble.
4. **Earn** — every second, each dino on your pads adds its Income to your Cash.
5. **Steal** — walk into another player's base, grab their dino, and carry it home (slow, speed 10). Die or leave while carrying and the dino returns to its pad.
6. **Lock** — step on your base's lock button: a wall closes your doorway for 60 seconds, with glowing laser beams across it. Then a 60 second cooldown.
7. **Sell** — sell your own dino back for 50% of its price and free the pad.

## The ladder

| Tier | Dino | Price | Income/sec | Chance |
|---|---|---|---|---|
| Common | Compy | $50 | $1 | 52% |
| Rare | Velociraptor | $250 | $6 | 28% |
| Epic | Triceratops | $1,200 | $30 | 12% |
| Legendary | Spinosaurus | $6,000 | $160 | 5% |
| Mythic | Golden T-Rex | $30,000 | $850 | 2% |
| **Dragon** | Fire / Ice / Void Dragon | $200,000–$500,000 | $5,500–$15,000 | 1% |

Every dino has neon glow accents in its rarity color — glow is a design pillar, not decoration. Dragons hover above their pads.

Full design: [`steal-game-kit/GAME_DESIGN.md`](steal-game-kit/GAME_DESIGN.md).

## What's in this repo

| Folder | What it is |
|---|---|
| `steal-game-kit/` | The game itself: belt spawner, buy/hatch/steal/sell systems, base manager + lock, pet factory + animations, DataStore saving. |
| `starter-kit/` | The reusable base: player Cash/Wins saving (`PlayerData`) and a gamepass shop. Works with any game type. |

## Install in Roblox Studio

Follow [`steal-game-kit/STUDIO_STEPS.md`](steal-game-kit/STUDIO_STEPS.md) — copy each script into the service it names (ServerScriptService, ReplicatedStorage, StarterPlayerScripts), then enable **Game Settings → Security → Enable Studio Access to API Services** so saving works. No gamepass or asset IDs are invented: put your real gamepass IDs in `starter-kit/ReplicatedStorage/Gamepasses.lua` after creating them on Roblox.

## Status

v1, in active development. The Phase 2 critical fixes (save-guard against failed loads, real `StarterPlayerScripts` class, once-ever starter cash, lost-pet return) are implemented and **statically verified** (parse-check + structural validation). They have **not yet been Play-tested in Roblox Studio** — runtime testing is still open.

## License

MIT — see [LICENSE](LICENSE).
