--[[
Joker Filter
============
Adds Cartomancer-integrated joker filter pills for All, Slot, Neg, and Extra
to make it easier to find those jokers you want to sell/replace

Change history:
Updated 2026-04-06 Depend on Cartomancer and append four filter pills to Control Row: All Slot Neg Extra

Future ideas:
- Add pills for Eternal/Absolute Rental/Expiring
- Add pills for economy mult xmult 
- Add pill for bad to find destructive jokers like Arsonist 

Definitions
-----------
All   = every joker
Slot  = jokers that take a normal slot (not Negative, not Extra)
Neg   = jokers with Negative
Extra = jokers with an extra-slot property
]]

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
}

----------------------------------------------------------------
-- State
----------------------------------------------------------------

local FILTER_LABELS = {
    all = "All",
    slot = "Slot",
    negative = "Neg",
    extra = "Extra",
}

local JF = {
    primary_filter = CONFIG.default_primary_filter,
    cartomancer_patched = false,
}

G.JF = JF

----------------------------------------------------------------
-- Filter state helpers
----------------------------------------------------------------

local function is_valid_primary_filter(filter_name)
    return FILTER_LABELS[filter_name] ~= nil
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

local function has_extra_slot(card)
    return card
        and card.edition
        and (card.edition.card_limit or 0) > 0
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

local function primary_filter_button_label(filter_name)
    return FILTER_LABELS[filter_name] .. " " .. tostring(count_primary_matches(filter_name))
end

----------------------------------------------------------------
-- Button helpers
----------------------------------------------------------------

local function jf_button_colour(filter_name)
    if get_primary_filter() == filter_name then
        return G.C.CHIPS
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
            row_nodes[#row_nodes + 1] = make_filter_button("extra", "jf_filter_extra", 1.15)

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
