local unicode = require("unicode")
local graphic = require("graphic")
local vgpu = {}

local pairs = pairs
local floor = math.floor
local concat = table.concat
local huge = math.huge

local unicode_len = unicode.len
local unicode_sub = unicode.sub

local gradients = {"░", "▒", "▓"}
local function formatColor(gpu, back, backPal, fore, forePal, text, noPalIndex)
    local depth = gpu.getDepth()
    if not graphic.colorAutoFormat or depth > 1 then
        return back, backPal, fore, forePal, text
    end

    local function getGradient(col, pal)
        if pal and col >= 0 and col <= 15 then
            col = gpu.getPaletteColor(col)
        end
        
        local r, g, b = colors.unBlend(col or 0x000000)
        local step = math.round(255 / #gradients)
        local val = ((r + g + b) / 3)
        local index = 1
        for i = 0, 255, step do
            if i > val then
                return gradients[math.min(index - 1, #gradients)]
            end
            index = index + 1
        end
        return gradients[#gradients]
    end

    local function formatCol(col, pal)
        if depth == 1 then
            if pal and col >= 0 and col <= 15 then
                col = gpu.getPaletteColor(col)
            end

            if col == 0x000000 then
                return 0x000000
            elseif col == 0xffffff then
                return 0xffffff
            end
        else
            return col, pal
        end
    end

    local oldEquals = back == fore
    local newBack, newBackPal = formatCol(back, backPal)
    local newFore, newForePal = formatCol(fore, forePal)
    local gradient, gradientEmpty = nil, true

    if not newBack then
        newBack = 0x000000
        gradient = getGradient(back, backPal)
        local buff = {}
        local buffI = 1
        for i = 1, unicode.len(text) do
            local char = unicode.sub(text, i, i)
            if char == " " then
                buff[buffI] = gradient
            else
                buff[buffI] = char
                gradientEmpty = false
            end
            buffI = buffI + 1
        end
        text = table.concat(buff)
    end

    if not newFore then
        newFore = 0xffffff
    end

    if depth == 1 then
        if not oldEquals and newBack == newFore then
            if gradient and gradientEmpty then
                newBack = 0x000000
                newFore = 0xffffff
            else
                if newFore == 0 then
                    newBack = 0xffffff
                else
                    newFore = 0
                end
            end
        end
    elseif noPalIndex then
        if newBackPal then
            if newBack >= 0 and newBack <= 15 then
                newBack = gpu.getPaletteColor(newBack)
            end
            newBackPal = false
        end

        if newForePal then
            if newFore >= 0 and newFore <= 15 then
                newFore = gpu.getPaletteColor(newFore)
            end
            newForePal = false
        end
    end

    return newBack, newBackPal, newFore, newForePal, text
end

function vgpu.create(gpu, screen)
    local obj = {}

    local getScreen = gpu.getScreen
    local bind = gpu.bind
    local setActiveBuffer = gpu.setActiveBuffer
    local getActiveBuffer = gpu.getActiveBuffer
    local getResolution = gpu.getResolution
    local getBackground = gpu.getBackground
    local getForeground = gpu.getForeground
    local setBackground = gpu.setBackground
    local setForeground = gpu.setForeground
    local getPaletteColor = gpu.getPaletteColor
    local setPaletteColor = gpu.setPaletteColor
    local setResolution = gpu.setResolution
    local copy = gpu.copy
    local set = gpu.set
    
    local function init()
        if getScreen() ~= screen then
            bind(screen, false)
        end
        if setActiveBuffer and getActiveBuffer() ~= 0 then
            setActiveBuffer(0)
        end
    end
    init()

    local updated = false
    local forceUpdate = true

    local currentBackgrounds = {}
    local currentForegrounds = {}
    local currentChars = {}

    local backgrounds = {}
    local foregrounds = {}
    local chars = {}

    local allBackground = 0
    local allForeground = 0xffffff
    local allChar = " "

    local currentBack, currentBackPal = getBackground()
    local currentFore, currentForePal = getForeground()
    local origCurrentBack, origCurrentFore = currentBack, currentFore

    local rx, ry = getResolution()
    local rsmax = (rx - 1) + ((ry - 1) * rx)

    for key, value in pairs(gpu) do
        obj[key] = value
    end



    local vpal = {}
    local depth = gpu.getDepth()

    function obj.setDepth(d)
        local out = gpu.setDepth(d)
        depth = d
        if d > 1 then
            for i = 0, 15 do
                vpal[i] = getPaletteColor(i)
            end
        else
            for i = 0, 15 do
                vpal[i] = 0
            end
        end
        return out
    end
    obj.setDepth(depth)

    function obj.getDepth()
        return depth
    end

    function obj.getPaletteColor(i)
        return vpal[i]
    end

    function obj.setPaletteColor(i, v)
        local out
        if depth > 1 then
            out = setPaletteColor(i, v)
        else
            out = vpal[i]
        end
        vpal[i] = v
        return out
    end



    function obj.getBackground()
        return origCurrentBack, currentBackPal
    end

    function obj.getForeground()
        return origCurrentFore, currentForePal
    end

    local old, oldPal
    function obj.setBackground(col, isPal)
        --checkArg(1, col, "number")
        --checkArg(2, isPal, "boolean", "nil")

        old = currentBack
        oldPal = currentBackPal
        if isPal then
            currentBack = vpal[col]
        else
            currentBack = col
        end
        origCurrentBack = col
        currentBackPal = not not isPal
        return old, oldPal
    end

    function obj.setForeground(col, isPal)
        --checkArg(1, col, "number")
        --checkArg(2, isPal, "boolean", "nil")
        
        old = currentFore
        oldPal = currentForePal
        if isPal then
            currentFore = vpal[col]
        else
            currentFore = col
        end
        origCurrentFore = col
        currentForePal = not not isPal
        return old, oldPal
    end

    function obj.getResolution()
        return rx, ry
    end

    function obj.setResolution(x, y)
        x = floor(x)
        y = floor(y)

        init()
        setResolution(x, y)

        rx, ry = x, y
        rsmax = (rx - 1) + ((ry - 1) * rx)
        
        for i = 0, rsmax do
            if not backgrounds[i] then
                backgrounds[i] = 0
                foregrounds[i] = 0xffffff
                chars[i] = " "
            end
        end
        for i = rsmax + 1, huge do
            if backgrounds[i] then
                backgrounds[i] = nil
                foregrounds[i] = nil
                chars[i] = nil
            else
                break
            end
        end
    end

    local index
    function obj.get(x, y)
        x = floor(x)
        y = floor(y)

        index = (x - 1) + ((y - 1) * rx)
        return chars[index] or allChar, foregrounds[index] or allForeground, backgrounds[index] or allBackground
    end

    function obj.set(x, y, text, vertical)
        local currentBack, _, currentFore, _, text = formatColor(obj, currentBack, currentBackPal, currentFore, currentForePal, text, true)
        x = floor(x)
        y = floor(y)

        if vertical then
            for i = 1, unicode_len(text) do
                if y + (i - 1) > ry then break end
                index = ((x - 1) * rx) + ((y + (i - 1)) - 1)
                backgrounds[index] = currentBack
                foregrounds[index] = currentFore
                chars[index] = unicode_sub(text, i, i)
            end
        else
            for i = 1, unicode_len(text) do
                if x + (i - 1) > rx then break end
                index = ((x + (i - 1)) - 1) + ((y - 1) * rx)
                backgrounds[index] = currentBack
                foregrounds[index] = currentFore
                chars[index] = unicode_sub(text, i, i)
            end
        end

        updated = true
    end

    function obj.fill(x, y, sizeX, sizeY, char)
        local currentBack, _, currentFore, _, char = formatColor(obj, currentBack, currentBackPal, currentFore, currentForePal, char, true)
        x = floor(x)
        y = floor(y)
        sizeX = floor(sizeX)
        sizeY = floor(sizeY)

        if x == 1 and y == 1 and sizeX == rx and sizeY == ry then
            allBackground = currentBack
            allForeground = currentFore
            allChar = char

            backgrounds = {}
            foregrounds = {}
            chars = {}
        else
            for ix = x, x + (sizeX - 1) do
                if ix > rx then break end
                for iy = y, y + (sizeY - 1) do
                    if iy > ry then break end
                    index = (ix - 1) + ((iy - 1) * rx)
                    backgrounds[index] = currentBack
                    foregrounds[index] = currentFore
                    chars[index] = char
                end
            end
        end
        

        updated = true
    end

    local newB, newF, newC, index, newindex
    function obj.copy(x, y, sx, sy, ox, oy)
        x = floor(x)
        y = floor(y)
        sx = floor(sx)
        sy = floor(sy)
        ox = floor(ox)
        oy = floor(oy)

        --обновляем картинку на экране
        if updated then
            obj.update()
        else
            init()
        end

        --фактически копируем картинку
        copy(x, y, sx, sy, ox, oy)

        --капируем картинку в буфере
        newB, newF, newC = {}, {}, {}
        --local newBP, newFP = {}, {}
        for ix = x, x + (sx - 1) do 
            for iy = y, y + (sy - 1) do
                index = (ix - 1) + ((iy - 1) * rx)
                newindex = ((ix + ox) - 1) + (((iy + oy) - 1) * rx)

                newB[newindex] = backgrounds[index] or allBackground
                newF[newindex] = foregrounds[index] or allForeground
                newC[newindex] = chars[index] or allChar
            end
        end

        for newindex in pairs(newC) do
            backgrounds[newindex] = newB[newindex]
            foregrounds[newindex] = newF[newindex]
            chars[newindex] = newC[newindex]
            
            currentBackgrounds[newindex] = newB[newindex] --чтобы это не требовалось перерисовывать(так как этот метод применяет изображения сразу)
            currentForegrounds[newindex] = newF[newindex]
            currentChars[newindex] = newC[newindex]
        end
    end

    local oldBg, oldFg
    function obj.update()
        if updated then
            init()

            local index, buff, buffI, back, fore
            local i = 0
            local pixels = {}
            while i <= rsmax do
                if forceUpdate or (backgrounds[i] or allBackground) ~= currentBackgrounds[i] or
                    (foregrounds[i] or allForeground) ~= currentForegrounds[i] or
                    (chars[i] or allChar) ~= currentChars[i] or
                    (i + 1) % rx == 0 then
                    
                    back = backgrounds[i] or allBackground
                    fore = foregrounds[i] or allForeground

                    buff = {}
                    buffI = 1
                    index = i
                    while true do
                        buff[buffI] = chars[i] or allChar
                        buffI = buffI + 1
                        if back == (backgrounds[i + 1] or allBackground) and fore == (foregrounds[i + 1] or allForeground) and (i + 1) % rx ~= 0 then
                            currentBackgrounds[i] = backgrounds[i] or allBackground
                            currentForegrounds[i] = foregrounds[i] or allForeground
                            currentChars[i] = chars[i] or allChar
                            i = i + 1
                        else
                            break
                        end
                    end

                    --[[
                    if back ~= oldBg then
                        setBackground(back)
                        oldBg = back
                    end
                    if fore ~= oldFg then
                        setForeground(fore)
                        oldFg = fore
                    end
                    set((index % rx) + 1, (index // rx) + 1, concat(buff))
                    ]]

                    pixels[back] = pixels[back] or {}
                    pixels[back][fore] = pixels[back][fore] or {}
                    pixels[back][fore][index] = concat(buff)
                end

                currentBackgrounds[i] = backgrounds[i] or allBackground
                currentForegrounds[i] = foregrounds[i] or allForeground
                currentChars[i] = chars[i] or allChar
                i = i + 1
            end

            for bg, fgs in pairs(pixels) do
                if bg ~= oldBg then
                    setBackground(bg)
                    oldBg = bg
                end
                for fg, sets in pairs(fgs) do
                    if fg ~= oldFg then
                        setForeground(fg)
                        oldFg = fg
                    end

                    for idx, text in pairs(sets) do
                        set((idx % rx) + 1, (idx // rx) + 1, text)
                    end
                end
            end

            updated = false
            forceUpdate = false
        end
    end

    return obj
end

function vgpu.createStub(gpu)
    local obj = {}
    for key, value in pairs(gpu) do
        obj[key] = value
    end

    local back, backPal = gpu.getBackground()
    local fore, forePal = gpu.getForeground()
    local bgUpdated, fgUpdated = false, false

    local vpal = {}
    local depth = gpu.getDepth()

    function obj.setDepth(d)
        local out = gpu.setDepth(d)
        depth = d
        if d > 1 then
            for i = 0, 15 do
                vpal[i] = gpu.getPaletteColor(i)
            end
        else
            for i = 0, 15 do
                vpal[i] = 0
            end
        end
        return out
    end
    obj.setDepth(depth)

    function obj.getDepth()
        return depth
    end

    function obj.getPaletteColor(i)
        return vpal[i]
    end

    function obj.setPaletteColor(i, v)
        local out
        if depth > 1 then
            out = gpu.setPaletteColor(i, v)
        else
            out = vpal[i]
        end
        vpal[i] = v
        return out
    end




    function obj.getBackground()
        return back, backPal
    end

    function obj.getForeground()
        return fore, forePal
    end

    function obj.setBackground(col, pal)
        bgUpdated = true
        local old, oldPal = fore, forePal
        back, backPal = col, pal
        return old, oldPal
    end

    function obj.setForeground(col, pal)
        fgUpdated = true
        local old, oldPal = fore, forePal
        fore, forePal = col, pal
        return old, oldPal
    end


    local function formatPal(col, isPal)
        if depth == 1 and isPal then
            return vpal[col] or 0
        end
        return col, isPal
    end

    function obj.set(x, y, text, vertical)
        local newBack, newBackPal, newFore, newForePal, text = formatColor(obj, back, backPal, fore, forePal, text)
        newBack, newBackPal = formatPal(newBack, newBackPal)
        newFore, newForePal = formatPal(newFore, newForePal)

        if fgUpdated then
            gpu.setForeground(newFore, newForePal)            
            fgUpdated = false
        end
        if bgUpdated then
            gpu.setBackground(newBack, newBackPal)
            bgUpdated = false
        end
        gpu.set(x, y, text, vertical)
    end

    function obj.fill(x, y, sx, sy, char)
        local newBack, newBackPal, newFore, newForePal, char = formatColor(obj, back, backPal, fore, forePal, char)
        newBack, newBackPal = formatPal(newBack, newBackPal)
        newFore, newForePal = formatPal(newFore, newForePal)

        if fgUpdated then
            gpu.setForeground(newFore, newForePal)            
            fgUpdated = false
        end
        if bgUpdated then
            gpu.setBackground(newBack, newBackPal)
            bgUpdated = false
        end
        gpu.fill(x, y, sx, sy, char)
    end

    return obj
end

vgpu.unloadable = true
return vgpu