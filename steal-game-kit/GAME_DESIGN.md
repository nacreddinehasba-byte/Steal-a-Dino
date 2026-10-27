# Steal-a-Dino — Game Design (v1)

## The idea in one line
Eggs travel on a belt. You buy an egg, it hatches into a **dinosaur** on your base,
the dino makes you money every second — and other players can **steal** your dinos
and carry them home. Above all dinosaurs sit the **dragons**: the supreme breed.

## The core loop
1. **Eggs on the belt** — eggs appear at one end of a long belt and travel to the
   other end. If nobody buys an egg, it falls off and disappears.
2. **Buy** — walk up to an egg and press the prompt. It costs Cash
   (the Cash from the starter kit's `PlayerData` — this kit adds nothing else).
3. **Hatch** — the egg is placed on a free pad in your base and hatches with a
   **cinematic sequence** (V2): on your screen the egg floats before the camera
   and wobbles — longer and wilder the rarer it is — then the dino is revealed
   on its pad with a sparkle burst, a flash and a spin.
4. **Earn** — every second, each dino on your pads adds its Income to your Cash.
5. **Steal** — walk into another player's base, press the prompt on their dino,
   and it jumps on your head. You walk **slow** (speed 10) while carrying.
   Reach your own base and the dino is yours, on your pad.
   If you die or leave while carrying, the dino **returns to its original pad**.
6. **Lock** — step on your base's lock button: a wall closes your doorway for
   **60 seconds** (nobody can steal), with glowing **laser beams** across the
   doorway while it lasts. Then a **60 second** cooldown.
7. **Sell** — press the prompt on your own dino to sell it back for **50%** of
   its price and free the pad.

## Bases
- 6 bases around the belt, one per player (v1 = up to 6 players).
- Each base: a floor, **6 pads**, a lock button, a doorway with a LockWall.
- You spawn at your base. When you leave, your dinos are **saved** (see
  *Saving your collection*) and the base is freed for the next player —
  your collection is back on your pads when you return.

## The ladder — rarity table

| Tier | Dino | Price | Income/sec | Spawn chance | Look |
|---|---|---|---|---|---|
| Common | Compy (tiny) | $50 | $1 | 52% | grey-green, big cute eyes |
| Rare | Velociraptor | $250 | $6 | 28% | blue, cyan glow stripes, sickle claws |
| Epic | Triceratops | $1,200 | $30 | 12% | purple, frill with neon edge, 3 horns, light |
| Legendary | Spinosaurus | $6,000 | $160 | 5% | orange-red, big sail with neon edge, light |
| Mythic | **Golden T-Rex** | $30,000 | $850 | 2% | full gold metal, gold neon, strong gold light |
| **DRAGON** | (see below) | — | — | **1%** | **the supreme breed — wings, hovers** |

### The DRAGON tier (above Mythic — أعلى سلالة)
Dragons are not dinosaurs. They outclass everything: they have **wings**, a long
neck, horns — and they **hover** above their pad, gently bobbing up and down.

| Dragon | Price | Income/sec | Chance inside Dragon tier |
|---|---|---|---|
| Fire Dragon (red-orange glow) | $200,000 | $5,500 | 45% |
| Ice Dragon (cyan-white glow) | $200,000 | $5,500 | 45% |
| **Void Dragon** (purple-black, purple glow) | $500,000 | $15,000 | 10% — the rarest thing in the game |

A Dragon egg is only ~1% of all eggs, and a Void egg is ~0.1% — about 1 in 1,000 eggs.

## Visual identity — the glow system (توهج)
Visual wow is a design pillar, not decoration:
- **Every dino has Neon glow accents** in its rarity color: glowing eyes, a neon
  stripe along the back, plus tier extras — Triceratops frill edge, Spinosaurus
  sail edge, T-Rex teeth/eyes, dragon wing membranes and horns.
- **PointLights on Epic and above.** The Golden T-Rex carries a strong gold light:
  it visibly shines across the map. Dragons glow in their element color
  (fire orange, ice cyan, void purple).
- **Eggs pulse.** On the belt, every egg's glow light breathes (brighter–dimmer)
  and the egg gently swells, so a rare egg can be spotted from far away.
  Dragon eggs are unmistakable: **dark shell with glowing cracks** in the
  dragon's color, pulsing harder than any normal egg.
- **Rarity colors are distinct and bright:** Common grey-green, Rare blue,
  Epic purple, Legendary orange-red, Mythic gold, Dragon = element color.
- The map needs one **BloomEffect** in Lighting (see STUDIO_STEPS) — without it,
  Neon parts look flat instead of glowing.

## Saving your collection
Collecting is the heart of the genre, so owned dinos/dragons **persist
between sessions**, like Cash:
- `PetSaveService` keeps its own DataStore (`StealDinoPets_v1`), separate
  from PlayerData's Cash save. It stores the ordered list of owned pets as
  records (`{ Species, Mutation }`) — pets are rebuilt by PetFactory on
  return. V1 saves (bare species strings) load as mutation-less records
  and are rewritten in the new format on the next save.
- **Save triggers:** every collection change (buy/hatch, a steal delivered,
  a sell), an autosave every ~3 minutes for changed collections, when a
  player leaves, and at server shutdown. A per-player *shadow list* mirrors
  the collection, so a save never reads the half-destroyed state of a
  player who is leaving.
- **Overflow rule:** a base has 6 pads. If a returning player owns more
  pets than pads, the **most valuable (highest income)** are placed; the
  rest wait in *storage* and are placed automatically the moment a pad
  frees (e.g. right after you sell a pet). Nothing is ever lost to overflow.
- **Load-failure safety rule:** if a player's save file fails to load,
  that file is **never overwritten** this session — the player plays with
  an empty base rather than risking their real collection.

## V2 — the polish pass (2026-10-23)
Built from a study of how the top steal/simulator games are made
(see `hidden_files/youtube-learning-digest.md`):

- **Articulated models.** Every dino/dragon is rebuilt with a belly, neck,
  jointed head, jointed jaw, feet (toe claws on the fighters), a two-segment
  tail, and cuter proportions — a head almost as tall as the body and big
  glowing eyes with a white sparkle. Signature features per species:
  Triceratops frill + 3 horns + beak, Spinosaurus sail + head crest + tail
  fin, Velociraptor snout + sickle claws + clawed arms, Compy crest tuft,
  T-Rex brow ridges + chomping jaw, dragons: jointed wings with neon
  membranes, horns, back/tail spikes and a spade tail tip.
- **Code animation (`PetAnim`).** No rigs or animation assets: placed pets
  bob and sway, heads turn, jaws chomp, tails wag with a phase lag, dragon
  wings flap — all CFrame math on the welds PetFactory marks as joints.
  Belt eggs bob and rock as they ride.
- **Cinematic hatch.** Buying plays the genre's signature moment: the egg
  wobbles in front of the buyer's camera (~2.2s for a Common, up to ~5.4s
  for a Rainbow Dragon, rising wobble speed), cracks in a flash, and a
  rarity banner names the catch — while the server reveals the pet on its
  pad with a particle burst, a light flash and a full spin. The server
  hatch stays authoritative; the client show is presentation only.
