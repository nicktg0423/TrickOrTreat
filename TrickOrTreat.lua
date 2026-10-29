--- Trick or Treat Deck, by NickTG. v1.0.0.
--- A new deck. Every time you select a blind, a card flips: 50/50.
---   Treat: a Negative Candy joins your Jokers. It copies the Joker to its right
---          (as Blueprint does) and melts after 3 rounds.
---   Trick: a Negative Ghost joins your Jokers. It possesses a random real Joker,
---          which is debuffed until the Ghost leaves 3 rounds later.
--- Skipped blinds don't flip. Every other deck plays exactly as vanilla.
---
--- Line numbers below point into the game code as it runs (the lovely dump,
--- "dump/") and Steamodded 1.0.0~BETA-1620a ("smods/").

local THIS_MOD = SMODS.current_mod          -- must be captured at load time
local cfg      = THIS_MOD.config
if type(cfg.candy_rounds) ~= 'number' then cfg.candy_rounds = 3 end
if type(cfg.ghost_rounds) ~= 'number' then cfg.ghost_rounds = 3 end

local CANDY, GHOST, DECK = 'j_ntgtt_candy', 'j_ntgtt_ghost', 'b_ntgtt_trick_or_treat'
local ORANGE, PURPLE = HEX('FD8200'), HEX('8A4FC7')
local SOURCE = 'ntgtt_ghost'                -- key in card.ability.debuff_sources

local TT = {}
local function log(msg) sendInfoMessage(msg, 'TrickOrTreat') end

local function key_of(card) return card and card.config and card.config.center and card.config.center.key end
function TT.is_candy(card) return key_of(card) == CANDY end
function TT.is_ghost(card) return key_of(card) == GHOST end
function TT.is_ours(card) local k = key_of(card); return k == CANDY or k == GHOST end
function TT.on_deck()
    return G.GAME and G.GAME.selected_back and G.GAME.selected_back.effect
        and G.GAME.selected_back.effect.center and G.GAME.selected_back.effect.center.key == DECK
end
local function gone(card) return not card or card.REMOVED or card.removed or card.getting_sliced or card.ntgtt_leaving end
local function name_of(card)
    return localize { type = 'name_text', set = 'Joker', key = key_of(card) } or '?'
end
-- A Negative Candy or Ghost uses the second atlas row, colour-adjusted for the
-- Negative shader so it still looks like itself.
local function fix_row(card)
    local s = card.children and card.children.center
    if not s then return end
    local want = (card.edition and card.edition.negative) and 1 or 0
    if s.sprite_pos and s.sprite_pos.y ~= want then
        s:set_sprite_pos({ x = card.config.center.pos.x, y = want })
    end
end
local function rounds_text(n, verb)
    n = n or 0
    if n <= 1 then return 'at end of round' end
    return 'in ' .. n .. ' rounds'
end

SMODS.Atlas { key = 'jokers', path = 'candy_ghost_jokers.png', px = 71, py = 95 }
SMODS.Atlas { key = 'back',   path = 'deck_back.png',          px = 71, py = 95 }

