local graphic = require("graphic")
local component = require("component")
local event = require("event")

------------------------------------

local screen = component.list("screen")()
local gpu = graphic.findGpu(screen)
local rx, ry = gpu.getResolution()

local mainWindow = graphic.classWindow:new(screen, 1, 2, rx, ry - 1)
local statusWindow = graphic.classWindow:new(screen, 1, 1, rx, 1)
local appMenu = graphic.classWindow:new(screen, 2, 3, 40, 20)

local appMenuOpen = false
local appMenuScroll = 0
local appMenuMaxScroll = 1

local function draw()
    mainWindow:clear(0x00AAFF)
    mainWindow:set(1, 1, 0x0000FF, 0xFFFFFF, "open")

    statusWindow:clear(0xAAAAAA)
    statusWindow:set(1, 1, 0xAAAAAA, 0xFFFFFF, "12:00")

    if appMenuOpen then
        appMenu:clear(0xAAAAAA)
        appMenu:set(1, 1, 0xFFFFFF, 0, string.rep("-", appMenu.sizeX))
        appMenu:set(1, 2, 0xFF0000, 0xFFFFFF, "close")
    end
end
draw()

while true do
    local eventData = {event.pull()}

    local mainWindowEventData = mainWindow:uploadEvent(eventData)
    local statusWindowEventData = statusWindow:uploadEvent(eventData)
    local appMenuWindowEventData = {}
    if appMenuWindowEventData then
        appMenuWindowEventData = appMenu:uploadEvent(eventData)
    end

    if mainWindowEventData[1] == "touch" then
        if mainWindowEventData[4] == 1 and mainWindowEventData[3] >= 1 and mainWindowEventData[3] <= 4 then
            appMenuOpen = true
            draw()
        end
    end
    
    if appMenuWindowEventData[1] == "touch" then
        if appMenuWindowEventData[4] == 2 and appMenuWindowEventData[3] >= 1 and appMenuWindowEventData[3] <= 5 then
            appMenuOpen = false
            draw()
        end
    elseif appMenuWindowEventData[1] == "scroll" then
        appMenuScroll = appMenuScroll + appMenuWindowEventData[5]
        if appMenuScroll < 0 then appMenuScroll = 0 end
        if appMenuScroll > appMenuMaxScroll then appMenuScroll = appMenuMaxScroll end
    end
end