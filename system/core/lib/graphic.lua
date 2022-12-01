local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local event = require("event")
local calls = require("calls")
local colors = require("colors")

------------------------------------

local graphic = {}
graphic.unloaded = true
graphic.screensBuffers = {}
graphic.globalUpdated = false
graphic.updated = {}
graphic.allowBuffer = true
graphic.windows = setmetatable({}, {__mode == "v"})
graphic.inputHistory = {}
graphic.disableBuffers = {}

------------------------------------class window

local function set(self, x, y, background, foreground, text)
    graphic.update(self.screen)
    local gpu = graphic.findGpu(self.screen)
    if gpu then
        gpu.setBackground(background, self.isPal)
        gpu.setForeground(foreground, self.isPal)
        gpu.set(self.x + (x - 1), self.y + (y - 1), text)
    end
end

local function fill(self, x, y, sizeX, sizeY, background, foreground, char)
    graphic.update(self.screen)
    local gpu = graphic.findGpu(self.screen)
    if gpu then
        gpu.setBackground(background, self.isPal)
        gpu.setForeground(foreground, self.isPal)
        gpu.fill(self.x + (x - 1), self.y + (y - 1), sizeX, sizeY, char)
    end
end

local function copy(self, x, y, sizeX, sizeY, offsetX, offsetY)
    graphic.update(self.screen)
    local gpu = graphic.findGpu(self.screen)
    if gpu then
        gpu.copy(self.x + (x - 1), self.y + (y - 1), sizeX, sizeY, offsetX, offsetY)
    end
end

local function clear(self, color)
    self:fill(1, 1, self.sizeX, self.sizeY, color, 0, " ")
end

local function setCursor(self, x, y)
    self.cursorX, self.cursorY = x, y
end

local function getCursor(self)
    return self.cursorX, self.cursorY
end

local function write(self, data, background, foreground, autoln)
    graphic.update(self.screen)
    local gpu = graphic.findGpu(self.screen)

    if gpu then
        local buffer = ""
        local setX, setY = self.cursorX, self.cursorY
        local function applyBuffer()
            gpu.set(self.x + (setX - 1), self.y + (setY - 1), buffer)
            buffer = ""
            setX, setY = self.cursorX, self.cursorY
        end

        gpu.setBackground(background or (self.isPal and colors.black or 0), self.isPal)
        gpu.setForeground(foreground or (self.isPal and colors.white or 0xFFFFFF), self.isPal)

        for i = 1, unicode.len(data) do
            local char = unicode.sub(data, i, i)
            local ln = autoln and self.cursorX > self.sizeX
            local function setChar()
                --gpu.set(self.x + (self.cursorX - 1), self.y + (self.cursorY - 1), char)
                buffer = buffer .. char
                self.cursorX = self.cursorX + 1
            end
            if char == "\n" or ln then
                self.cursorY = self.cursorY + 1
                self.cursorX = 1
                applyBuffer()
                if ln then
                    setChar()
                end
            else
                setChar()
            end
        end

        applyBuffer()
    end
end

local function uploadEvent(self, eventData)
    local newEventData = {} --пустая таблица, чтобы не чекать на nil
    if eventData then
        if eventData[2] == self.screen and
        (eventData[1] == "touch" or eventData[1] == "drop" or eventData[1] == "drag" or eventData[1] == "scroll") then
            local oldSelected = self.selected
            local rePosX = (eventData[3] - self.x) + 1
            local rePosY = (eventData[4] - self.y) + 1
            self.selected = false
            if rePosX >= 1 and rePosY >= 1
            and rePosX <= self.sizeX and rePosY <= self.sizeY then
                self.selected = true
                newEventData = {eventData[1], eventData[2], rePosX, rePosY, eventData[5], eventData[6]}
            end
            if eventData[1] == "drop" then
                self.selected = oldSelected
            end
        elseif eventData[1] == "key_down" or eventData[1] == "key_up" or eventData[1] == "clipboard" then
            local ok
            for i, v in ipairs(component.invoke(self.screen, "getKeyboards")) do
                if eventData[2] == v then
                    ok = true
                    break
                end
            end
            if ok then
                newEventData = eventData
            end
        end
    end
    if self.selected then
        return newEventData
    end
    return {}
end

local function toRealPos(self, x, y)
    return self.x + (x - 1), self.y + (y - 1)
end

