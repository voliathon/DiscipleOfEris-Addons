--[[
    FastFollow
    Author: DiscipleOfEris
    Version: 1.2.3
    Commands: /fastfollow, /ffo

    Description:
    This addon provides enhanced "follow" functionality for multi-boxing in Final Fantasy XI.
    It allows one character to be a "leader" and other characters to follow them smoothly.
    This is achieved through IPC (Inter-Process Communication) messages between Windower instances.

    Features:
    - Smooth following logic to maintain a set distance.
    - Automatic pausing of follow during actions like casting spells or using items.
    - A display to show the distance to other characters in the party.
    - Cross-character communication to start/stop following and update positions.
--]]

-- TODO: pause on ranged attacks.

-- #region Libraries
require('strings')
require('tables')
require('sets')
require('coroutine')
packets = require('packets')
res = require('resources')
spells = require('spell_cast_times')
items = res.items
config = require('config')
texts = require('texts')
require('logger')
-- #endregion

-- #region Default Settings
-- Default configuration for the addon.
-- These values are used if no user settings are found.
defaults = {
    show = false, -- Toggles the display of the tracking information.
    min = 0.5,    -- The minimum distance to maintain from the target.
    display = {
        pos = {
            x = 0,
            y = 0,
        },
        bg = {
            red = 0,
            green = 0,
            blue = 0,
            alpha = 102,
        },
        text = {
            font = 'Consolas',
            red = 255,
            green = 255,
            blue = 255,
            alpha = 255,
            size = 10,
        },
    },
}
settings = config.load(defaults)
box = texts.new("", settings.display, settings)
-- #endregion

-- #region Global Variables
-- State variables for the addon's logic.
follow_me = 0           -- Counter for how many characters are following this character.
following = false       -- The name of the character being followed.
target = nil            -- The current target's position information.
last_target = nil       -- The last known position of the target.
min_dist = settings.min^2 -- The minimum distance squared, for performance.
max_dist = 50.0^2       -- The maximum follow distance squared.
spell_dist = 20.4^2     -- The spell range distance squared.
repeated = false        -- A flag to prevent command spam.
last_self = nil         -- The last known position of the player.
last_zone = os.clock()  -- The time of the last zone change.
zone_suppress = 3       -- The time to suppress zone packets after a zone.
zone_min_dist = 1.0^2   -- The minimum distance squared to a zone line to zone.
zoned = false           -- A flag to indicate if the character has recently zoned.
running = false         -- A flag to indicate if the character is currently running.
casting = nil           -- The timestamp of the last casting action.
cast_time = 0           -- The cast time of the current spell/item.
pause_delay = 0.1       -- The delay before pausing for an action.
pause_dismount_delay = 0.5 -- The delay for dismounting.
pauseon = S{}           -- A set of actions that will trigger a pause.
co = nil                -- A coroutine for handling casting pauses.
tracking = false        -- A flag to indicate if tracking is enabled.

track_info = T{}        -- A table to store the positions of tracked characters.
-- #endregion

-- #region Constants
-- Packet and event constants for easy reference.
local PACKET_OUT = { ACTION = 0x01A, USE_ITEM = 0x037, REQUEST_ZONE = 0x05E }
local PACKET_INC = { ACTION = 0x028 }
local PACKET_ACTION_CATEGORY = { MAGIC_CAST = 0x03, DISMOUNT = 0x12 }
local EVENT_ACTION_CATEGORY = { SPELL_FINISH = 4, ITEM_FINISH = 5, SPELL_BEGIN_OR_INTERRUPT = 8, ITEM_BEGIN_OR_INTERRUPT = 9 }
local EVENT_ACTION_PARAM = { BEGIN = 24931, INTERRUPT = 28787 }
-- #endregion

-- #region Core Functions

--[[
    Handles addon unloading.
    Stops all following behavior and adds a small delay to prevent crashing.
--]]
windower.register_event('unload', function()
    windower.send_command('ffo stop')
    coroutine.sleep(0.25) -- Reduce crash on reload
end)