----------------------------------------------------------------------
-- Candy: a Blueprint that melts. SMODS.blueprint_effect (smods/src/utils.lua:2219)
-- returns nothing for a debuffed target, so a Ghost on the copied Joker cancels it,
-- and it chains through another Candy or a Blueprint the same way Blueprint does.
----------------------------------------------------------------------
SMODS.Joker {
    key = 'candy', atlas = 'jokers', pos = { x = 0, y = 0 },
    rarity = 1, cost = 0, discovered = true, unlocked = true,
    blueprint_compat = true, eternal_compat = false, perishable_compat = false,
    config = { extra = { rounds = 3 } },
    in_pool = function() return false end,       -- only the flip makes one
    loc_txt = {
        name = 'Candy',
        text = {
            'Copies the ability of the',
            '{C:attention}Joker{} to the right',
            '{C:inactive}Melts #1#',
        },
    },
    loc_vars = function(self, info_queue, card)
        local ex = card.ability.extra or {}
        local main_end
        if card.area and card.area == G.jokers then
            card.ability.blueprint_compat_ui = card.ability.blueprint_compat_ui or ''
            card.ability.blueprint_compat_check = nil
            -- vanilla Blueprint's compatible/incompatible box (dump/card.lua:1008)
            main_end = { {n = G.UIT.C, config = {align = 'bm', minh = 0.4}, nodes = {
                {n = G.UIT.C, config = {ref_table = card, align = 'm', colour = G.C.JOKER_GREY, r = 0.05, padding = 0.06, func = 'blueprint_compat'}, nodes = {
                    {n = G.UIT.T, config = {ref_table = card.ability, ref_value = 'blueprint_compat_ui', colour = G.C.UI.TEXT_LIGHT, scale = 0.32 * 0.8}},
                }},
            }} }
        end
        return { vars = { rounds_text(ex.rounds or cfg.candy_rounds) }, main_end = main_end }
    end,
    update = function(self, card, dt)
        fix_row(card)
        -- same rule as vanilla Blueprint (dump/card.lua:4679)
        if G.STAGE ~= G.STAGES.RUN or not G.jokers or card.area ~= G.jokers then return end
        local other
        for i = 1, #G.jokers.cards do if G.jokers.cards[i] == card then other = G.jokers.cards[i + 1] end end
        -- plus: a debuffed (possessed) Joker reads as incompatible, since nothing gets copied
        card.ability.blueprint_compat = (other and other ~= card and other.config.center.blueprint_compat and not other.debuff) and 'compatible' or 'incompatible'
    end,
    calculate = function(self, card, context)
        local other
        for i = 1, #G.jokers.cards do if G.jokers.cards[i] == card then other = G.jokers.cards[i + 1] end end
        local ret = SMODS.blueprint_effect(card, other, context)
        if ret then ret.colour = ORANGE end
        return ret
    end,
}