- **Mutations.** Every hatch rolls **Golden (8%, ×3 income)** — the pet
  turns metal-gold and sparkles — and **Rainbow (1.5%, ×6 income)** — its
  whole palette cycles through the rainbow, forever. Mutations are saved
  with the pet (V1 saves migrate automatically) and multiply its sell
  price too. **Legendary+ hatches and every Rainbow are announced to the
  whole server** in chat.
- **Lock lasers + 60s lock.** Locking now shows three neon beams across
  the doorway (the invisible wall still does the blocking), and the lock
  lasts the genre-standard 60 seconds.
- **Labels.** Every billboard is now three lines — name, rarity, and money
  in compact format (`$1.2K`, `$850/s`, `$1.5M`) — on belt eggs and placed
  pets alike; prompts and sale messages use the same formatting.

Still placeholder: hatch **sounds** (the three SoundIds in `HatchClient`
are `rbxassetid://0` with a TODO — the sequence is fully visual until the
sound pass picks real Creator Store audio).

**V2 audio (completed pass):** all hatch sounds are now real verified Creator Store audio wired into `HatchClient` (wobble/crack/reveal/buy/roar), and `MusicClient` loops world background music ("Happy Adventure") + jungle ambience from the moment a player joins — zero placeholder SoundIds remain anywhere in the game.

