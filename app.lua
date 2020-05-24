-- split a string
function string:split(delimiter)
    local result = { }
    local from  = 1
    local delim_from, delim_to = string.find( self, delimiter, from  )
    while delim_from do
        table.insert( result, string.sub( self, from , delim_from-1 ) )
        from  = delim_to + 1
        delim_from, delim_to = string.find( self, delimiter, from  )
    end
    table.insert( result, string.sub( self, from  ) )
    return result
end

local Font = require('Font')
local Music= require('Music')
local Window = require('Window')
local Renderer = require('Renderer')
local Event = require('Event')
local TCPSocket = require('TCPSocket')
local Thread = require('Thread')
local SocketSelect = require('select')
local Common = require('Common')

local wnd = Window("App", 1024, 850)
local rnd = Renderer(wnd)
local font = Font("msyh.ttf", 18)

local WorldWidth = 20
local WorldHeight = 15
local mapData = {}

wnd:show()
rnd:clear()
rnd:copyTo(font:renderText(rnd, "Loading Resources...", 255, 255, 255, 0), 0, 0)
rnd:update()

local function NumberFormat(n)
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    else
        return tostring(n)
    end
end

local function generateMap()
    for i=1, WorldWidth do
        mapData[i] = {}
        for j=1, WorldHeight do
            mapData[i][j] = {}
        end
    end

    for i=1, WorldWidth do
        for j=1, WorldHeight do
            if math.random(100) < 50 then
                local party, color
                if math.random(100) < 50 then
                    party = 1
                    color = table.pack(255, 0, 0, 0)
                else
                    party = 2
                    color = table.pack(0, 0, 255, 0)
                end
                mapData[i][j].party = party
                mapData[i][j].color = color
                mapData[i][j].number = math.random(1000)
            end
        end
    end
end

local function getSurround(x, y, party)
    local same, diff = 0, 0
    local directions = {
        {-1, 0},
        {1, 0},
        {0, 1},
        {0, -1}
    }
    for _, dvec in pairs(directions) do
        local dx = dvec[1]
        local dy = dvec[2]
        if mapData[x + dx] and mapData[x + dx][y + dy] and mapData[x + dx][y + dy].party then
            if mapData[x + dx][y + dy].party == party then same = same + 1
            else diff = diff + 1 end
        end
    end
    return same, diff
end

local selected
local clickBlocked
local playerParty

local function drawMap()
    local r, g, b, a = rnd:getColor()
    rnd:setColor(255, 255, 255, 0)
    local slx, sly = -1, -1
    if selected then slx, sly = table.unpack(selected) end

    for i=1, WorldWidth do
        for j=1, WorldHeight do
            if i == slx and j == sly then rnd:fillRect((i-1)*50, (j-1)*50, 50, 50) end
            if math.abs(i - slx) + math.abs(j - sly) == 1 then
                rnd:setColor(128, 128, 128, 0)
                rnd:fillRect((i-1)*50, (j-1)*50, 50, 50)
                rnd:setColor(255, 255, 255, 0)
            end
            local party = mapData[i][j].party
            if party then
                rnd:drawRect((i-1)*50, (j-1)*50, 50, 50)
                local same, diff = getSurround(i, j, party)
                local content = NumberFormat(mapData[i][j].number)
                if diff >= 3 then
                    content = string.format("%s↓↓", content)
                elseif diff >= 2 then
                    content = string.format("%s↓", content)
                end
                local color = mapData[i][j].color
                rnd:copyTo(font:renderUTF8(rnd, content, table.unpack(color)), (i-1)*50, (j-1)*50)
            end
        end
    end
    rnd:setColor(r, g, b, a)
end

