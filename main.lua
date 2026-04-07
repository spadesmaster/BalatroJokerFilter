--[[
Joker Filter v0.5.6
BigRed

Joker Filter extends Cartomancer's Joker controls with compact filter pills
for triaging large Joker collections in Balatro.

CHANGE HISTORY
v0.5.6
- Renamed the old Eternal filter/button to Perm.
- Perm now matches either Eternal or Absolute.
- Added Vampire-style "removes card enhancement" wording to Destroy checks.
- Preserved the compact 3x3 config layout and Slot capacity display.

DETAILS
This version depends on Cartomancer and appends filter pills into
Cartomancer's joker control row.

PILLS
All = every joker; also clears any active pill filter and resets the
  rarity pill to the configured default / rarest currently available rarity
Slot = jokers that take a normal slot (not Negative, not Extra) and shows
  the current Slot count plus free or over capacity
Neg = jokers with Negative
Extra = jokers with an explicit extra-slot / card-limit bonus, excluding
  Negative jokers
Temp = jokers that are Rental, Expiring/Perishable, self-destruct, or
  temporary-duration style cards such as "for the next X hands",
  "disappears after", or "reduces/decreases by X every round"
Retrig = jokers whose description includes retrigger wording
Destroy = jokers whose description uses active destructive wording such as
  "destroys", "convert all", or "removes card enhancement", but not
  passive wording like "is destroyed"
OnSell = jokers with sell-trigger style effects
Rarity = a single cycling pill that steps through rarity buckets
  from rarest to most common; starts on the configured default and
  stays blue until activated
Perm = jokers with a permanent sticker state, matching Eternal or Absolute

NOTES
Slot is the practical replace/sell candidate bucket.
Extra intentionally excludes Negative jokers because in practice
Negative appears to share the same slot-related flag.
Temp also catches self-destruction phrases such as "this card is destroyed".
Destroy intentionally excludes self-destruction phrases, which belong in Temp.
OnSell uses both property checks and description heuristics.
Perm treats Eternal and Absolute as one combined permanent-status bucket.
Special pills with a zero count are hidden automatically, while All, Slot,
and Rarity remain visible.
The in-game Config tab is compacted and groups Show-button toggles
into three rows of three.
Visual feedback is the active pill state plus the count on each pill.
Popup feedback and joker-count banners are intentionally removed.
Individual pills can be disabled from config.lua or the in-game Mods menu.
]]

local MOD = SMODS.current_mod

----------------------------------------------------------------
-- Config helpers
----------------------------------------------------------------

-- Returns a top-level config value or a default when the key is missing.
local function cfg1(t, key, default_value)
    if t and t[key] ~= nil then
        return t[key]
    end
    return default_value
end

-- Returns a nested config value or a default when the parent/key pair is missing.
local function cfg2(t, key1, key2, default_value)
    if t and t[key1] and t[key1][key2] ~= nil then
        return t[key1][key2]
    end
    return default_value
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------

local mod_config = MOD.config or {}

local legacy_default_primary_filter = cfg1(mod_config, "default_primary_filter", "all")

local CONFIG = {
    default_primary_filter = legacy_default_primary_filter == "eternal" and "perm" or legacy_default_primary_filter,
    button_scale = cfg1(mod_config, "button_scale", 0.3),
    default_rarity_cycle_index = cfg1(mod_config, "default_rarity_cycle_index", 1),
    enabled_buttons = {        slot = cfg2(mod_config, "enabled_buttons", "slot", true),
        negative = cfg2(mod_config, "enabled_buttons", "negative", true),
        extra = cfg2(mod_config, "enabled_buttons", "extra", true),
        temp = cfg2(mod_config, "enabled_buttons", "temp", true),
        retrigger = cfg2(mod_config, "enabled_buttons", "retrigger", true),
        destroy = cfg2(mod_config, "enabled_buttons", "destroy", true),
        onsell = cfg2(mod_config, "enabled_buttons", "onsell", true),
        rarity = cfg2(mod_config, "enabled_buttons", "rarity", true),
        perm = cfg2(mod_config, "enabled_buttons", "perm", cfg2(mod_config, "enabled_buttons", "eternal", true)),
    },
}

----------------------------------------------------------------
-- State
----------------------------------------------------------------

local FILTER_LABELS = {
    all = "All",
    slot = "Slot",
    negative = "Neg",
    extra = "Extra",
    temp = "Temp",
    retrigger = "Retrig",
    destroy = "Destroy",
    onsell = "OnSell",
    rarity = "Rarity",
    perm = "Perm",
}

local FILTER_OPTIONS = {
    "all",
    "slot",
    "negative",
    "extra",
    "temp",
    "retrigger",
    "destroy",
    "onsell",
    "perm",
}

