-------------------------------------------------------------------------------
-- Module API
-------------------------------------------------------------------------------

function hc.teambalance.init()
    hc.add_menu_command("Change Team", hc.teambalance.change_team_command, hc.CHANGE_TEAM_LEVEL, hc.ADMIN_MENU_KEY, { category = "Discipline" })

    addhook("team", "hc.teambalance.team_hook", -9999)
    addhook("spawn", "hc.teambalance.spawn_hook", -99999)
    addhook("die", "hc.teambalance.die_hook", -99999)
    addhook("delete_player", "hc.teambalance.delete_player_hook")
    addhook("init_player", "hc.teambalance.init_player_hook")
    addhook("init", "hc.teambalance.init_hook")
    addhook("startround", "hc.teambalance.startround_hook")
end


-------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------

function hc.teambalance.init_hook()
    hc.teambalance.count_players()
end

function hc.teambalance.init_player_hook(p, reason)
    local join
    if reason == hc.SCRIPT_INIT then
        join = os.time() - (player(p, "score") + player(p, "deaths"))
    else
        join = os.time()
    end
    hc.players[p].tb = { join = join, team = player(p, "team") }
end

function hc.teambalance.delete_player_hook(p, reason)
    hc.teambalance.count_players()
end

function hc.teambalance.startround_hook(mode)
    local team

    if hc.teambalance.team_count[hc.T] > hc.teambalance.team_count[hc.CT] then
        team = hc.T
    else
        team = hc.CT
    end

    local n = math.floor((hc.teambalance.team_count[team] - hc.teambalance.team_count[3 - team]) / 2)
    for i=1,n do
        local p = hc.teambalance.team_table[team][i].id

        hc.set_no_real_death(p)
        hc.players[p].tb.saved_values = hc.get_player_values(p)
        hc.teambalance.auto_team_balance(p, team)
        parse("setdeaths " .. p .. " " .. (player(p, "deaths") - 1))
    end
end

function hc.teambalance.team_hook(p, team, look)
    if hc.players[p].tb.locked_to_spec and team ~= hc.SPEC then
        hc.info(p, "You are locked to spectator mode.")
        return 1
    end

    if hc.players[p].tb.team_changed and team == hc.players[p].tb.team_changed then
    -- Manually team changed - don't team balance
        hc.players[p].tb.team = team
        hc.teambalance.count_players()
        hc.players[p].tb.team_changed = nil
        return 0
    end

    local old_team = hc.players[p].tb.team

    if team ~= hc.SPEC and team ~= old_team then
        local n_new_team
        local n_other_team

        if team == old_team then
        -- This will never happen! (according to *current* implementation)
            n_new_team = hc.teambalance.team_count[team]
            n_other_team = hc.teambalance.team_count[3 - team]
        elseif old_team == hc.SPEC then
            n_new_team = hc.teambalance.team_count[team] + 1
            n_other_team = hc.teambalance.team_count[3 - team]
        else -- team ~= old_team and team ~= hc.SPEC and old_team ~= hc.SPEC
            n_new_team = hc.teambalance.team_count[team] + 1
            n_other_team = hc.teambalance.team_count[3 - team] - 1
        end

        local n = math.floor((n_new_team - n_other_team) / 2)
        if n >= 1 then
            hc.info(p, "You can't join that team right now.")
            return 1
        end
        hc.players[p].tb.team = team
        hc.teambalance.count_players()
    elseif team ~= hc.SPEC and team == old_team then
    -- Player is not changing team. We can't team balance here,
    -- because CS2D will change back immediately :(
        hc.players[p].tb.no_tb = true
    end
end

function hc.teambalance.spawn_hook(p)
    local values = hc.players[p].tb.saved_values
    if values ~= nil then
    -- This player was team balanced. Try to make the team change as
    -- transparent as possible.
        hc.players[p].tb.saved_values = nil
        return hc.set_player_values(p, values, false)
    end
end

function hc.teambalance.die_hook(p, killer, weapon, x, y)
    if hc.players[p].tb.saved_values then
    -- This player was team balanced. Try to make the team change as
    -- transparent as possible.
        return 1
    end

    if hc.players[p].tb.no_tb then
        hc.players[p].tb.no_tb = nil
        return
    end

    if player(p, "flag") then
    -- If we change them team of a flag bearer,
    -- the flag will change colour!
        return
    end

    local team = hc.players[p].tb.team
    local n = math.floor((hc.teambalance.team_count[team] - hc.teambalance.team_count[3 - team]) / 2)
    if n > 0 then
    -- Team imbalance detected
        for i=1,n do
            if hc.teambalance.team_table[team][i].id == p then
                hc.teambalance.auto_team_balance(p, team)
                return
            end
        end
    end
end


-------------------------------------------------------------------------------
-- Menu commands
-------------------------------------------------------------------------------

function hc.teambalance.change_team_command(p)
    local function f(p, _, item)
        local id = item.id
        local team = player(id, "team")
        local menu

        if team == hc.T then
            menu = {
                { title = "Counter-Terrorist", command = "makect", team = hc.CT, id = id },
                { title = "Spectator", command = "makespec", team = hc.SPEC, id = id }
            }
        elseif team == hc.CT then
            menu = {
                { title = "Terrorist", command = "maket", team = hc.T, id = id },
                { title = "Spectator", command = "makespec", team = hc.SPEC, id = id }
            }
        else
            menu = {
                { title = "Counter-Terrorist", command = "makect", team = hc.CT, id = id },
                { title = "Terrorist", command = "maket", team = hc.T, id = id }
            }
        end

        local function f(p, _, item)
            local id = item.id
            local deaths = player(id, "deaths")
            local health = player(id, "health")
            local old_team = player(id, "team")

            if old_team ~= hc.SPEC then
                hc.set_no_real_death(id)
            end
            if item.team ~= hc.SPEC then
                hc.players[id].tb.join = id
                hc.players[id].tb.team_changed = item.team
                hc.players[id].tb.locked_to_spec = nil
            else
                hc.info(id, "You have been locked to spectator mode.")
                hc.players[id].tb.locked_to_spec = true
            end

            hc.exec(p, item.command .. " " .. id)

            if old_team ~= hc.SPEC and health > 0 then
                parse("setdeaths " .. id .. " " .. deaths)
            end
        end

        hc.show_menu(p, "Change Team", menu, f)
    end

    hc.show_menu(p, "Change Team", hc.get_players({ max_lvl = hc.USER }), f)
end


-------------------------------------------------------------------------------
-- Misc functions
-------------------------------------------------------------------------------

-- Sort the players per team after the time when they joined
function hc.teambalance.count_players()
    local team_table = { [hc.T] = {}, [hc.CT] = {} }
    local n = { [hc.T] = 0, [hc.CT] = 0 }

    for i=1,hc.SLOTS do
        if hc.player_exists(i) then
            local t = hc.players[i].tb.team
            if t ~= hc.SPEC then
                n[t] = n[t] + 1
                team_table[t][n[t]] = { id = i, join = hc.players[i].tb.join }
            end
        end
    end

    local f = function(x1, x2) return x1.join > x2.join end

    table.sort(team_table[hc.T], f)
    table.sort(team_table[hc.CT], f)

    hc.teambalance.team_table = team_table
    hc.teambalance.team_count = n
end

function hc.teambalance.auto_team_balance(p, team)
    hc.event(p, "You have been auto team balanced.")
    if team == hc.T then
        parse("makect " .. p)
    else
        parse("maket " .. p)
    end
end