local hint
local function drawHint()
    local nexty = WorldHeight * 50
    if hint then
        pcall(function()
            local t = font:renderUTF8(rnd, hint, 255, 255, 255, 0)
            rnd:copyTo(t, 0, nexty)
            local w, h = t:getSize()
            nexty = nexty + h
        end)
    end

    if playerParty == 1 then
        local t = font:renderUTF8(rnd, "玩家阵营: Red", 255, 0, 0, 0)
        rnd:copyTo(t, 0, nexty)
        local w, h = t:getSize()
        nexty = nexty + h
    elseif playerParty == 2 then
        local t = font:renderUTF8(rnd, "玩家阵营: Blue", 0, 0, 255, 0)
        rnd:copyTo(t, 0, nexty)
        local w, h = t:getSize()
        nexty = nexty + h
    end

    if clickBlocked then
        local t = font:renderUTF8(rnd, "现在是对手的回合", 255, 255, 255, 0)
        rnd:copyTo(t, 0, nexty)
        local w, h = t:getSize()
        nexty = nexty + h
    else
        local t = font:renderUTF8(rnd, "现在是你的回合", 255, 255, 0, 0)
        rnd:copyTo(t, 0, nexty)
        local w, h = t:getSize()
        nexty = nexty + h
    end

    -- 统计两边人数
    local cred = 0
    local cblue = 0
    for i=1, WorldWidth do
        for j=1, WorldHeight do
            if mapData[i][j].party and mapData[i][j].party == 1 then
                cred = cred + mapData[i][j].number
            elseif mapData[i][j].party and mapData[i][j].party == 2 then
                cblue = cblue + mapData[i][j].number
            end
        end
    end

    local t = font:renderUTF8(rnd, string.format("红方: %d 蓝方: %d", cred, cblue), 255, 255, 255, 0)
    rnd:copyTo(t, 0, nexty)
end

local function game_panel()
    while true do
        print("game_panel start.")

        local t = table.pack(Event.poll())
        if t[1] == nil then
            coroutine.yield(table.pack())
        elseif t[1] == "quit" then
            return true
        elseif t[1] == "mousedown" then
            print(table.unpack(t))
            local tox, toy = t[3], t[4]
            if clickBlocked then
                print('click blocked')
            elseif tox >= WorldWidth * 50 or toy >= WorldHeight * 50 then
                print("outside map")
            elseif selected then
                local fromx, fromy = table.unpack(selected)
                selected = nil
                tox = tox // 50 + 1
                toy = toy // 50 + 1 
                print(string.format("selected %d, %d", tox, toy))
                if fromx == tox and fromy == toy then
                    hint = "起点和终点相同."
                elseif math.abs(fromx - tox) + math.abs(fromy - toy) > 1 then
                    hint = "超出移动距离"
                elseif mapData[fromx][fromy].party and mapData[tox][toy].party then
                    if mapData[fromx][fromy].party == mapData[tox][toy].party then
                        if t[2] == "left" then
                            coroutine.yield(table.pack("merge", fromx, fromy, tox, toy))
                        elseif t[2] == "right" then
                            coroutine.yield(table.pack("halfmerge", fromx, fromy, tox, toy))
                        end
                    else
                        if t[2] == "left" then
                            coroutine.yield(table.pack("attack", fromx, fromy, tox, toy))
                        elseif t[2] == "right" then
                            coroutine.yield(table.pack("halfattack", fromx, fromy, tox, toy))
                        end
                    end
                else
                    if t[2] == "left" then
                        coroutine.yield(table.pack("move", fromx, fromy, tox, toy))
                    elseif t[2] == "right" then
                        coroutine.yield(table.pack("halfmove", fromx, fromy, tox, toy))
                    end
                end
            else
                tox = tox // 50 + 1
                toy = toy // 50 + 1
                if mapData[tox][toy].party then
                    if mapData[tox][toy].party == playerParty then
                        hint = string.format("selected %d, %d", tox, toy)
                        print(hint)
                        selected = table.pack(tox, toy)
                    else
                        hint = "只能选取自己阵营的单位"
                    end
                end
            end
        end

        rnd:clear()
        drawMap()
        drawHint()
        rnd:update()
        collectgarbage("collect")
    end
end

local function get_lines(str)
    local t = {}
    local next_begin = 1
    local begin_idx, end_idx = string.find(str, "\n", next_begin)
    while begin_idx do
        table.insert(t, string.sub(str, next_begin, end_idx - 1))
        next_begin = end_idx + 1
        begin_idx, end_idx = string.find(str, "\n", next_begin)
    end

    return t, string.sub(str, next_begin)