local FILTER_OPTION_LABELS = {
    "All",
    "Slot",
    "Neg",
    "Extra",
    "Temp",
    "Retrig",
    "Destroy",
    "OnSell",
    "Perm",
}

-- Vanilla joker rarities:
-- 1 = Common, 2 = Uncommon, 3 = Rare, 4 = Legendary
-- Modded rarities may use string keys.
local RARITY_CYCLE = {
    { key = "cry_exotic", label = "Exotic" },
    { key = 4,            label = "Legend" },
    { key = "cry_epic",   label = "Epic" },
    { key = 3,            label = "Rare" },
    { key = 2,            label = "Uncommon" },
    { key = 1,            label = "Common" },
}

local RARITY_DEFAULT_OPTIONS = {"Rarest available", "Exotic", "Legend", "Epic", "Rare", "Uncommon", "Common"}

local JF = {
    primary_filter = CONFIG.default_primary_filter,
    rarity_cycle_index = CONFIG.default_rarity_cycle_index,
    cartomancer_patched = false,
}

G.JF = JF

----------------------------------------------------------------
-- Utility
----------------------------------------------------------------

-- Persists the current mod config back through Steamodded.
local function save_config()
    if MOD then
        MOD.config = CONFIG
        if MOD.save_mod_config then
            MOD:save_mod_config()
        elseif SMODS and SMODS.save_mod_config then
            SMODS.save_mod_config(MOD)
        end
    end
end

-- Rebuilds the Cartomancer toolbar so button labels/visibility stay in sync.
local function refresh_toolbar()
    if G and G.jokers and G.jokers.children and G.jokers.children.cartomancer_controls then
        G.jokers.children.cartomancer_controls:remove()
        G.jokers.children.cartomancer_controls = nil
    end

    if Cartomancer and Cartomancer.align_G_jokers then
        Cartomancer.align_G_jokers()
    elseif G and G.jokers then
        G.jokers:align_cards()
        G.jokers:hard_set_cards()
    end
end

----------------------------------------------------------------
-- Filter state helpers
----------------------------------------------------------------

-- Returns true when a filter name maps to a known pill.
local function is_valid_primary_filter(filter_name)
    return FILTER_LABELS[filter_name] ~= nil
end

-- Returns whether a pill is enabled in config.
local function is_filter_button_enabled(filter_name)
    return CONFIG.enabled_buttons[filter_name] == true
end

-- Clamps the rarity-cycle index to a valid option range.
local function clamp_rarity_cycle_index(index)
    if type(index) ~= "number" then
        return 1
    end

    if index < 1 then
        return 1
    end

    if index > #RARITY_CYCLE then
        return #RARITY_CYCLE
    end

    return math.floor(index)
end

-- Returns the active filter, preferring saved game state over defaults.
local function get_primary_filter()
    local current = JF.primary_filter

    if G and G.GAME and type(G.GAME.jf_primary_filter) == "string" then
        current = G.GAME.jf_primary_filter
    end

    if not is_valid_primary_filter(current) then
        current = CONFIG.default_primary_filter
    end

    if not is_valid_primary_filter(current) then
        current = "all"
    end

    return current
end

-- Returns the active rarity-cycle index from game state or config.
local function get_rarity_cycle_index()
    local current = JF.rarity_cycle_index

    if G and G.GAME and type(G.GAME.jf_rarity_cycle_index) == "number" then
        current = G.GAME.jf_rarity_cycle_index
    end

    return clamp_rarity_cycle_index(current)
end

-- Returns the current rarity descriptor for the rarity pill.
local function get_current_rarity_entry()
    return RARITY_CYCLE[get_rarity_cycle_index()]
end

-- Activates a filter, stores it in game state, and refreshes the toolbar.
local function set_primary_filter(filter_name)
    if not is_valid_primary_filter(filter_name) then
        return
    end

    JF.primary_filter = filter_name

    if G and G.GAME then
        G.GAME.jf_primary_filter = filter_name
    end

    refresh_toolbar()
end

-- Stores the current rarity-cycle index in runtime and save state.
local function set_rarity_cycle_index(index)
    local clamped = clamp_rarity_cycle_index(index)
    JF.rarity_cycle_index = clamped

    if G and G.GAME then
        G.GAME.jf_rarity_cycle_index = clamped
    end
end

-- Advances the rarity pill to the next rarity bucket.
local function advance_rarity_cycle()
    local next_index = get_rarity_cycle_index() + 1
    if next_index > #RARITY_CYCLE then
        next_index = 1
    end
    set_rarity_cycle_index(next_index)
end

----------------------------------------------------------------
-- Joker property helpers
----------------------------------------------------------------

