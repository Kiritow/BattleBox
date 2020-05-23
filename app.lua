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
        local t = font:renderUTF8(rnd, hint, 255, 255, 255, 0)
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

generateMap()


while true do
    local t = table.pack(Event.wait())
    -- print(table.unpack(t))
	if t[1] == "quit" then
		break
    end
    if t[1] == "mouseover" then goto loopend end
    if t[1] == "mousedown" then
        print(table.unpack(t))
        local tox, toy = t[3], t[4]
        if tox >= WorldWidth * 50 or toy >= WorldHeight * 50 then
            print("outside map")
        elseif t[2] == "right" then
            selected = nil
            hint = nil
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
                    mapData[tox][toy].number = mapData[tox][toy].number + mapData[fromx][fromy].number
                    mapData[fromx][fromy] = {}
                else
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
                    elseif left == 0 then
                        hint = string.format("平手, 损 %d, 击杀 %d", atknum, defnum)
                        mapData[fromx][fromy] = {}
                        mapData[tox][toy] = {}
                    else
                        left = math.abs(left)
                        if left > defnum then
                            left = defnum
                        end
                        hint = string.format("进攻失败, 战损 %d, 击杀 %d", atknum, defnum - left)
                        mapData[tox][toy].number = left
                        mapData[fromx][fromy] = {}
                    end
                end
            else
                mapData[tox][toy] = {
                    party = mapData[fromx][fromy].party,
                    color = mapData[fromx][fromy].color,
                    number = mapData[fromx][fromy].number
                }
                mapData[fromx][fromy] = {}
                hint = nil
            end
        else
            tox = tox // 50 + 1
            toy = toy // 50 + 1
            if mapData[tox][toy].party then
                hint = string.format("selected %d, %d", tox, toy)
                print(hint)
                selected = table.pack(tox, toy)
            end
        end
    end

    rnd:clear()
    drawMap()
    drawHint()
    rnd:update()
    collectgarbage("collect")

    ::loopend::
end