end

local function server_game_main(client)
    rnd:clear()
    rnd:copyTo(font:renderUTF8(rnd, "正在同步地图到客户端...", 255, 255, 255, 0), 0, 0)
    rnd:update()
    local tdata = {}
    table.insert(tdata, "begin_map")
    for i=1, WorldWidth do
        for j=1, WorldHeight do
            if mapData[i][j].party then
                table.insert(tdata, string.format("setmap %d %d %d %d", i, j, mapData[i][j].party, mapData[i][j].number))
            else
                table.insert(tdata, string.format("setmap %d %d", i, j))
            end
        end
    end
    table.insert(tdata, "end_map")
    table.insert(tdata, "begin_game\n")
    client:send(table.concat(tdata, "\n"))
    local co = coroutine.create(game_panel)
    local buffer = ""
    playerParty = 1

    while true do
        local flag, data = coroutine.resume(co)
        if not flag then
            print("Panel Error:", data)
            return true
        end

        if not clickBlocked then
            local op, fromx, fromy, tox, toy = table.unpack(data)
            if op then
                clickBlocked = true

                if op == "move" or op == "halfmove" then
                    if op == "move" or mapData[fromx][fromy].number < 2 then
                        mapData[tox][toy] = {
                            party = mapData[fromx][fromy].party,
                            color = mapData[fromx][fromy].color,
                            number = mapData[fromx][fromy].number
                        }
                        mapData[fromx][fromy] = {}
                        hint = ""
                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                    else
                        local tomove = math.floor(mapData[fromx][fromy].number / 2)
                        mapData[tox][toy] = {
                            party = mapData[fromx][fromy].party,
                            color = mapData[fromx][fromy].color,
                            number = tomove
                        }
                        mapData[fromx][fromy].number = mapData[fromx][fromy].number - tomove
                        client:send(string.format("setmap %d %d %d %d\n", fromx, fromy, mapData[fromx][fromy].party, mapData[fromx][fromy].number))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                        hint = ""
                    end
                elseif op == "merge" or op == "halfmerge" then
                    if op == "merge" or mapData[fromx][fromy].number < 2 then
                        mapData[tox][toy].number = mapData[tox][toy].number + mapData[fromx][fromy].number
                        mapData[fromx][fromy] = {}
                        hint = ""
                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                    else
                        local tomove = math.floor(mapData[fromx][fromy].number / 2)
                        mapData[tox][toy].number = mapData[tox][toy].number + tomove
                        mapData[fromx][fromy].number = mapData[fromx][fromy].number - tomove
                        client:send(string.format("setmap %d %d %d %d\n", fromx, fromy, mapData[fromx][fromy].party, mapData[fromx][fromy].number))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                    end
                elseif op == "attack" or op == "halfattack" then
                    local atkbuf, defbuf
                    local same, diff = getSurround(fromx, fromy, mapData[fromx][fromy].party)
                    if diff >= 3 then
                        atkbuf = math.random(100, 105) / 100
                    elseif diff >= 2 then
                        atkbuf = math.random(100, 110) / 100
                    else
                        atkbuf = math.random(100, 115) / 100
                    end

                    local same, diff = getSurround(tox, toy, mapData[tox][toy].party)
                    if diff >= 3 then
                        defbuf = math.random(80, 90) / 100
                    elseif diff >= 2 then
                        defbuf = math.random(90, 100) / 100
                    else
                        defbuf = math.random(100, 115) / 100
                    end

                    local atknum = mapData[fromx][fromy].number
                    local defnum = mapData[tox][toy].number
                    local left = math.floor(atknum * atkbuf - defnum * defbuf)
                    if left > 0 then
                        if left > atknum then
                            left = atknum
                        end
                        hint = string.format("进攻成功, 战损 %d, 击杀 %d", atknum - left, defnum)
                        mapData[tox][toy] = {
                            party = mapData[fromx][fromy].party,
                            color = mapData[fromx][fromy].color,
                            number = left
                        }
                        mapData[fromx][fromy] = {}

                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                        client:send(string.format("sethint 防守失败, 战损 %d, 击杀 %d\n", defnum, atknum - left))
                    elseif left == 0 then
                        hint = string.format("平手, 战损 %d, 击杀 %d", atknum, defnum)
                        mapData[fromx][fromy] = {}
                        mapData[tox][toy] = {}

                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d\n", tox, toy))
                        client:send(string.format("sethint 平手, 战损 %d, 击杀 %d\n", defnum, atknum))
                    else
                        left = math.abs(left)
                        if left > defnum then
                            left = defnum
                        end
                        hint = string.format("进攻失败, 战损 %d, 击杀 %d", atknum, defnum - left)
                        mapData[tox][toy].number = left
                        mapData[fromx][fromy] = {}

                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                        client:send(string.format("sethint 防守成功, 战损 %d, 击杀 %d\n", defnum - left, atknum))
                    end
                else
                    print("unknown operation", op)
                    clickBlocked = nil
                end

                if clickBlocked then
                    client:send("turn_over\n")
                end
            end
        else
            local readset, writeset, errorset = SocketSelect({[client] = true}, {}, {}, 1000)  -- 1ms
            print(readset, writeset, errorset)
            if readset then
                buffer = buffer .. client:recv(2048)
                local message_list, temp_buffer = get_lines(buffer)
                buffer = temp_buffer
                for _, message in ipairs(message_list) do
                    print(message)

                    if message == "turn_over" then
                        clickBlocked = nil
                    else
                        local begin_idx, end_idx = string.find(message, " ")
                        if begin_idx then
                            local opmsg = string.sub(message, 1, begin_idx - 1)
                            if opmsg == "setmap" then
                                local opdata = string.split(message, " ")
                                local opx = math.floor(tonumber(opdata[2]))
                                local opy = math.floor(tonumber(opdata[3]))
                                local opparty = opdata[4]
                                local opnumber = opdata[5]
                                if opparty then
                                    opparty = math.floor(tonumber(opdata[4]))
                                    opnumber = math.floor(tonumber(opdata[5]))
                                    local opcolor
                                    if opparty == 1 then
                                        opcolor = table.pack(255, 0, 0, 0)
                                    else
                                        opcolor = table.pack(0, 0, 255, 0)
                                    end
                                    mapData[opx][opy] = {
                                        party = opparty,
                                        color = opcolor,
                                        number = opnumber
                                    }
                                else
                                    mapData[opx][opy] = {}
                                end
                            elseif opmsg == "sethint" then
                                hint = string.sub(message, end_idx + 1)
                            end
                        end
                    end
                end
            else
                print('socket read timeout.')
            end
        end

        if coroutine.status(co) == "dead" then
            return false
        end
    end