-- Returns true when a card belongs to the Joker set.
local function is_joker(card)
    return card
        and card.ability
        and card.ability.set == "Joker"
end

-- Returns true when a card is currently in the live Joker area.
local function is_joker_in_row(card)
    if not (G and G.jokers and G.jokers.cards and card) then
        return false
    end

    for i = 1, #G.jokers.cards do
        if G.jokers.cards[i] == card then
            return true
        end
    end

    return false
end

-- Returns true when a card is a Joker currently managed by this toolbar.
local function is_filter_target(card)
    return is_joker(card) and is_joker_in_row(card)
end

-- Detects whether a Joker has the Negative edition.
local function has_negative_shader(card)
    return card
        and card.edition
        and card.edition.negative == true
end

-- Reads the explicit extra-slot bonus from runtime or center config.
local function get_explicit_extra_slot_bonus(card)
    local ability_bonus =
        tonumber(card and card.ability and card.ability.card_limit) or 0

    local center_bonus =
        tonumber(
            card
            and card.config
            and card.config.center
            and card.config.center.config
            and card.config.center.config.card_limit
        ) or 0

    return math.max(ability_bonus, center_bonus)
end

-- Detects Extra-slot Jokers while excluding Negative Jokers.
local function has_extra_slot(card)
    return get_explicit_extra_slot_bonus(card) > 0
        and not has_negative_shader(card)
end

-- Detects whether a Joker has the Eternal sticker.
local function has_eternal(card)
    return card
        and card.ability
        and card.ability.eternal == true
end

-- Detects whether a Joker has the Absolute sticker/state.
local function has_absolute(card)
    return card and (
        (card.ability and (card.ability.cry_absolute == true or card.ability.absolute == true))
        or (card.config and card.config.center and (
            card.config.center.cry_absolute == true
            or card.config.center.absolute == true
            or (card.config.center.config and (
                card.config.center.config.cry_absolute == true
                or card.config.center.config.absolute == true
            ))
        ))
    )
end

-- Detects whether a Joker belongs in the combined permanent-status bucket.
local function has_perm(card)
    return has_eternal(card) or has_absolute(card)
end

-- Returns a Joker's rarity key from its center config.
local function get_joker_rarity(card)
    return card and card.config and card.config.center and card.config.center.rarity
end

-- Returns true when a Joker matches the currently selected rarity pill.
local function matches_current_rarity(card)
    local rarity = get_joker_rarity(card)
    local entry = get_current_rarity_entry()
    return entry and rarity == entry.key
end

-- Detects perishable/expiring Jokers from their ability flags.
local function is_expiring(card)
    return card
        and card.ability
        and card.ability.perishable == true
end

-- Detects rental Jokers from their ability flags.
local function is_rental(card)
    return card
        and card.ability
        and card.ability.rental == true
end

----------------------------------------------------------------
-- Description scanning helpers
----------------------------------------------------------------

--[[
These helpers use normalized description text instead of hardcoded Joker names
whenever possible. That keeps the filter logic more compatible with modded Jokers,
but it also means wording changes can affect matching behavior.
]]