--[[
    Main command handler for the addon.
    Parses user input and executes the corresponding logic.
--]]
windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or nil
    local args = T{...}

    if not command then
        log('Provide a name to follow, or "me" to make others follow you.')
        log('Stop following with "stop" on a single character, or "stopall" on all characters.')
        log('Can configure auto-pausing with pauseon|pausedelay commands.')
        return
    end

    local self_mob = windower.ffxi.get_mob_by_target('me')

    if command == 'followme' or command == 'me' then
        if not self_mob and not repeated then
            repeated = true
            windower.send_command('@wait 1; ffo followme')
            return
        end
        repeated = false
        windower.send_ipc_message('follow ' .. self_mob.name)
        windower.send_ipc_message('track ' .. (settings.show and 'on' or 'off'))

    elseif command == 'stop' then
        if following then
            windower.send_ipc_message('stopfollowing ' .. following)
        end
        following = false
        tracking = false

    elseif command == 'stopall' then
        follow_me = 0
        following = false
        tracking = false
        windower.send_ipc_message('stop')

    elseif command == 'follow' then
        if #args == 0 then
            return windower.add_to_chat(0, 'FastFollow: You must provide a player name to follow.')
        end
        casting = nil
        following = args[1]:lower()
        windower.send_ipc_message('following ' .. following)
        windower.ffxi.follow()

    elseif command == 'pauseon' then
        if #args == 0 then
            return windower.add_to_chat(0, 'FastFollow: To change pausing behavior, provide spell|item|any to pauseon.')
        end

        local arg = args[1]:lower()
        if arg == 'spell' or arg == 'any' then
            if pauseon:contains('spell') then pauseon:remove('spell') else pauseon:add('spell') end
        end
        if arg == 'item' or arg == 'any' then
            if pauseon:contains('item') then pauseon:remove('item') else pauseon:add('item') end
        end
        if arg == 'dismount' or arg == 'any' then
            if pauseon:contains('dismount') then pauseon:remove('dismount') else pauseon:add('dismount') end
        end

        windower.add_to_chat(0, 'FastFollow: Pausing on Spell: ' .. tostring(pauseon:contains('spell')) .. ', Item: ' .. tostring(pauseon:contains('item')))
        -- TODO: Save these settings.

    elseif command == 'pausedelay' then
        pause_delay = tonumber(args[1])
        windower.add_to_chat(0, 'FastFollow: Setting item/spell pause delay to ' .. tostring(pause_delay) .. ' seconds.')

    elseif command == 'info' then
        if not args[1] then
            settings.show = not settings.show
        elseif args[1] == 'on' then
            settings.show = true
        elseif args[1] == 'off' then
            settings.show = false
        end
        windower.send_ipc_message('track ' .. (settings.show and 'on' or 'off'))
        config.save(settings)

    elseif command == 'min' then
        local dist = tonumber(args[1])
        if not dist then return end

        dist = math.min(math.max(0.2, dist), 50.0)
        settings.min = dist
        min_dist = settings.min^2
        config.save(settings)

    elseif #args == 0 then
        windower.send_command('ffo follow ' .. command)
    end
end)

--[[
    Handles IPC messages from other Windower instances.
    This is the core of the multi-boxing communication.
--]]
windower.register_event('ipc message', function(msgStr)
    local args = msgStr:lower():split(' ')
    local command = args:remove(1)
    local self_player = windower.ffxi.get_player()

    if command == 'stop' then
        follow_me = 0
        following = false
        tracking = false
        windower.ffxi.run(false)

    elseif command == 'follow' then
        if following then
            windower.send_ipc_message('stopfollowing ' .. following)
        end
        following = args[1]
        casting = nil
        target_pos = nil
        last_target_pos = nil
        windower.send_ipc_message('following ' .. following)
        windower.ffxi.follow()

    elseif command == 'following' then
        if not self_player or self_player.name:lower() ~= args[1] then return end
        follow_me = follow_me + 1

    elseif command == 'stopfollowing' then
        if not self_player or self_player.name:lower() ~= args[1] then return end
        follow_me = math.max(follow_me - 1, 0)

    elseif command == 'update' then
        local pos = { x = tonumber(args[3]), y = tonumber(args[4]) }
        track_info[args[1]] = pos

        if not following or args[1] ~= following then return end

        zoned = false
        target = { x = pos.x, y = pos.y, zone = tonumber(args[2]) }

        if not last_target then last_target = target end

        if target.zone ~= -1 and (target.x ~= last_target.x or target.y ~= last_target.y or target.zone ~= last_target.zone) then
            last_target = target
        end

    elseif command == 'zone' then
        if not following or args[1] ~= following then return end
        local zone_line = tonumber(args[2])
        local zone_type = tonumber(args[3])
        if zone_line and zone_type then
            zone(zone_line, zone_type, target.zone, target.x, target.y)
        end

    elseif command == 'track' then
        tracking = args[1] == 'on'
    end
end)