## Economy notes
- **Starter cash:** new players start with $0 in the save file, so BaseManager
  grants **$100 once per server session** if a player's Cash is below the
  cheapest egg ($50). With pet saving this still behaves as a floor, not a
  bonus: it only fires while Cash is below the cheapest egg, and restored
  pets resume paying income immediately. *TODO for v2: save a "starter
  claimed" flag in PlayerData so the grant survives across servers.*
- **Sell-back is 50%** — stealing is always more profitable than selling.
- **Gamepass hooks (already wired):** the starter kit's `DoubleCash` attribute
  doubles all pad income automatically. BaseLock has a clean TODO hook for a
  future **"LongLock"** gamepass (double lock duration) — add the pass in
  `Gamepasses.lua` and the attribute in `GamepassShop` does the rest.

## v1 scope
**In:** belt + spawning (weighted rarities), code-built eggs and dinos (no models
needed), buying/hatching, 6 bases × 6 pads, per-second income, stealing with
carry/slow/return, base lock with cooldown, selling, owner notifications,
full glow system, dragon tier with hover, saving owned dinos/dragons
between sessions (PetSaveService — the collection persists like Cash).
**Out (later versions):** more species per tier, trading, rebirth/prestige,
events and admin eggs, custom map art, real sound ids (hatch sounds are
placeholders in V2), gamepass IDs (shop itself comes from the starter kit).

## Files in this kit
| File | Goes in Studio | Role |
|---|---|---|
| `ReplicatedStorage/Config.lua` | ReplicatedStorage (ModuleScript) | All numbers: rarities, species, prices, chances |
| `ReplicatedStorage/PetFactory.lua` | ReplicatedStorage (ModuleScript) | Builds eggs + articulated dinos out of parts, with glow + mutations |
| `ReplicatedStorage/PetAnim.lua` | ReplicatedStorage (ModuleScript) | Code animation: idle bob/sway, joint wiggles, Rainbow color cycle |
| `ServerScriptService/BaseService.lua` | ServerScriptService (ModuleScript) | Shared brain: bases, pads, locks, notifications |
| `ServerScriptService/BaseManager.server.lua` | ServerScriptService (Script) | Base assignment, spawning at base, income tick, dragon hover |
| `ServerScriptService/PetSaveService.server.lua` | ServerScriptService (Script) | Saves owned dinos/dragons between sessions; restores them on join |
| `ServerScriptService/BeltSpawner.server.lua` | ServerScriptService (Script) | Eggs on the belt: spawn, move, pulse, despawn |
| `ServerScriptService/BuySystem.server.lua` | ServerScriptService (Script) | Buy prompt on eggs → hatch on a pad |
| `ServerScriptService/StealSystem.server.lua` | ServerScriptService (Script) | Steal prompt, carrying, delivery, return |
| `ServerScriptService/SellSystem.server.lua` | ServerScriptService (Script) | Sell prompt on your own dinos |
| `ServerScriptService/BaseLock.server.lua` | ServerScriptService (Script) | Lock button, wall, cooldown |
| `StarterPlayerScripts/NotifyClient.client.lua` | StarterPlayerScripts (LocalScript) | Shows the notification messages on screen |
| `StarterPlayerScripts/HatchClient.client.lua` | StarterPlayerScripts (LocalScript) | The cinematic hatch show on the buyer's screen |

Plus the starter kit (`PlayerData`, `GamepassShop`, `Gamepasses`) — install it
first; this kit uses its Cash and its gamepass attributes.