-- Collects description lines from local text and global localization tables.
local function get_joker_description_lines(card)
    local lines = {}

    local center = card and card.config and card.config.center
    local loc_txt = center and center.loc_txt

    if loc_txt and type(loc_txt.text) == "table" then
        for i = 1, #loc_txt.text do
            local line = loc_txt.text[i]
            if type(line) == "string" then
                lines[#lines + 1] = line
            end
        end
    end

    local key = center and center.key
    local loc_entry = key
        and G and G.localization
        and G.localization.descriptions
        and G.localization.descriptions.Joker
        and G.localization.descriptions.Joker[key]

    if loc_entry and type(loc_entry.text) == "table" then
        for i = 1, #loc_entry.text do
            local line = loc_entry.text[i]
            if type(line) == "string" then
                lines[#lines + 1] = line
            end
        end
    end

    return lines
end

-- Normalizes description text so heuristic string matching is more reliable.
local function normalize_description_text(text)
    text = string.lower(text or "")
    text = string.gsub(text, "{.-}", " ")
    text = string.gsub(text, "[^%w%s%-]", " ")
    text = string.gsub(text, "%-", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return " " .. text .. " "
end

-- Joins and normalizes all description text for a Joker into one searchable blob.
local function get_normalized_description_blob(card)
    local lines = get_joker_description_lines(card)

    if #lines == 0 then
        return ""
    end

    return normalize_description_text(table.concat(lines, " "))
end

local TEMP_DESTRUCTION_PATTERNS = {
    " self destruct ",
    " self destructs ",
    " destroy itself ",
    " destroys itself ",
    " this card is destroyed ",
    " this joker is destroyed ",
    " this card gets destroyed ",
    " this joker gets destroyed ",
    " then destroy this card ",
    " then destroy this joker ",
    " destroyed after ",
    " is destroyed after ",
}

local TEMP_DURATION_PATTERNS = {
    " disappears after ",
    " for the next ",
}

local ONSELL_PATTERNS = {
    " sell this card ",
    " sell this joker ",
    " when sold ",
    " if sold ",
    " upon sell ",
    " on sell ",
    " a joker is sold ",
    " joker is sold ",
    " jokers are sold ",
    " card is sold ",
    " cards are sold ",
}

local RETRIGGER_PATTERNS = {
    " retrigger ",
    " retriggers ",
    " retriggered ",
}

local DESTROY_PATTERNS = {
    " destroys ",
    " convert all ",
    " removes card enhancement ",
    " removes card enhancements ",
}

-- Returns true when any normalized pattern appears in the Joker description blob.
local function description_matches_any_pattern(card, patterns)
    local blob = get_normalized_description_blob(card)

    if blob == "" then
        return false
    end

    for i = 1, #patterns do
        if string.find(blob, patterns[i], 1, true) then
            return true
        end
    end

    return false
end

-- Detects self-destruction wording that should map into the Temp bucket.
local function description_suggests_self_destruct(card)
    return description_matches_any_pattern(card, TEMP_DESTRUCTION_PATTERNS)
end

-- Detects temporary-duration wording such as 'for the next' or per-round decay.
local function description_suggests_temp_duration(card)
    local blob = get_normalized_description_blob(card)

    if blob == "" then
        return false
    end

    for i = 1, #TEMP_DURATION_PATTERNS do
        if string.find(blob, TEMP_DURATION_PATTERNS[i], 1, true) then
            return true
        end
    end

    local has_reduce_phrase =
        string.find(blob, " reduces by ", 1, true)
        or string.find(blob, " reduce by ", 1, true)
        or string.find(blob, " decreases by ", 1, true)
        or string.find(blob, " decrease by ", 1, true)

    local has_every_round =
        string.find(blob, " every round ", 1, true) ~= nil

    return has_reduce_phrase and has_every_round
end

-- Detects sell-trigger wording in Joker descriptions.
local function description_suggests_on_sell(card)
    return description_matches_any_pattern(card, ONSELL_PATTERNS)
end

-- Detects retrigger wording in Joker descriptions.
local function description_suggests_retrigger(card)
    return description_matches_any_pattern(card, RETRIGGER_PATTERNS)
end

-- Detects active destructive wording while excluding self-destruction phrases.
local function description_suggests_destroy(card)
    if description_suggests_self_destruct(card) then
        return false
    end

    return description_matches_any_pattern(card, DESTROY_PATTERNS)
end

-- Returns true when a Joker belongs in the Temp bucket.
local function is_temporary(card)
    return is_rental(card)
        or is_expiring(card)
        or description_suggests_self_destruct(card)
        or description_suggests_temp_duration(card)
end

-- Detects explicit on-sell behavior from runtime/config fields.
local function has_generic_on_sell(card)
    return card
        and (
            card.on_sell ~= nil
            or (card.ability and card.ability.on_sell ~= nil)
            or (card.config and card.config.center and card.config.center.on_sell ~= nil)
        )
end

-- Returns true when a Joker belongs in the OnSell bucket.
local function is_on_sell(card)
    return has_generic_on_sell(card) or description_suggests_on_sell(card)
end

-- Returns true when a Joker belongs in the Retrig bucket.
local function is_retrigger(card)
    return description_suggests_retrigger(card)
end

-- Returns true when a Joker belongs in the Destroy bucket.
local function is_destroy(card)
    return description_suggests_destroy(card)
end

----------------------------------------------------------------
-- Matching logic
----------------------------------------------------------------

-- Checks whether a Joker matches a given primary filter pill.
local function matches_primary_filter(filter_name, card)
    local neg = has_negative_shader(card)
    local extra = has_extra_slot(card)

    if filter_name == "all" then
        return true
    elseif filter_name == "slot" then
        return (not neg) and (not extra)
    elseif filter_name == "negative" then
        return neg
    elseif filter_name == "extra" then
        return extra
    elseif filter_name == "temp" then
        return is_temporary(card)
    elseif filter_name == "retrigger" then
        return is_retrigger(card)
    elseif filter_name == "destroy" then
        return is_destroy(card)
    elseif filter_name == "onsell" then
        return is_on_sell(card)
    elseif filter_name == "rarity" then
        return matches_current_rarity(card)
    elseif filter_name == "perm" then
        return has_perm(card)
    end

    return true
end

-- Checks whether a Joker matches the currently active filter pill.
local function matches_active_primary_filter(card)
    return matches_primary_filter(get_primary_filter(), card)
end

-- Returns true when a Joker should be hidden by the active filter.
local function should_hide(card)
    if not is_filter_target(card) then
        return false
    end

    return not matches_active_primary_filter(card)
end

----------------------------------------------------------------
-- Count helpers
----------------------------------------------------------------

-- Counts how many live Jokers match a given filter pill.
local function count_primary_matches(filter_name)
    local count = 0

    if not (G and G.jokers and G.jokers.cards) then
        return 0
    end

    for i = 1, #G.jokers.cards do
        local card = G.jokers.cards[i]

        if is_filter_target(card) and matches_primary_filter(filter_name, card) then
            count = count + 1
        end
    end

    return count
end

-- Counts how many live Jokers match a specific rarity key.
local function count_rarity_matches(rarity_key)
    local count = 0

    if not (G and G.jokers and G.jokers.cards) then
        return 0
    end

    for i = 1, #G.jokers.cards do
        local card = G.jokers.cards[i]
        if is_filter_target(card) and get_joker_rarity(card) == rarity_key then
            count = count + 1
        end
    end

    return count
end

-- Finds the rarest rarity bucket that currently has at least one Joker.
local function get_rarest_available_rarity_index()
    for i = 1, #RARITY_CYCLE do
        if count_rarity_matches(RARITY_CYCLE[i].key) > 0 then
            return i
        end
    end

    return clamp_rarity_cycle_index(CONFIG.default_rarity_cycle_index)
end

-- Resets the rarity pill to the configured default or the current rarest available rarity.
local function reset_rarity_cycle_to_rarest_available()
    local desired = CONFIG.default_rarity_cycle_index
    if desired == 1 then
        desired = get_rarest_available_rarity_index()
    else
        desired = math.min(desired - 1, #RARITY_CYCLE)
        desired = math.max(desired, 1)
    end
    set_rarity_cycle_index(desired)
end

-- Formats the Slot pill label as current slot-count plus free/over capacity.
local function get_slot_capacity_text()
    local slot_jokers = count_primary_matches("slot")

    local used =
        tonumber(G and G.jokers and G.jokers.config and G.jokers.config.card_count) or 0

    local total =
        tonumber(
            G
            and G.jokers
            and G.jokers.config
            and G.jokers.config.card_limits
            and G.jokers.config.card_limits.total_slots
        ) or used

    local delta = total - used

    if delta >= 0 then
        return tostring(slot_jokers) .. " (" .. tostring(delta) .. " free)"
    else
        return tostring(slot_jokers) .. " (" .. tostring(math.abs(delta)) .. " over)"
    end
end

-- Builds the label text for normal filter pills.
local function primary_filter_button_label(filter_name)
    if filter_name == "slot" then
        return FILTER_LABELS[filter_name] .. " " .. get_slot_capacity_text()
    end

    return FILTER_LABELS[filter_name] .. " " .. tostring(count_primary_matches(filter_name))
end

-- Builds the label text for the cycling rarity pill.
local function rarity_button_label()
    local entry = get_current_rarity_entry()
    local count = entry and count_rarity_matches(entry.key) or 0
    return (entry and entry.label or "Rarity") .. " " .. tostring(count)
end

----------------------------------------------------------------
-- Button helpers
----------------------------------------------------------------

-- Chooses the active/inactive colour for a pill button.
local function jf_button_colour(filter_name)
    if get_primary_filter() == filter_name then
        return G.C.RED
    end

    return G.C.BLUE
end

-- Builds a standard pill button node for the Cartomancer toolbar.
local function make_filter_button(filter_name, callback_name, minw)
    return {
        n = G.UIT.C,
        config = { align = "cm" },
        nodes = {
            UIBox_button({
                id = "jf_filter_" .. filter_name,
                button = callback_name,
                label = { primary_filter_button_label(filter_name) },
                minh = 0.45,
                minw = minw,
                col = false,
                scale = CONFIG.button_scale,
                colour = jf_button_colour(filter_name),
            })
        }
    }
end

-- Builds the special cycling rarity pill button node.
local function make_rarity_button(callback_name, minw)
    return {
        n = G.UIT.C,
        config = { align = "cm" },
        nodes = {
            UIBox_button({
                id = "jf_filter_rarity",
                button = callback_name,
                label = { rarity_button_label() },
                minh = 0.45,
                minw = minw,
                col = false,
                scale = CONFIG.button_scale,
                colour = jf_button_colour("rarity"),
            })
        }
    }
end

----------------------------------------------------------------
-- Config tab
----------------------------------------------------------------

-- Maps the configured default filter to its config-tab option index.
local function get_default_filter_option_index()
    for i = 1, #FILTER_OPTIONS do
        if FILTER_OPTIONS[i] == CONFIG.default_primary_filter then
            return i
        end
    end
    return 1
end

G.FUNCS.jf_config_default_filter = function(e)
    CONFIG.default_primary_filter = FILTER_OPTIONS[e.to_key] or "all"
    save_config()
    refresh_toolbar()
end

G.FUNCS.jf_config_button_scale = function(e)
    local values = {0.25, 0.3, 0.35, 0.4}
    CONFIG.button_scale = values[e.to_key] or 0.3
    save_config()
    refresh_toolbar()
end

G.FUNCS.jf_config_rarity_default = function(e)
    CONFIG.default_rarity_cycle_index = e.to_key or 1
    save_config()
    reset_rarity_cycle_to_rarest_available()
    refresh_toolbar()
end

-- Builds one config-tab toggle node for show/hide button settings.
local function make_toggle_node(label, ref_value)
    return create_toggle({
        label = label,
        ref_table = CONFIG.enabled_buttons,
        ref_value = ref_value,
        callback = function()
            save_config()
            refresh_toolbar()
        end
    })
end

--[[
This config tab mirrors the file-based config so users can change the default
filter, button scale, rarity default, and visible pills without leaving the game.
]]
MOD.config_tab = function()
    local function toggle_cell(label, ref_value)
        return {
            n = G.UIT.C,
            config = {align = "cm", padding = 0.02},
            nodes = { make_toggle_node(label, ref_value) }
        }
    end

    local rows = {
        {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            create_option_cycle({
                label = "Default filter",
                scale = 0.7,
                w = 4.8,
                options = FILTER_OPTION_LABELS,
                opt_callback = "jf_config_default_filter",
                current_option = get_default_filter_option_index(),
            }),
            create_option_cycle({
                label = "Button scale",
                scale = 0.7,
                w = 3.2,
                options = {"0.25", "0.30", "0.35", "0.40"},
                opt_callback = "jf_config_button_scale",
                current_option = (CONFIG.button_scale == 0.25 and 1)
                    or (CONFIG.button_scale == 0.35 and 3)
                    or (CONFIG.button_scale == 0.4 and 4)
                    or 2,
            }),
            create_option_cycle({
                label = "Rarity default",
                scale = 0.7,
                w = 4.8,
                options = RARITY_DEFAULT_OPTIONS,
                opt_callback = "jf_config_rarity_default",
                current_option = CONFIG.default_rarity_cycle_index or 1,
            }),
        }},
        {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            toggle_cell("Show Slot", "slot"),
            toggle_cell("Show Neg", "negative"),
            toggle_cell("Show Extra", "extra"),
        }},
        {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            toggle_cell("Show Temp", "temp"),
            toggle_cell("Show Retrig", "retrigger"),
            toggle_cell("Show Destroy", "destroy"),
        }},
        {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            toggle_cell("Show OnSell", "onsell"),
            toggle_cell("Show Rarity", "rarity"),
            toggle_cell("Show Perm", "perm"),
        }},
    }

    return {
        n = G.UIT.ROOT,
        config = {
            emboss = 0.05,
            minh = 4.8,
            minw = 15,
            r = 0.1,
            align = "cm",
            padding = 0.12,
            colour = G.C.BLACK
        },
        nodes = rows
    }
