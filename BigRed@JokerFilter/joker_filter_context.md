# Joker Filter project context

## Goal
A Balatro mod that supplements Cartomancer by adding compact filter pills directly into Cartomancer’s Joker controls row so very large Joker piles can be triaged quickly during modded runs.

## Integration model
- Depends on `cartomancer`
- Overrides `Cartomancer.add_visibility_controls()`
- Adds pills into the same row as Cartomancer’s `Hide`, `Zoom`, and slider
- Filters Jokers by suppressing draw in `Card:draw()` and interaction in `Card:click()`

## Current filters
- **All**: show all Jokers and reset rarity to the rarest available
- **Slot**: not Negative and not Extra
- **Neg**: Negative Jokers
- **Extra**: explicit extra-slot/card-limit Jokers, excluding Negative
- **Temp**: rental, perishable/expiring, self-destruct, and tightly-scoped duration/decay text
- **Retrig**: description contains retrigger wording
- **Destroy**: description contains active `destroys` or `convert all`, but not self-destruction wording
- **OnSell**: sell-trigger style effects via property or text
- **Rarity**: cycling pill from rarest to common
- **Eternal**: Eternal sticker only

## Current color behavior
- active pill = red
- inactive pills = blue
- rarity starts blue until activated
- eternal starts blue until activated

## Current config behavior
There are two config paths:
- `config.lua`
- in-game Steamodded **Config** tab

`config.lua` supports:

```lua
default_primary_filter = "all"
button_scale = 0.3
default_rarity_cycle_index = 1

enabled_buttons = {
  all = true,
  slot = true,
  negative = true,
  extra = true,
  temp = true,
  retrigger = true,
  destroy = true,
  onsell = true,
  rarity = true,
  eternal = true,
}
```

## Current rarity behavior
- rarity cycle order:
  1. `cry_exotic`
  2. Legendary (`4`)
  3. `cry_epic`
  4. Rare (`3`)
  5. Uncommon (`2`)
  6. Common (`1`)
- rarity defaults to the rarest rarity currently present if `default_rarity_cycle_index = 1`
- clicking **All** resets rarity to the configured default / rarest-available behavior
- rarity only becomes active after clicking the rarity pill

## Current text heuristics

### Temp self-destruction patterns
Examples:
- `self destruct`
- `self destructs`
- `destroy itself`
- `destroys itself`
- `this card is destroyed`
- `this joker is destroyed`
- `this card gets destroyed`
- `this joker gets destroyed`
- `then destroy this card`
- `then destroy this joker`
- `destroyed after`
- `is destroyed after`

### Temp duration patterns
Keep these tight:
- `disappears after`
- `for the next`
- `reduces/reduce by ... every round`
- `decreases/decrease by ... every round`

Avoid broad matches like raw `every round` or `every blind` because they caused false positives.

### Retrigger patterns
- `retrigger`
- `retriggers`
- `retriggered`

### Destroy patterns
- `destroys`
- `convert all`

Important:
- Destroy must **not** catch passive phrases like `when a card is destroyed`
- self-destruction phrases belong in **Temp**, not Destroy

### OnSell patterns
Use both property checks and text patterns:
- property checks on `on_sell` style fields
- text like:
  - `sell this card`
  - `sell this joker`
  - `when sold`
  - `if sold`
  - `upon sell`
  - `on sell`
  - `a joker is sold`
  - `joker is sold`
  - `jokers are sold`
  - `card is sold`
  - `cards are sold`

## Known implementation details
- `Extra` comes from explicit card-limit bonus:
  - `card.ability.card_limit`
  - `card.config.center.config.card_limit`
- `Extra` explicitly excludes Negative Jokers
- descriptions are scanned from:
  - `card.config.center.loc_txt.text`
  - `G.localization.descriptions.Joker[key].text`
- Config tab uses Steamodded `config_tab` with toggle / option-cycle style controls
- Version numbers should be kept in sync by incrementing the last numeric segment across:
  - `main.lua`
  - changelog
  - JSON metadata

## File-generation preferences
When generating future updates:
- generate the **full Lua file**
- preserve the user’s top description/comment block
- keep the header clean with the version number
- update **Details** and **Notes** as needed
- avoid extra cluttered `--` indentation in those sections

## Recent decisions worth remembering
- Absolute support was dropped
- sticker cycle was replaced with a plain Eternal pill
- config toggles were added for individual pills
- config was also surfaced in the in-game Mods menu via `config_tab`
- Destruct was renamed to Destroy
- README / changelog / context were refreshed to reflect in-game config
- Extra needed explicit Negative exclusion
- Slot label should show slot count plus free/over capacity information
- user wants version bumping kept synchronized automatically

## Next steps
### 1) Build an agent-driven workflow for this project
Goal: reduce copy/paste churn and make future pair-coding sessions cleaner.

Recommended direction:
- create a small project-specific CLI helper/agent that can:
  - bump version numbers in Lua / changelog / JSON together
  - regenerate full `main.lua`
  - regenerate README / changelog / context
  - package release files
  - validate JSON syntax before handoff
- keep this as a repeatable command-driven workflow instead of ad hoc chat/manual steps

### 2) JetBrains integration
High-priority future improvement:
- integrate the workflow with **JetBrains** as the main IDE pipeline
- preferred outcome:
  - one command or run configuration from JetBrains to:
    - update version
    - run validation
    - package files
    - optionally export a release bundle
- likely approaches:
  - JetBrains external tools
  - run configurations
  - file watchers
  - terminal/CLI task integration
  - possibly an AI/agent plugin workflow inside JetBrains

### 3) Agent / plugin exploration
Investigate whether to:
- build a lightweight custom agent for the CLI
- or leverage an existing plugin/agent framework already available in JetBrains

Potential capabilities:
- project-aware edits
- code review pass before packaging
- consistency checks across files
- changelog/version sync
- release checklist automation

### 4) Code review and testing framework
Set up a more professional pipeline around the mod:
- add a repeatable code review checklist
- add automated sanity checks for:
  - JSON validity
  - version consistency
  - required files present
  - config keys present
- add lightweight test fixtures or scripted smoke tests where possible
- consider a “pre-release validation” command

### 5) Packaging / release workflow
Future automation target:
- generate installable mod files
- generate Mod Manager submission files
- generate changelog / README updates
- optionally zip output for release in one command

## Likely future work
- confirm Extra behavior in live runs since Negative seems to share slot-related internals
- possibly split pills into grouped rows if toolbar gets too crowded
- maybe add other sticker filters later if they prove useful
- maybe make some heuristics mod-pack specific if false positives appear
- move the project toward a cleaner JetBrains-centered professional workflow
