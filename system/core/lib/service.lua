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

-- handlers
local shutdownHandlers = {}
function service.addShutdownHandler(func)
    shutdownHandlers[func] = true
end
function service.delShutdownHandler(func)
    shutdownHandlers[func] = nil
end

-- process
local rawShutdown = computer.shutdown
local function shutdownProcess(mode)
    -- shutdown all process
    event.push("shutdown")
    os.sleep(0.1)

    -- run shutdown handlers
    local logs = require("logs")
    for handler in pairs(shutdownHandlers) do
        logs.assert(handler())
    end
    os.sleep(0.1)

    -- real shutdown
    rawShutdown(mode)
end

-- hook
local shutdownState
function computer.shutdown(mode)
    local thread = package.get("thread")

    if shutdownState then
        if thread then
            local current = thread.current()
            if current then pcall(current.kill, current) end --kill self thread
        end
        return
    end
    shutdownState = true
    
    if thread then
        thread.createBackground(shutdownProcess, mode):resume()
        local current = thread.current()
        if current then pcall(current.kill, current) end --kill self thread
    else
        shutdownProcess(mode)
    end
    event.wait()
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