--[[
    The main update loop, called on every frame.
    Handles character movement and position updates.
--]]
windower.register_event('prerender', function()
    updateInfo()

    if not follow_me and not following then return end
    
    local self_mob = windower.ffxi.get_mob_by_target('me')
    local info = windower.ffxi.get_info()

    if not self_mob or not info then return end

    if follow_me > 0 then
        -- This character is being followed, so send position updates.
        local args = T{ 'update', self_mob.name, info.zone, self_mob.x, self_mob.y }
        windower.send_ipc_message(args:concat(' '))
    elseif following then
        -- This character is following someone.
        if tracking then
            windower.send_ipc_message('update ' .. self_mob.name .. ' ' .. info.zone .. ' ' .. self_mob.x .. ' ' .. self_mob.y)
        end

        if casting then
            windower.ffxi.run(false)
            running = false
            return
        end

        if not target then
            if running then
                windower.ffxi.run(false)
                running = false
            end
            return
        end

        -- Calculate distance and move the character.
        local distSq = distanceSquared(target, self_mob)
        local len = math.sqrt(distSq)
        if len < 1 then len = 1 end

        if target.zone == info.zone and distSq > min_dist and distSq < max_dist then
            windower.ffxi.run((target.x - self_mob.x) / len, (target.y - self_mob.y) / len)
            running = true
        elseif target.zone == info.zone and distSq <= min_dist then
            windower.ffxi.run(false)
            running = true
        elseif running then
            windower.ffxi.run(false)
            running = false
        end
    end
end)

--[[
    Handles outgoing packets.
    Used to detect actions that should pause following.
--]]
windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
    if blocked then return end

    if id == PACKET_OUT.REQUEST_ZONE then
        if follow_me > 0 then
            local packet = packets.parse('outgoing', modified)
            local self_mob = windower.ffxi.get_mob_by_target('me')
            windower.send_ipc_message('zone %s %d %d':format(self_mob.name, packet['Zone Line'], packet['Type']))
        end

        if following and (os.clock() - last_zone) < zone_suppress then
            return true
        else
            last_zone = os.clock()
        end

    elseif id == PACKET_OUT.ACTION and not casting then
        if not pauseon:contains('spell') and not pauseon:contains('dismount') then return end

        local packet = packets.parse('outgoing', modified)
        if packet.Category ~= PACKET_ACTION_CATEGORY.MAGIC_CAST and packet.Category ~= PACKET_ACTION_CATEGORY.DISMOUNT then return end
        if packet.Category == PACKET_ACTION_CATEGORY.MAGIC_CAST and not pauseon:contains('spell') then return end
        if packet.Category == PACKET_ACTION_CATEGORY.DISMOUNT and not pauseon:contains('dismount') then return end

        local cast_attempt = os.clock()
        casting = cast_attempt
        if pause_delay <= 0 then return end

        windower.ffxi.run(false)
        running = false
        coroutine.schedule(function() packets.inject(packet) end, pause_delay)

        local delay = pause_dismount_delay
        if packet.Category == PACKET_ACTION_CATEGORY.MAGIC_CAST then
            local spell = spells[packet.Param]
            delay = spell.cast_time + 0.5
        end

        if co then coroutine.close(co) end
        co = coroutine.schedule(function()
            if casting and not (casting > cast_attempt) then
                casting = false
            end
        end, pause_delay + 0.5)

        return true

    elseif id == PACKET_OUT.USE_ITEM and not casting then
        if not pauseon:contains('item') then return end

        casting = os.time()
        if pause_delay <= 0 then return end

        local packet = packets.parse('outgoing', modified)
        local item = items[packet.Param]
        if not item or not item.cast_time then return end

        local cast_time = os.time()
        casting = cast_time

        coroutine.schedule(function() packets.inject(packets.parse('outgoing', modified)) end, pause_delay)

        if co then coroutine.close(co) end
        co = coroutine.schedule(function()
            if casting ~= cast_time then return end
            casting = false
        end, pause_delay + item.cast_time)

        return true
    end