local function read(self, x, y, sizeX, background, foreground, preStr, crypto, buffer, clickCheck)
    local keyboards = component.invoke(self.screen, "getKeyboards")
    local buffer = buffer or ""
    local allowUse = not clickCheck
    local function redraw()
        graphic.update(self.screen)
        local gpu = graphic.findGpu(self.screen)

        if gpu then
            gpu.setBackground(background, self.isPal)
            gpu.setForeground(foreground, self.isPal)
            local newBuffer = buffer
            if crypto then
                newBuffer = string.rep("*", unicode.len(newBuffer))
            end
            
            local str = (preStr or "") .. newBuffer
            if allowUse and self.selected then
                str = str .. "_"
            end

            local num = (unicode.len(str) - sizeX) + 1
            if num < 1 then num = 1 end
            str = unicode.sub(str, num, unicode.len(str))

            if unicode.len(str) < sizeX then
                str = str .. string.rep(" ", sizeX - unicode.len(str))
            end

            gpu.set(self.x + (x - 1), self.y + (y - 1), str)
        end
    end
    redraw()

    return {uploadEvent = function(eventData)
        --вызывайте функцию и передавайте туда эвенты которые сами читаете, 
        --если функция чтото вернет, это результат, если он TRUE(не false) значет было нажато ctrl+c
        if allowUse then
            local ok
            for i, v in ipairs(keyboards) do
                if eventData[2] == v then
                    ok = true
                    break
                end
            end
            if ok and self.selected then
                if eventData[1] == "key_down" then
                    if eventData[4] == 28 then
                        table.insert(graphic.inputHistory, buffer)
                        while #graphic.inputHistory > 64 do
                            table.remove(graphic.inputHistory, 1)
                        end
                        return buffer
                    elseif eventData[4] == 14 then
                        if #buffer > 0 then
                            buffer = unicode.sub(buffer, 1, unicode.len(buffer) - 1)
                            redraw()
                        end
                    elseif eventData[3] == 3 and eventData[4] == 46 then
                        return true --exit ctrl + c
                    elseif eventData[3] > 0 then
                        buffer = buffer .. unicode.char(eventData[3])
                        redraw()
                    elseif eventData[3] == 200 then --up
                        
                    elseif eventData[3] == 208 then --down

                    end
                elseif eventData[1] == "clipboard" and not crypto then
                    buffer = buffer .. eventData[3]
                    redraw()
                    if buffer:byte(#buffer) == 13 then return buffer end
                end
            end
        end

        if clickCheck then
            if eventData[1] == "touch" and eventData[2] == self.screen and eventData[5] == 0 then
                if eventData[3] >= x and eventData[3] < x + sizeX and eventData[4] == y then
                    allowUse = true
                    redraw()
                else
                    allowUse = false
                    redraw()
                end
            end
        end
    end, redraw = redraw, getBuffer = function()
        return buffer
    end, setBuffer = function(v)
        buffer = v
    end, setAllowUse = function(state)
        allowUse = state
    end}
end

function graphic.createWindow(screen, x, y, sizeX, sizeY, selected, isPal)
    local obj = {
        screen = screen,
        x = x,
        y = y,
        sizeX = sizeX,
        sizeY = sizeY,
        cursorX = 1,
        cursorY = 1,

        read = read,
        toRealPos = toRealPos,
        set = set,
        fill = fill,
        copy = copy,
        clear = clear,
        uploadEvent = uploadEvent,
        write = write,
        getCursor = getCursor,
        setCursor = setCursor,
        isPal = isPal or false,
    }

    if selected ~= nil then
        obj.selected = selected
    else
        local gpu = graphic.findGpu(screen)
        obj.selected = gpu and gpu.getDepth() == 1
    end

    if obj.selected then
        for i, window in ipairs(graphic.windows) do
            window.selected = false
        end
    end

    table.insert(graphic.windows, obj)
    return obj
end

------------------------------------

graphic.gpuPrivateList = {} --для приватизации видеокарт, дабы избежать "кражи" другими процессами, добовляйте так graphic.gpuPrivateList[gpuAddress] = true

--local bindCache = {}
function graphic.findGpu(screen)
    --от кеша слишком много проблемм, а findGpu и так довольно быстрая, за счет оптимизированого getDeviceInfo
    --if bindCache[screen] and bindCache[screen].getScreen() == screen then return bindCache[screen] end
    local deviceinfo = computer.getDeviceInfo()
    local screenLevel = tonumber(deviceinfo[screen].capacity) or 0

    local bestGpuLevel, gpuLevel, bestGpu = 0
    local function check(deep)
        for address in component.list("gpu") do
            if not graphic.gpuPrivateList[address] and (deep or component.invoke(address, "getScreen") == screen) then
                gpuLevel = tonumber(deviceinfo[address].capacity) or 0
                if component.invoke(address, "getScreen") == screen and gpuLevel == screenLevel then --уже подключенная видео карта, казырный туз, но только если она того же уровня что и монитор!
                    gpuLevel = gpuLevel + 99999999999999999999
                elseif gpuLevel == screenLevel then
                    gpuLevel = gpuLevel + 999999999
                elseif gpuLevel > screenLevel then
                    gpuLevel = gpuLevel + 999999
                end
                if gpuLevel > bestGpuLevel then
                    bestGpuLevel = gpuLevel
                    bestGpu = address
                end
            end
        end
    end
    check()
    check(true)
    
    if bestGpu then
        local gpu = component.proxy(bestGpu)
        if gpu.getScreen() ~= screen then
            gpu.bind(screen, false)
        end
        --bindCache[screen] = gpu

        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            if not graphic.screensBuffers[screen] then
                gpu.setActiveBuffer(0)
                graphic.screensBuffers[screen] = gpu.allocateBuffer(gpu.getResolution())
            end

            gpu.setActiveBuffer(graphic.screensBuffers[screen])
        else
            if gpu.setActiveBuffer then
                gpu.setActiveBuffer(0)
            end
        end

        return gpu
    end
end

--[[
event.listen(nil, function(eventType, _, ctype)
    if (eventType == "component_added" or eventType == "component_removed") and (ctype == "filesystem" or ctype == "gpu") then
        bindCache = {} --да, тупо создаю новую табличьку
    end
end)
]]

do
    local gpu = component.proxy(component.list("gpu")() or "")

    if gpu and gpu.setActiveBuffer and graphic.allowBuffer then
        event.timer(0.05, function()
            if not graphic.allowBuffer then return end
            if graphic.globalUpdated then
                for address, ctype in component.list("screen") do
                    if graphic.isBufferAllow(address) then
                        if graphic.updated[address] then
                            graphic.updated[address] = nil
                            graphic.findGpu(address).bitblt()
                        end
                    end
                end
                graphic.globalUpdated = false
            end
        end, math.huge)
    end
end


function graphic.getResolution(screen)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.getResolution()
    end
end

function graphic.maxResolution(screen)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.maxResolution()
    end
end

function graphic.setResolution(screen, x, y)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            local activeBuffer = gpu.getActiveBuffer()

            local palette
            if gpu.getDepth() > 1 then
                palette = {}
                for i = 0, 15 do
                    table.insert(palette, graphic.getPaletteColor(screen, i) or 0)
                end
                gpu.setActiveBuffer(activeBuffer)
            end

            
            local newBuffer = gpu.allocateBuffer(x, y)
            if newBuffer then
                gpu.bitblt(newBuffer, nil, nil, nil, nil, activeBuffer)
                graphic.screensBuffers[screen] = newBuffer
                gpu.freeBuffer(activeBuffer)

                if palette then
                    gpu.setActiveBuffer(newBuffer)
                    for i, color in ipairs(palette) do
                        gpu.setPaletteColor(i - 1, color)
                    end
                    
                    gpu.setActiveBuffer(0)
                    for i, color in ipairs(palette) do
                        gpu.setPaletteColor(i - 1, color)
                    end
                else
                    gpu.setActiveBuffer(0)
                end
            else
                graphic.screensBuffers[screen] = nil
            end
        end
        return gpu.setResolution(x, y)
    end
end

function graphic.setPaletteColor(screen, i, v)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(graphic.screensBuffers[screen])
            gpu.setPaletteColor(i, v)
            gpu.setActiveBuffer(0)
        end
        return gpu.setPaletteColor(i, v)
    end
end

function graphic.getPaletteColor(screen, i)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.getPaletteColor(i)
    end
end

function graphic.getDepth(screen)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.getDepth()
    end
end

function graphic.setDepth(screen, v)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.setDepth(v)
    end
end

function graphic.maxDepth(screen)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.maxDepth()
    end
end

function graphic.getViewport(screen)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.getViewport()
    end
end

function graphic.setViewport(screen, x, y)
    local gpu = graphic.findGpu(screen)
    if gpu then
        if gpu.setActiveBuffer and graphic.isBufferAllow(screen) then
            gpu.setActiveBuffer(0)
        end
        return gpu.setViewport(x, y)
    end
end

function graphic.update(screen)
    graphic.globalUpdated = true
    graphic.updated[screen] = true
end

function graphic.setAllowBuffer(state)
    if not state then
        for address, ctype in component.list("gpu") do
            component.invoke(address, "setActiveBuffer", 0)
        end
    end
    graphic.allowBuffer = state
end

function graphic.isBufferAvailable()
    local gpu = component.proxy(component.list("gpu")() or "")
    if gpu then
        return not not gpu.setActiveBuffer
    end
    return false
end

function graphic.isBufferAllow(screen)
    return graphic.allowBuffer and not graphic.disableBuffers[screen]
end

function graphic.setBufferStateOnScreen(screen, state)
    graphic.disableBuffers[screen] = not state
    if not state then
        local gpu = graphic.findGpu(screen)
        if gpu then
            gpu.setActiveBuffer(0)
        end
    end
end

function graphic.getBufferStateOnScreen(screen)
    return not graphic.disableBuffers[screen]
end

return graphic