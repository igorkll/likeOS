local computer = require("computer")
local component = require("component")
local paths = require("paths")
local event = require("event")
local fs = require("filesystem")
local cache = require("cache")
local service = {}

local oldFree
service.unloadTimer = event.timer(2, function()
    --check RAM
    local free = computer.freeMemory()
    if not oldFree or free > oldFree then --проверка сборшика мусора
        if free < computer.totalMemory() / 3 then
            require("system").setUnloadState(true)
            cache.clearCache()
        else
            require("system").setUnloadState(false)
        end
    end
    oldFree = free
end, math.huge)

event.hyperListen(function (eventType, componentUuid, componentType)
    if fs.autoMount and componentType == "filesystem" then
        local path = paths.concat("/mnt", componentUuid)
        if eventType == "component_added" then
            fs.mount(component.proxy(componentUuid), path)
        elseif eventType == "component_removed" then
            fs.umount(path)
        end
    end
end)

return service