----------------------------------------------------------------------
-- Ghost: possesses one real Joker. The possession is stored on the target
-- (ability.ntgtt_haunt = the Ghost's uid) plus a debuff source, so it survives
-- save and load; TT.upkeep keeps the two in step every frame.
----------------------------------------------------------------------
SMODS.Joker {
    key = 'ghost', atlas = 'jokers', pos = { x = 1, y = 0 },
    rarity = 1, cost = 0, discovered = true, unlocked = true,
    blueprint_compat = false, eternal_compat = false, perishable_compat = false,
    config = { extra = { rounds = 3, uid = 0 } },
    in_pool = function() return false end,
    loc_txt = {
        name = 'Ghost',
        text = {
            '{C:red}Debuffs{} the {C:attention}Joker{} it haunts',
            '{C:inactive}Haunting: {C:attention}#1#',
            '{C:inactive}Leaves #2#',
            '{C:inactive}Can\'t be sold or destroyed',
        },
    },
    loc_vars = function(self, info_queue, card)
        local ex = card.ability.extra or {}
        local t = TT.target_of(card)
        return { vars = { t and name_of(t) or 'nobody yet', rounds_text(ex.rounds or cfg.ghost_rounds) } }
    end,
    update = function(self, card, dt) fix_row(card) end,
    calculate = function(self, card, context) end,
}

----------------------------------------------------------------------
-- The deck
----------------------------------------------------------------------
SMODS.Back {
    key = 'trick_or_treat', atlas = 'back', pos = { x = 0, y = 0 },
    unlocked = true, discovered = true,
    loc_txt = {
        name = 'Trick or Treat Deck',
        text = {
            'Select a blind: flip for',
            '{C:attention}Trick{} or {C:attention}Treat{}',
            '{C:attention}Treat:{} a {C:dark_edition}Negative{} Candy',
            '{C:attention}Trick:{} a {C:dark_edition}Negative{} Ghost',
        },
    },
    calculate = function(self, back, context)
        -- setting_blind fires once, from new_round (dump/functions/state_events.lua:282),
        -- before the hand is drawn; skipped blinds never reach it.
        if context.setting_blind then
            G.GAME.ntgtt_counted = false
            TT.queue_flip()
        end
        -- end_of_round reaches the deck once per round (state_events.lua:107). Smods
        -- leaves context.cardarea set from the Joker pass, so a flag guards it instead.
        if context.end_of_round and (not context.game_over or SMODS.saved) and G.GAME.ntgtt_counted == false then
            G.GAME.ntgtt_counted = true
            TT.count_down()
        end
    end,
}

----------------------------------------------------------------------
-- The flip: a face-down card in the middle of the screen turns over to show
-- the Candy or the Ghost, "TREAT!" or "TRICK!", then flies into the Joker row.
-- About a second at normal game speed.
----------------------------------------------------------------------
function TT.queue_flip(force)
    local treat = pseudorandom('ntgtt_flip') < 0.5
    if force ~= nil then treat = force end      -- rig tests only
    local key = treat and CANDY or GHOST
    log('Flip: ' .. (treat and 'Treat (Candy)' or 'Trick (Ghost)') .. ' at ante ' .. tostring(G.GAME.round_resets.ante)
        .. ' ' .. tostring(G.GAME.blind and G.GAME.blind.config and G.GAME.blind.config.blind and G.GAME.blind.config.blind.key))
    local card
    G.E_MANAGER:add_event(Event({ func = function()
        card = SMODS.create_card({ set = 'Joker', key = key, area = G.play, no_edition = true, skip_materialize = true })
        card:set_edition({ negative = true }, true, true)
        card.ability.extra.rounds = treat and cfg.candy_rounds or cfg.ghost_rounds
        if not treat then
            G.GAME.ntgtt_uid = (G.GAME.ntgtt_uid or 0) + 1
            card.ability.extra.uid = G.GAME.ntgtt_uid
        end
        card.facing, card.sprite_facing = 'back', 'back'
        G.play:emplace(card, nil, true)      -- stay face down (dump/cardarea.lua:55)
        play_sound('card1')
        return true end }))
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.25, func = function()
        card:flip(); play_sound('card1', 1.15)
        return true end }))
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
        attention_text({ text = treat and 'TREAT!' or 'TRICK!', scale = 1.1, hold = 1.9, major = card,
            backdrop_colour = treat and ORANGE or PURPLE, align = 'tm', offset = { x = 0, y = -0.15 }, silent = true })
        play_sound(treat and 'tarot1' or 'cancel', treat and 1.2 or 0.8)
        card:juice_up(0.3, 0.4)
        return true end }))
    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 1.5, func = function()
        G.play:remove_card(card)
        card:add_to_deck()
        G.jokers:emplace(card)
        return true end }))
end

----------------------------------------------------------------------
-- Countdown: a round is one blind played. The blind a card arrives on is round 1.
----------------------------------------------------------------------
function TT.count_down()
    if not G.jokers then return end
    for _, c in ipairs(G.jokers.cards) do
        if TT.is_ours(c) and not gone(c) and not (c.ability.extra or {}).dud then
            c.ability.extra.rounds = (c.ability.extra.rounds or 1) - 1
            if c.ability.extra.rounds <= 0 then TT.leave(c) end
        end
    end
end

function TT.leave(c)
    c.ntgtt_leaving = true
    if TT.is_ghost(c) then
        local t = TT.target_of(c)
        if t then TT.release(t) end
        log('Ghost ' .. tostring(c.ability.extra.uid) .. ' leaves')
    else
        log('Candy melts')
    end
    -- text first, straight into the round's event flow (as Gros Michel does); queued
    -- from inside an event it would land after cash-out (review, 24 Oct)
    card_eval_status_text(c, 'extra', nil, nil, nil, { message = TT.is_ghost(c) and 'Gone!' or 'Melted!',
        colour = TT.is_ghost(c) and PURPLE or ORANGE })
    G.E_MANAGER:add_event(Event({ func = function() c:start_dissolve(); return true end }))