end


----------------------------------------------------------------
-- Callbacks
----------------------------------------------------------------

-- UI callbacks: each handler updates a pill state, then refreshes the toolbar as needed.
-- Resets filters to All and restores the configured rarity default.
G.FUNCS.jf_filter_all = function(e)
    reset_rarity_cycle_to_rarest_available()
    set_primary_filter("all")
end

-- Activates the Slot filter.
G.FUNCS.jf_filter_slot = function(e)
    set_primary_filter("slot")
end

-- Activates the Neg filter.
G.FUNCS.jf_filter_negative = function(e)
    set_primary_filter("negative")
end

-- Activates the Extra filter.
G.FUNCS.jf_filter_extra = function(e)
    set_primary_filter("extra")
end

-- Activates the Temp filter.
G.FUNCS.jf_filter_temp = function(e)
    set_primary_filter("temp")
end

-- Activates the Retrig filter.
G.FUNCS.jf_filter_retrigger = function(e)
    set_primary_filter("retrigger")
end

-- Activates the Destroy filter.
G.FUNCS.jf_filter_destroy = function(e)
    set_primary_filter("destroy")
end

-- Activates the OnSell filter.
G.FUNCS.jf_filter_onsell = function(e)
    set_primary_filter("onsell")
end

-- Activates the Perm filter.
G.FUNCS.jf_filter_perm = function(e)
    set_primary_filter("perm")