end)

--[[
    Handles incoming action packets.
    Used to detect the end of casting or other actions.
--]]
windower.register_event('action', function(action)
    local player = windower.ffxi.get_player()
    if not player or action.actor_id ~= player.id then return end

    if action.category == EVENT_ACTION_CATEGORY.SPELL_FINISH or (action.category == EVENT_ACTION_CATEGORY.SPELL_BEGIN_OR_INTERRUPT and action.param == EVENT_ACTION_PARAM.INTERRUPT) then
        casting = false
    elseif action.category == EVENT_ACTION_CATEGORY.ITEM_FINISH or (action.category == EVENT_ACTION_CATEGORY.ITEM_BEGIN_OR_INTERRUPT and action.param == EVENT_ACTION_PARAM.INTERRUPT) then
        casting = false
    elseif action.category == EVENT_ACTION_CATEGORY.SPELL_BEGIN_OR_INTERRUPT and action.param == EVENT_ACTION_PARAM.BEGIN then
        casting = os.clock()
    end
end)

-- #endregion

-- #region Helper Functions

--[[
    Handles the logic for automatically zoning after the leader.

    @param zone_line The zone line ID.
    @param zone_type The type of zone.
    @param zone The zone ID of the leader.
    @param x The x-coordinate of the leader.
    @param y The y-coordinate of the leader.
--]]
function zone(zone_line, zone_type, zone, x, y)
    coroutine.sleep(0.2 + math.random() * 2.5)
    local self_mob = windower.ffxi.get_mob_by_target('me')
    local info = windower.ffxi.get_info()

    if not self_mob or not info or info.zone ~= zone then return end

    local packet = packets.new('outgoing', PACKET_OUT.REQUEST_ZONE, {
        ['Zone Line'] = zone_line,
        ['Type'] = zone_type,
    })

    local pos = { x = x, y = y }
    local distSq = distanceSquared(self_mob, pos)
    local i = 0
    while distSq > zone_min_dist and i < 12 do
        coroutine.sleep(0.25)
        self_mob = windower.ffxi.get_mob_by_target('me')
        if not self_mob then return end
        distSq = distanceSquared(self_mob, pos)
        i = i + 1
    end

    if distSq <= zone_min_dist then
        packets.inject(packet)
        last_zone = os.clock()
    end
end

--[[
    Updates the informational display with the distances to tracked characters.
--]]
function updateInfo()
    box:visible(settings.show)

    if not settings.show then return end

    local self_mob = windower.ffxi.get_mob_by_target('me')
    if not self_mob then
        box:visible(false)
        return
    end

    local lines = T{}
    for char, pos in pairs(track_info) do
        local dist = math.sqrt(distanceSquared(self_mob, pos))
        lines:insert(string.format('%s %.2f', char, dist))
    end

    local maxWidth = math.max(1, table.reduce(lines, function(a, b) return math.max(a, #b) end, '1'))
    for i, line in ipairs(lines) do lines[i] = lines[i]:lpad(' ', maxWidth) end
    box:text(lines:concat('\n'))
end

--[[
    Calculates the squared distance between two points.
    Using squared distance is more performant as it avoids the square root operation.

    @param A A table with x and y coordinates.
    @param B A table with x and y coordinates.
    @return The squared distance between A and B.
--]]
function distanceSquared(A, B)
    local dx = B.x - A.x
    local dy = B.y - A.y
    return dx * dx + dy * dy
end

-- #endregion