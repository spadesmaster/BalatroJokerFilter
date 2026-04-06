--[[
Joker Filter
============
Adds Cartomancer-integrated joker filter pills for All, Slot, Neg, and Extra
to make it easier to find those jokers you want to sell/replace

Change history as of 2026-04-06:
Update: Onsell now matches when X jokers are sold as well
Update: Added Retrig to find jokers with retriggers in the description
Update: Destruct trys to find jokers that destroy cards like Vampire, Daggers, 
Update: Temp now also looks for self destructs in descripton, added rarity pill to toggle through 
Update: Added icons, fixed Slot to exclude Neg+Extra, added Temp and OnSell pill filters.
Update: Depend on Cartomancer and append four filter pills to Control Row: All Slot Neg Extra

Future ideas:
- Add pills for Eternal/Absolute
- Add pills for economy mult xmult 
- Add pill for bad or is Destruct good enough?
- Sorting?

-- Details
--
-- This version depends on Cartomancer and appends filter pills into
-- Cartomancer's joker control row.
--
-- Pills
-- -----
-- All      = every joker; also clears any active pill filter
-- Slot     = jokers that take a normal slot (not Negative, not Extra)
-- Neg      = jokers with Negative
-- Extra    = jokers with an explicit extra-slot / card-limit bonus
-- Temp     = jokers that are Rental, Expiring/Perishable, self-destruct,
--            or temporary-duration style cards such as "for the next X hands"
-- Retrig   = jokers whose description includes retrigger wording
-- Destruct = jokers whose description uses the active verb "destroys"
--            or "convert all" wording, but not passive wording like "is destroyed"
-- OnSell   = jokers with sell-trigger style effects
-- Rarity   = a single cycling pill that steps through rarity buckets
--            from rarest to most common
--
-- Notes
-- -----
-- - Neg and Extra are not exclusive buckets.
-- - Slot is the practical "replace/sell candidate" bucket.
-- - Temp intentionally includes cards that shrink or expire over time.
-- - Destruct intentionally excludes self-destruction phrases such as
--   "this card is destroyed", which belong in Temp instead.
-- - OnSell uses both property checks and description heuristics.
-- - Visual feedback is the active pill state plus the count on each pill.
-- - Popup feedback and joker-count banners are intentionally removed.

----------------------------------------------------------------
-- Config helpers
----------------------------------------------------------------

local function cfg1(t, key, default_value)
    if t and t[key] ~= nil then
        return t[key]
    end
    return default_value
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------

local mod_config = (SMODS.current_mod and SMODS.current_mod.config) or {}

local CONFIG = {
    default_primary_filter = cfg1(mod_config, "default_primary_filter", "all"),
    button_scale = cfg1(mod_config, "button_scale", 0.3),
    default_rarity_cycle_index = cfg1(mod_config, "default_rarity_cycle_index", 1),
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
    destructive = "Destruct",
    onsell = "OnSell",
    rarity = "Rarity",
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

local JF = {
    primary_filter = CONFIG.default_primary_filter,
    rarity_cycle_index = CONFIG.default_rarity_cycle_index,
    cartomancer_patched = false,
}

G.JF = JF

----------------------------------------------------------------
-- Filter state helpers
----------------------------------------------------------------

local function is_valid_primary_filter(filter_name)
    return FILTER_LABELS[filter_name] ~= nil
end

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

local function get_rarity_cycle_index()
    local current = JF.rarity_cycle_index

    if G and G.GAME and type(G.GAME.jf_rarity_cycle_index) == "number" then
        current = G.GAME.jf_rarity_cycle_index
    end

    return clamp_rarity_cycle_index(current)
end

local function get_current_rarity_entry()
    return RARITY_CYCLE[get_rarity_cycle_index()]
end

local function set_primary_filter(filter_name)
    if not is_valid_primary_filter(filter_name) then
        return
    end

    JF.primary_filter = filter_name

    if G and G.GAME then
        G.GAME.jf_primary_filter = filter_name
    end

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

local function set_rarity_cycle_index(index)
    local clamped = clamp_rarity_cycle_index(index)
    JF.rarity_cycle_index = clamped

    if G and G.GAME then
        G.GAME.jf_rarity_cycle_index = clamped
    end
end

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

local function is_joker(card)
    return card
        and card.ability
        and card.ability.set == "Joker"
end

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

local function is_filter_target(card)
    return is_joker(card) and is_joker_in_row(card)
end

local function has_negative_shader(card)
    return card
        and card.edition
        and card.edition.negative == true
end

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

local function has_extra_slot(card)
    return get_explicit_extra_slot_bonus(card) > 0
end

local function get_joker_rarity(card)
    return card and card.config and card.config.center and card.config.center.rarity
end

local function matches_current_rarity(card)
    local rarity = get_joker_rarity(card)
    local entry = get_current_rarity_entry()
    return entry and rarity == entry.key
end

local function is_expiring(card)
    return card
        and card.ability
        and card.ability.perishable == true
end

local function is_rental(card)
    return card
        and card.ability
        and card.ability.rental == true
end

----------------------------------------------------------------
-- Description scanning helpers
----------------------------------------------------------------

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
    " decreases by ",
    " decrease by ",
    " every round ",
    " every blind ",
    " for the next ",
    " next hands ",
    " next hand ",
    " next rounds ",
    " next round ",
    " disappears after ",
    " until it disappears ",
    " until destroyed ",
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

local DESTRUCTIVE_PATTERNS = {
    " destroys ",
	" convert all",
}

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

local function description_suggests_self_destruct(card)
    return description_matches_any_pattern(card, TEMP_DESTRUCTION_PATTERNS)
end

local function description_suggests_temp_duration(card)
    return description_matches_any_pattern(card, TEMP_DURATION_PATTERNS)
end

local function description_suggests_on_sell(card)
    return description_matches_any_pattern(card, ONSELL_PATTERNS)
end

local function description_suggests_retrigger(card)
    return description_matches_any_pattern(card, RETRIGGER_PATTERNS)
end

local function description_suggests_destructive(card)
    if description_suggests_self_destruct(card) then
        return false
    end

    return description_matches_any_pattern(card, DESTRUCTIVE_PATTERNS)
end

local function is_temporary(card)
    return is_rental(card)
        or is_expiring(card)
        or description_suggests_self_destruct(card)
        or description_suggests_temp_duration(card)
end

local function has_generic_on_sell(card)
    return card
        and (
            card.on_sell ~= nil
            or (card.ability and card.ability.on_sell ~= nil)
            or (card.config and card.config.center and card.config.center.on_sell ~= nil)
        )
end

local function is_on_sell(card)
    return has_generic_on_sell(card) or description_suggests_on_sell(card)
end

local function is_retrigger(card)
    return description_suggests_retrigger(card)
end

local function is_destructive(card)
    return description_suggests_destructive(card)
end

----------------------------------------------------------------
-- Matching logic
----------------------------------------------------------------

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
    elseif filter_name == "destructive" then
        return is_destructive(card)
    elseif filter_name == "onsell" then
        return is_on_sell(card)
    elseif filter_name == "rarity" then
        return matches_current_rarity(card)
    end

    return true
end

local function matches_active_primary_filter(card)
    return matches_primary_filter(get_primary_filter(), card)
end

local function should_hide(card)
    if not is_filter_target(card) then
        return false
    end

    return not matches_active_primary_filter(card)
end

----------------------------------------------------------------
-- Count helpers
----------------------------------------------------------------

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

local function primary_filter_button_label(filter_name)
    return FILTER_LABELS[filter_name] .. " " .. tostring(count_primary_matches(filter_name))
end

local function rarity_button_label()
    local entry = get_current_rarity_entry()
    local count = entry and count_rarity_matches(entry.key) or 0
    return (entry and entry.label or "Rarity") .. " " .. tostring(count)
end

----------------------------------------------------------------
-- Button helpers
----------------------------------------------------------------

local function jf_button_colour(filter_name)
    if get_primary_filter() == filter_name then
        return G.C.RED
    end

    return G.C.BLUE
end

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
-- Callbacks
----------------------------------------------------------------

G.FUNCS.jf_filter_all = function(e)
    set_primary_filter("all")
end

G.FUNCS.jf_filter_slot = function(e)
    set_primary_filter("slot")
end

G.FUNCS.jf_filter_negative = function(e)
    set_primary_filter("negative")
end

G.FUNCS.jf_filter_extra = function(e)
    set_primary_filter("extra")
end

G.FUNCS.jf_filter_temp = function(e)
    set_primary_filter("temp")
end

G.FUNCS.jf_filter_retrigger = function(e)
    set_primary_filter("retrigger")
end

G.FUNCS.jf_filter_destructive = function(e)
    set_primary_filter("destructive")
end

G.FUNCS.jf_filter_onsell = function(e)
    set_primary_filter("onsell")
end

G.FUNCS.jf_cycle_rarity = function(e)
    if get_primary_filter() == "rarity" then
        advance_rarity_cycle()
    end

    set_primary_filter("rarity")
end

----------------------------------------------------------------
-- Cartomancer integration
----------------------------------------------------------------

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

            row_nodes[#row_nodes + 1] = make_filter_button("all", "jf_filter_all", 1.0)
            row_nodes[#row_nodes + 1] = make_filter_button("slot", "jf_filter_slot", 1.0)
            row_nodes[#row_nodes + 1] = make_filter_button("negative", "jf_filter_negative", 1.0)
            row_nodes[#row_nodes + 1] = make_filter_button("extra", "jf_filter_extra", 1.1)
            row_nodes[#row_nodes + 1] = make_filter_button("temp", "jf_filter_temp", 1.0)
            row_nodes[#row_nodes + 1] = make_filter_button("retrigger", "jf_filter_retrigger", 1.2)
            row_nodes[#row_nodes + 1] = make_filter_button("destructive", "jf_filter_destructive", 1.45)
            row_nodes[#row_nodes + 1] = make_filter_button("onsell", "jf_filter_onsell", 1.25)
            row_nodes[#row_nodes + 1] = make_rarity_button("jf_cycle_rarity", 1.3)

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

    if G and G.jokers and G.jokers.children and G.jokers.children.cartomancer_controls then
        G.jokers.children.cartomancer_controls:remove()
        G.jokers.children.cartomancer_controls = nil
    end
end

----------------------------------------------------------------
-- Draw hook
----------------------------------------------------------------

local original_card_draw = Card.draw

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