end

-- Activates the Rarity filter and advances it when clicked while already active.
G.FUNCS.jf_cycle_rarity = function(e)
    if get_primary_filter() == "rarity" then
        advance_rarity_cycle()
    end

    set_primary_filter("rarity")
end

-- Returns true when a pill should be rendered, including zero-count hiding rules.
local function should_show_filter_button(filter_name)
    if filter_name == "all" then
        return true
    end

    if not is_filter_button_enabled(filter_name) then
        return false
    end

    if filter_name == "slot" or filter_name == "rarity" then
        return true
    end

    return count_primary_matches(filter_name) > 0
end

-- Creates a compact state signature so the toolbar rebuilds when counts or capacity change.
--[[
The toolbar signature tracks live state that affects labels or visibility.
When it changes, the Cartomancer controls box is rebuilt so counts and hidden
zero-state pills stay accurate after shop buys, Joker creation, or slot changes.
]]
local function get_toolbar_signature()
    local used =
        tonumber(G and G.jokers and G.jokers.config and G.jokers.config.card_count) or 0

    local total =
        tonumber(
            G
            and G.jokers
            and G.jokers.config
            and G.jokers.config.card_limits
            and G.jokers.config.card_limits.total_slots
        ) or used

    return table.concat({
        tostring(#(G and G.jokers and G.jokers.cards or {})),
        tostring(used),
        tostring(total),
        tostring(count_primary_matches("negative")),
        tostring(count_primary_matches("extra")),
        tostring(count_primary_matches("temp")),
        tostring(count_primary_matches("retrigger")),
        tostring(count_primary_matches("destroy")),
        tostring(count_primary_matches("onsell")),
        tostring(count_primary_matches("perm")),
        tostring(get_rarity_cycle_index()),
        tostring(get_primary_filter()),
    }, "|")
end

----------------------------------------------------------------
-- Cartomancer integration
----------------------------------------------------------------

-- Applies the Cartomancer toolbar override once and injects Joker Filter controls.
--[[
This is the core integration point. It overrides Cartomancer's control-row
builder, injects Joker Filter pills, and rebuilds the toolbar whenever the
underlying Joker state changes.
]]
local function ensure_cartomancer_patch()
    if JF.cartomancer_patched then
        return
    end

    if not (Cartomancer and type(Cartomancer.add_visibility_controls) == "function") then
        return
    end

    Cartomancer.add_visibility_controls = function()
        if not G.jokers then
            return
        end

        if G and G.GAME and G.GAME.jf_rarity_cycle_index == nil then
            reset_rarity_cycle_to_rarest_available()
        end

        local toolbar_signature = get_toolbar_signature()

        if G.jokers.jf_toolbar_signature ~= toolbar_signature then
            G.jokers.jf_toolbar_signature = toolbar_signature

            if G.jokers.children.cartomancer_controls then
                G.jokers.children.cartomancer_controls:remove()
                G.jokers.children.cartomancer_controls = nil
            end
        end

        if not (Cartomancer.SETTINGS.jokers_controls_buttons
            and #G.jokers.cards >= Cartomancer.SETTINGS.jokers_controls_show_after) then
            G.jokers.cart_jokers_expanded = false

            if G.jokers.children.cartomancer_controls then
                Cartomancer.align_G_jokers()
            end

            return
        end

        if not G.jokers.children.cartomancer_controls then
            local settings = Sprite(0, 0, 0.425, 0.425, G.ASSET_ATLAS["cart_settings"], { x = 0, y = 0 })
            settings.states.drag.can = false

            local joker_slider = nil
            if G.jokers.cart_jokers_expanded then
                joker_slider = create_slider({
                    id = "joker_slider",
                    w = 6,
                    h = 0.4,
                    ref_table = G.jokers,
                    ref_value = "cart_zoom_slider",
                    min = 0,
                    max = 100,
                    decimal_places = 1,
                    hide_val = true,
                    colour = G.C.CHIPS,
                })
                joker_slider.config.padding = 0
            end

            local row_nodes = {}

            if G.jokers.cart_hide_all then
                row_nodes[#row_nodes + 1] = {
                    n = G.UIT.C,
                    config = { align = "cm" },
                    nodes = {
                        UIBox_button({
                            id = "show_all_jokers",
                            button = "cartomancer_show_all_jokers",
                            label = { localize("carto_jokers_show") },
                            minh = 0.45,
                            minw = 1,
                            col = false,
                            scale = 0.3,
                            colour = G.C.CHIPS,
                        })
                    }
                }
            else
                row_nodes[#row_nodes + 1] = {
                    n = G.UIT.C,
                    config = { align = "cm" },
                    nodes = {
                        UIBox_button({
                            id = "hide_all_jokers",
                            button = "cartomancer_hide_all_jokers",
                            label = { localize("carto_jokers_hide") },
                            minh = 0.45,
                            minw = 1,
                            col = false,
                            scale = 0.3,
                        })
                    }
                }
            end

            row_nodes[#row_nodes + 1] = {
                n = G.UIT.C,
                config = { align = "cm" },
                nodes = {
                    UIBox_button({
                        id = "zoom_jokers",
                        button = "cartomancer_zoom_jokers",
                        label = { localize("carto_jokers_zoom") },
                        minh = 0.45,
                        minw = 1,
                        col = false,
                        scale = 0.3,
                    })
                }
            }

            if joker_slider then
                row_nodes[#row_nodes + 1] = joker_slider
            end

            if should_show_filter_button("all") then
                row_nodes[#row_nodes + 1] = make_filter_button("all", "jf_filter_all", 1.0)
            end
            if should_show_filter_button("slot") then
                row_nodes[#row_nodes + 1] = make_filter_button("slot", "jf_filter_slot", 2.35)
            end
            if should_show_filter_button("negative") then
                row_nodes[#row_nodes + 1] = make_filter_button("negative", "jf_filter_negative", 1.0)
            end
            if should_show_filter_button("extra") then
                row_nodes[#row_nodes + 1] = make_filter_button("extra", "jf_filter_extra", 1.1)
            end
            if should_show_filter_button("temp") then
                row_nodes[#row_nodes + 1] = make_filter_button("temp", "jf_filter_temp", 1.0)
            end
            if should_show_filter_button("retrigger") then
                row_nodes[#row_nodes + 1] = make_filter_button("retrigger", "jf_filter_retrigger", 1.2)
            end
            if should_show_filter_button("destroy") then
                row_nodes[#row_nodes + 1] = make_filter_button("destroy", "jf_filter_destroy", 1.35)
            end
            if should_show_filter_button("onsell") then
                row_nodes[#row_nodes + 1] = make_filter_button("onsell", "jf_filter_onsell", 1.25)
            end
            if should_show_filter_button("rarity") then
                row_nodes[#row_nodes + 1] = make_rarity_button("jf_cycle_rarity", 1.3)
            end
            if should_show_filter_button("perm") then
                row_nodes[#row_nodes + 1] = make_filter_button("perm", "jf_filter_perm", 1.35)
            end

            if Cartomancer.INTERNAL_jokers_menu then
                row_nodes[#row_nodes + 1] = {
                    n = G.UIT.C,
                    config = { align = "cm" },
                    nodes = {
                        {
                            n = G.UIT.C,
                            config = {
                                align = "cm",
                                padding = 0.01,
                                r = 0.1,
                                hover = true,
                                colour = G.C.BLUE,
                                button = "cartomancer_joker_visibility_settings",
                                shadow = true
                            },
                            nodes = {
                                { n = G.UIT.O, config = { object = settings } },
                            }
                        },
                    }
                }
            end

            G.jokers.children.cartomancer_controls = UIBox{
                definition = {
                    n = G.UIT.ROOT,
                    config = {
                        align = "cm",
                        padding = 0.07,
                        colour = G.C.CLEAR,
                    },
                    nodes = {
                        {
                            n = G.UIT.R,
                            config = {
                                align = "tm",
                                padding = 0.07,
                                no_fill = true
                            },
                            nodes = row_nodes
                        }
                    }
                },
                config = {
                    align = "t",
                    bond = "Strong",
                    parent = G.jokers
                },
            }
        end

        G.jokers.children.cartomancer_controls:draw()
    end

    JF.cartomancer_patched = true
    refresh_toolbar()
end

----------------------------------------------------------------
-- Draw hook
----------------------------------------------------------------

local original_card_draw = Card.draw

-- Skips drawing Jokers that are hidden by the active filter.
function Card:draw(...)
    ensure_cartomancer_patch()

    if should_hide(self) then
        return
    end

    return original_card_draw(self, ...)
end

----------------------------------------------------------------
-- Click hook
----------------------------------------------------------------

local original_card_click = Card.click

-- Blocks interaction with Jokers that are hidden by the active filter.
function Card:click(...)
    ensure_cartomancer_patch()

    if should_hide(self) then
        return
    end

    if original_card_click then
        return original_card_click(self, ...)
    end
end

----------------------------------------------------------------
-- Initial patch attempt
----------------------------------------------------------------

ensure_cartomancer_patch()