end

----------------------------------------------------------------------
-- Possession bookkeeping
----------------------------------------------------------------------
function TT.target_of(ghost)
    if not G.jokers or not ghost.ability.extra then return nil end
    local uid = ghost.ability.extra.uid
    for _, c in ipairs(G.jokers.cards) do
        if c.ability.ntgtt_haunt == uid and not gone(c) then return c end
    end
end

function TT.release(t)
    t.ability.ntgtt_haunt = nil
    SMODS.debuff_card(t, nil, SOURCE)
end

function TT.possess(ghost, t)
    t.ability.ntgtt_haunt = ghost.ability.extra.uid
    SMODS.debuff_card(t, true, SOURCE)
    log('Ghost ' .. tostring(ghost.ability.extra.uid) .. ' possesses ' .. tostring(key_of(t)))
    t:juice_up(0.5, 0.5); ghost:juice_up(0.3, 0.3)
    card_eval_status_text(t, 'extra', nil, nil, nil, { message = 'Possessed!', colour = PURPLE })
end

-- Runs every frame in a run on this deck. Cheap: a handful of Jokers.
function TT.upkeep()
    local ghosts, live = {}, {}
    for _, c in ipairs(G.jokers.cards) do
        if TT.is_ours(c) and not gone(c) then
            local ex = c.ability.extra
            if ex.dud then
                -- a copy made by Invisible Joker or Ankh with nothing else to pick: vanishes
                c.ntgtt_leaving = true
                log('Copy of ' .. key_of(c) .. ' removed')
                card_eval_status_text(c, 'extra', nil, nil, nil, { message = 'Can\'t copy!', colour = G.C.RED })
                G.E_MANAGER:add_event(Event({ func = function() c:start_dissolve(); return true end }))
            elseif (ex.rounds or 1) <= 0 then
                TT.leave(c)                     -- e.g. saved during its dissolve, then continued
            elseif TT.is_ghost(c) then
                if not ex.uid or ex.uid == 0 then
                    G.GAME.ntgtt_uid = (G.GAME.ntgtt_uid or 0) + 1; ex.uid = G.GAME.ntgtt_uid
                end
                ghosts[#ghosts + 1] = c; live[ex.uid] = c
            end
        end
    end
    -- a haunted Joker whose Ghost has gone is released
    for _, c in ipairs(G.jokers.cards) do
        local uid = c.ability.ntgtt_haunt
        if uid and (not live[uid] or TT.is_ours(c)) then TT.release(c) end
    end
    -- every Ghost holds exactly one Joker if it can; a sold or destroyed one makes it jump
    for _, g in ipairs(ghosts) do
        local t = TT.target_of(g)
        if t then
            if not (t.ability.debuff_sources and t.ability.debuff_sources[SOURCE]) then
                SMODS.debuff_card(t, true, SOURCE)
            end
        else
            local pool = {}
            for _, c in ipairs(G.jokers.cards) do
                if not TT.is_ours(c) and not c.ability.ntgtt_haunt and not gone(c) and c.ability.set == 'Joker' then
                    pool[#pool + 1] = c
                end
            end
            if #pool > 0 then TT.possess(g, pseudorandom_element(pool, pseudoseed('ntgtt_haunt'))) end
        end
    end
end

local game_update_ref = Game.update
function Game:update(dt)
    game_update_ref(self, dt)
    if G.STAGE == G.STAGES.RUN and G.jokers and G.GAME and TT.on_deck() and G.STATE ~= G.STATES.GAME_OVER then
        TT.upkeep()
    end
end

----------------------------------------------------------------------
-- Ghosts can't be sold or destroyed. Every vanilla check (selling, Ceremonial
-- Dagger, Madness, Ankh, Hex) goes through SMODS.is_eternal (smods/src/utils.lua:2976).
----------------------------------------------------------------------
local is_eternal_ref = SMODS.is_eternal
function SMODS.is_eternal(card, trigger)
    if TT.is_ghost(card) then return true end
    return is_eternal_ref(card, trigger)
end

-- Candy and Ghost sell for $0.
local set_cost_ref = Card.set_cost
function Card:set_cost(...)
    set_cost_ref(self, ...)
    if TT.is_ours(self) then self.sell_cost = 0; self.sell_cost_label = self.facing == 'back' and '?' or 0 end
end

----------------------------------------------------------------------
-- Candy and Ghost only come from the flip, so Invisible Joker and Ankh never copy
-- them. Both pick with pseudorandom_element(jokers, pseudoseed('invisible' /
-- 'ankh_choice')) (dump/card.lua:2775, 1756). The seed is computed first, so it
-- flags the very next pick, which leaves ours out. If nothing else is left, the
-- copy is made and then removed by TT.upkeep.
----------------------------------------------------------------------
local pseudoseed_ref = pseudoseed
function pseudoseed(key, predict_seed)
    if (key == 'invisible' or key == 'ankh_choice') and not predict_seed then TT.copy_pick = true end
    return pseudoseed_ref(key, predict_seed)
end

local pre_ref = pseudorandom_element
function pseudorandom_element(_t, seed, args)
    if TT.copy_pick then
        TT.copy_pick = nil
        if type(_t) == 'table' and _t[1] and type(_t[1]) == 'table' and _t[1].config then
            local f = {}
            for _, c in ipairs(_t) do if not TT.is_ours(c) then f[#f + 1] = c end end
            if #f > 0 and #f < #_t then _t = f end
        end
    end
    return pre_ref(_t, seed, args)
end

-- A copy of a possessed Joker is not possessed; a copy of a Ghost is a dud.
local copy_card_ref = copy_card
function copy_card(other, new_card, ...)
    local c = copy_card_ref(other, new_card, ...)
    if c and c.ability then
        if c.ability.ntgtt_haunt then
            c.ability.ntgtt_haunt = nil
            if c.ability.debuff_sources then c.ability.debuff_sources[SOURCE] = nil end
            local still = c.ability.perishable and (c.ability.perish_tally or 1) <= 0
            for _, v in pairs(c.ability.debuff_sources or {}) do if v == true then still = true end end
            if not still then c.debuff = false end
        end
        if TT.is_ours(c) then c.ability.extra.dud = true end
    end
    return c
end

----------------------------------------------------------------------
-- Config: how long each lasts
----------------------------------------------------------------------
local ROUND_OPTS = { '1', '2', '3', '4', '5', '6' }
G.FUNCS.ntgtt_candy_rounds = function(args) cfg.candy_rounds = args.to_key end
G.FUNCS.ntgtt_ghost_rounds = function(args) cfg.ghost_rounds = args.to_key end

THIS_MOD.config_tab = function()
    local function row(node) return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = { node } } end
    return {
        n = G.UIT.ROOT, config = { align = 'cm', padding = 0.1, colour = G.C.CLEAR },
        nodes = {
            row({ n = G.UIT.T, config = { text = 'How long each one lasts (new ones only)', scale = 0.32, colour = G.C.UI.TEXT_LIGHT } }),
            row(create_option_cycle({ label = 'Candy melts after', options = ROUND_OPTS, current_option = cfg.candy_rounds,
                opt_callback = 'ntgtt_candy_rounds', w = 3, scale = 0.8, colour = ORANGE })),
            row(create_option_cycle({ label = 'Ghost leaves after', options = ROUND_OPTS, current_option = cfg.ghost_rounds,
                opt_callback = 'ntgtt_ghost_rounds', w = 3, scale = 0.8, colour = PURPLE })),
        },
    }
end

TT_DEBUG = TT   -- read by the test rig; harmless in play
log('Loaded v1.0.0, candy_rounds=' .. tostring(cfg.candy_rounds) .. ' ghost_rounds=' .. tostring(cfg.ghost_rounds))
