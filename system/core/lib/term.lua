local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local calls = require("calls")

------------------------------------

local term = {}

------------------------------------class window

local window = {}
window.__index = window

function window:new(screen, x, y, sizeX, sizeY)
    local obj = {
        screen = screen,
        x = x,
        y = y,
        sizeX = sizeX,
        sizeY = sizeY,
        cursorX = 1,
        cursorY = 1,
    }

    setmetatable(obj, self)
    return obj
end

function window:set(x, y, background, foreground, text)
    local gpu = term.findGpu(self.screen)
    if gpu then
        gpu.setBackground(background)
        gpu.setForeground(foreground)
        gpu.set(self.x + (x - 1), self.y + (y - 1), text)
    end
end

function window:fill(x, y, sizeX, sizeY, background, foreground, char)
    local gpu = term.findGpu(self.screen)
    if gpu then
        gpu.setBackground(background)
        gpu.setForeground(foreground)
        gpu.fill(self.x + (x - 1), self.y + (y - 1), sizeX, sizeY, char)
    end
end

function window:copy(x, y, sizeX, sizeY, offsetX, offsetY)
    local gpu = term.findGpu(self.screen)
    if gpu then
        gpu.copy(self.x + (x - 1), self.y + (y - 1), sizeX, sizeY, offsetX, offsetY)
    end
end

function window:clear(color)
    self:fill(1, 1, self.sizeX, self.sizeY, color, 0, " ")
end

function window:setCursor(x, y)
    self.x, self.y = x, y
end

function window:getCursor()
    return self.x, self.y
end

function window:write(data, background, foreground)
    local gpu = term.findGpu(self.screen)
    if gpu then
        gpu.setBackground(background or 0)
        gpu.setForeground(foreground or 0xFFFFFF)

        for i = 1, unicode.len(data) do
            local char = unicode.sub(data, i, i)
            if char == "\n" then
                self.cursorY = self.cursorY + 1
                self.cursorX = 1
            else
                gpu.set(self.x + (self.cursorX - 1), self.y + (self.cursorY - 1), char)
                self.cursorX = self.cursorX + 1
            end
        end
    end
end

function window:read(x, y, sizeX, background, foreground)
    local gpu = term.findGpu(self.screen)
    local keyboards = component.invoke(self.screen, "getKeyboards")
    return function(...)
        --вызывайте функцию и передавайте туда эвенты которые сами читаете, 
        --если функция чтото вернет, это результат, если он TRUE(не false) значет было нажато ctrl+c
        local eventData = {...}
        local buffer = ""
        local function redraw()
            if gpu then
                gpu.setBackground(background)
                gpu.setForeground(foreground)
                local str = buffer .. "_"
                local num = (unicode.len(buffer) - sizeX) + 1
                if num < 1 then num = 1 end
                str = unicode.sub(buffer, num, unicode.len(buffer))
                if unicode.len(str) < sizeX then
                    str = str .. string.rep(" ", sizeX - unicode.len(str))
                end
                gpu.set(x, y, str)
            end
        end
        if eventData[1] == "key_down" then
            local ok
            for i, v in ipairs(keyboards) do
                if eventData[2] == v then
                    ok = true
                    break
                end
            end
            if ok then
                if eventData[4] == 28 then
                    return buffer
                elseif eventData[3] >= 32 and eventData[3] <= 126 then
                    buffer = buffer .. string.char(eventData[3])
                    redraw()
                elseif eventData[4] == 14 then
                    if #buffer > 0 then
                        buffer = buffer:sub(1, #buffer - 1)
                        redraw()
                    end
                elseif eventData[4] == 46 then
                    return true --exit ctrl + c
                end
            end
        end
    end
end

term.classWindow = window

------------------------------------

function term.findGpu(screen)
    local deviceinfo = computer.getDeviceInfo()
    local screenLevel = tonumber(deviceinfo[screen].capacity) or 0

    local bestGpuLevel, gpuLevel, bestGpu = 0
    for address in component.list("gpu") do
        gpuLevel = tonumber(deviceinfo[address].capacity) or 0
        if gpuLevel == screenLevel then
            gpuLevel = gpuLevel + 1000
        elseif gpuLevel > screenLevel then
            gpuLevel = gpuLevel + 800
        end
        if gpuLevel > bestGpuLevel then
            bestGpuLevel = gpuLevel
            bestGpu = address
        end
    end
    
    if bestGpu then
        local gpu = component.proxy(bestGpu)
        if gpu.getScreen() ~= screen then
            gpu.bind(screen, false)
        end
        return gpu
    end
end

return term