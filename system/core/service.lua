local computer = require("computer")
local component = require("component")
local paths = require("paths")
local event = require("event")
local fs = require("filesystem")
local cache = require("cache")
local package = require("package")
local service = {}

------ auto-unload
local oldFree
service.unloadTimer = event.timer(2, function()
    --check RAM
    local free = computer.freeMemory()
    if not oldFree or free > oldFree then --проверка сборшика мусора
        if free < computer.totalMemory() / 5 then
            require("system").setUnloadState(true)
            cache.clearCache()
        else
            require("system").setUnloadState(false)
        end
    end
    oldFree = free
end, math.huge)

------ auto-mounting
event.hyperListen(function (eventType, componentUuid, componentType)
    if componentType == "filesystem" then
        local path = paths.concat("/mnt", componentUuid)
        if eventType == "component_added" then
            fs.mount(component.proxy(componentUuid), path)
        elseif eventType == "component_removed" then
            fs.umount(path)
        end
    end
end)

------ shutdown processing
local shutdownHandlers = {}
function service.addShutdownHandler(func)
    shutdownHandlers[func] = true
end
function service.delShutdownHandler(func)
    shutdownHandlers[func] = nil
end

local shutdown = computer.shutdown
local function shutdownProcess(mode)
    computer.shutdown(mode)
end
function computer.shutdown(mode)
    local thread = package.get("thread")
    if thread then
        local current = thread.current()
        if current then pcall(current.kill, current) end --kill self thread
        thread.createBackground(shutdownProcess):resume()
    else
        shutdownProcess(mode)
    end
end

------ registrations

service.addShutdownHandler(function ()
    local vcomponent = require("vcomponent")
    local gpu = component.getReal("gpu", true)

    for screen in component.list("screen") do
        if not vcomponent.isVirtual(screen) then
            if gpu.getScreen() ~= screen then gpu.bind(screen, false) end
            if gpu.setActiveBuffer then gpu.setActiveBuffer(0) end
            gpu.setDepth(1)
            gpu.setBackground(0)
            gpu.setForeground(0xFFFFFF)
            gpu.setResolution(50, 16)
            gpu.fill(1, 1, 50, 16, " ")
        end
    end
end)

return service