end

local function server_main()
    rnd:clear()
    rnd:copyTo(font:renderUTF8(rnd, "正在创建服务器...", 255, 255, 255, 0), 0, 0)
    rnd:update()

    local server = TCPSocket()
    server:listen("0.0.0.0", 10111)

    generateMap()

    rnd:clear()
    rnd:copyTo(font:renderUTF8(rnd, "等待客户端连接...", 255, 255, 255, 0), 0, 0)
    rnd:update()

    while true do
        while true do
            local t = table.pack(Event.poll())
            if t[1] == nil then break end
            if t[1] == "quit" then
                return true
            end
        end

        local readset = SocketSelect({[server] = true}, {}, {}, 1000)  -- 1ms
        if readset then  -- New connection
            local client, peerip, peerport = server:accept()
            print(string.format('Connected from %s:%d', peerip, peerport))
            server:close()

            return server_game_main(client)
        end
    end
end

local function client_main()
    rnd:clear()
    rnd:copyTo(font:renderUTF8(rnd, "连接到服务器...", 255, 255, 255, 0), 0, 0)
    rnd:update()

    print("Connecting to server...")
    local client = TCPSocket()
    client:connect("106.53.10.163", 59632)

    for i=1, WorldWidth do
        mapData[i] = {}
        for j=1, WorldHeight do
            mapData[i][j] = {}
        end
    end

    local buffer = ""

    local flagGameStart = false
    while not flagGameStart do
        buffer = buffer .. client:recv(2048)
        local message_list, temp_buffer = get_lines(buffer)
        buffer = temp_buffer
        for _, message in ipairs(message_list) do
            print(message)

            if message == "begin_map" then
                print("Begin receiving map data.")
            elseif message == "end_map" then
                print("End receiving map data.")
            elseif message == "begin_game" then
                print("Game start.")
                flagGameStart = true
            else
                local begin_idx, end_idx = string.find(message, " ")
                if begin_idx then
                    local opmsg = string.sub(message, 1, begin_idx - 1)
                    if opmsg == "setmap" then
                        local opdata = string.split(message, " ")
                        local opx = math.floor(tonumber(opdata[2]))
                        local opy = math.floor(tonumber(opdata[3]))
                        local opparty = opdata[4]
                        local opnumber = opdata[5]
                        if opparty then
                            opparty = math.floor(tonumber(opdata[4]))
                            opnumber = math.floor(tonumber(opdata[5]))
                            local opcolor
                            if opparty == 1 then
                                opcolor = table.pack(255, 0, 0, 0)
                            else
                                opcolor = table.pack(0, 0, 255, 0)
                            end
                            mapData[opx][opy] = {
                                party = opparty,
                                color = opcolor,
                                number = opnumber
                            }
                        else
                            mapData[opx][opy] = {}
                        end
                    end
                end
            end
        end
    end

    local co = coroutine.create(game_panel)
    clickBlocked = true
    playerParty = 2

    while true do
        local flag, data = coroutine.resume(co)
        if not flag then
            print("Panel Error:", data)
            return true
        end

        if not clickBlocked then
            local op, fromx, fromy, tox, toy = table.unpack(data)
            if op then
                clickBlocked = true

                if op == "move" or op == "halfmove" then
                    if op == "move" or mapData[fromx][fromy].number < 2 then
                        mapData[tox][toy] = {
                            party = mapData[fromx][fromy].party,
                            color = mapData[fromx][fromy].color,
                            number = mapData[fromx][fromy].number
                        }
                        mapData[fromx][fromy] = {}
                        hint = ""
                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                    else
                        local tomove = math.floor(mapData[fromx][fromy].number / 2)
                        mapData[tox][toy] = {
                            party = mapData[fromx][fromy].party,
                            color = mapData[fromx][fromy].color,
                            number = tomove
                        }
                        mapData[fromx][fromy].number = mapData[fromx][fromy].number - tomove
                        client:send(string.format("setmap %d %d %d %d\n", fromx, fromy, mapData[fromx][fromy].party, mapData[fromx][fromy].number))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                        hint = ""
                    end
                elseif op == "merge" or op == "halfmerge" then
                    if op == "merge" or mapData[fromx][fromy].number < 2 then
                        mapData[tox][toy].number = mapData[tox][toy].number + mapData[fromx][fromy].number
                        mapData[fromx][fromy] = {}
                        hint = ""
                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                    else
                        local tomove = math.floor(mapData[fromx][fromy].number / 2)
                        mapData[tox][toy].number = mapData[tox][toy].number + tomove
                        mapData[fromx][fromy].number = mapData[fromx][fromy].number - tomove
                        client:send(string.format("setmap %d %d %d %d\n", fromx, fromy, mapData[fromx][fromy].party, mapData[fromx][fromy].number))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                    end
                elseif op == "attack" or op == "halfattack" then
                    local atkbuf, defbuf
                    local same, diff = getSurround(fromx, fromy, mapData[fromx][fromy].party)
                    if diff >= 3 then
                        atkbuf = math.random(100, 105) / 100
                    elseif diff >= 2 then
                        atkbuf = math.random(100, 110) / 100
                    else
                        atkbuf = math.random(100, 115) / 100
                    end

                    local same, diff = getSurround(tox, toy, mapData[tox][toy].party)
                    if diff >= 3 then
                        defbuf = math.random(80, 90) / 100
                    elseif diff >= 2 then
                        defbuf = math.random(90, 100) / 100
                    else
                        defbuf = math.random(100, 115) / 100
                    end

                    local atknum = mapData[fromx][fromy].number
                    local defnum = mapData[tox][toy].number
                    local left = math.floor(atknum * atkbuf - defnum * defbuf)
                    if left > 0 then
                        if left > atknum then
                            left = atknum
                        end
                        hint = string.format("进攻成功, 战损 %d, 击杀 %d", atknum - left, defnum)
                        mapData[tox][toy] = {
                            party = mapData[fromx][fromy].party,
                            color = mapData[fromx][fromy].color,
                            number = left
                        }
                        mapData[fromx][fromy] = {}

                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                        client:send(string.format("sethint 防守失败, 战损 %d, 击杀 %d\n", defnum, atknum - left))
                    elseif left == 0 then
                        hint = string.format("平手, 战损 %d, 击杀 %d", atknum, defnum)
                        mapData[fromx][fromy] = {}
                        mapData[tox][toy] = {}

                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d\n", tox, toy))
                        client:send(string.format("sethint 平手, 战损 %d, 击杀 %d\n", defnum, atknum))
                    else
                        left = math.abs(left)
                        if left > defnum then
                            left = defnum
                        end
                        hint = string.format("进攻失败, 战损 %d, 击杀 %d", atknum, defnum - left)
                        mapData[tox][toy].number = left
                        mapData[fromx][fromy] = {}

                        client:send(string.format("setmap %d %d\n", fromx, fromy))
                        client:send(string.format("setmap %d %d %d %d\n", tox, toy, mapData[tox][toy].party, mapData[tox][toy].number))
                        client:send(string.format("sethint 防守成功, 战损 %d, 击杀 %d\n", defnum - left, atknum))
                    end
                else
                    print("unknown operation", op)
                    clickBlocked = nil
                end

                if clickBlocked then
                    client:send("turn_over\n")
                end
            end
        else
            local readset, writeset, errorset = SocketSelect({[client] = true}, {}, {}, 1000)  -- 1ms
            print(readset, writeset, errorset)
            if readset then
                buffer = buffer .. client:recv(2048)
                local message_list, temp_buffer = get_lines(buffer)
                buffer = temp_buffer
                for _, message in ipairs(message_list) do
                    print(message)

                    if message == "turn_over" then
                        clickBlocked = nil
                    else
                        local begin_idx, end_idx = string.find(message, " ")
                        if begin_idx then
                            local opmsg = string.sub(message, 1, begin_idx - 1)
                            if opmsg == "setmap" then
                                local opdata = string.split(message, " ")
                                local opx = math.floor(tonumber(opdata[2]))
                                local opy = math.floor(tonumber(opdata[3]))
                                local opparty = opdata[4]
                                local opnumber = opdata[5]
                                if opparty then
                                    opparty = math.floor(tonumber(opdata[4]))
                                    opnumber = math.floor(tonumber(opdata[5]))
                                    
                                    local opcolor
                                    if opparty == 1 then
                                        opcolor = table.pack(255, 0, 0, 0)
                                    else
                                        opcolor = table.pack(0, 0, 255, 0)
                                    end
                                    mapData[opx][opy] = {
                                        party = opparty,
                                        color = opcolor,
                                        number = opnumber
                                    }
                                else
                                    mapData[opx][opy] = {}
                                end
                            elseif opmsg == "sethint" then
                                hint = string.sub(message, end_idx + 1)
                            end
                        end
                    end
                end
            else
                print('socket read timeout.')
            end
        end

        if coroutine.status(co) == "dead" then
            return false
        end
    end
end

while true do
    rnd:clear()
    local t1 = font:renderUTF8(rnd, "按下 S 键开启一场对局", 255, 255, 255, 0)
    local t2 = font:renderUTF8(rnd, "按下 C 键加入一场对局", 255, 255, 255, 0)
    rnd:copyTo(t1, 0, 0)
    local w, h = t1:getSize()
    rnd:copyTo(t2, 0, h + 10)
    rnd:update()

    local t = table.pack(Event.wait())
    if t[1] == "quit" then
        break
    end

    if t[1] == "keydown" then
        if t[2] == "s" then
            if server_main() then break end
        elseif t[2] == "c" then
            if client_main() then break end
        end
    end
end
