local natives = require("natives")
local computer = require("computer")
local package = require("package")
local cache = require("cache")
local event = require("event")
local lastinfo = require("lastinfo")
local component = require("component")
local fs = require("filesystem")
local paths = require("paths")
local calls = require("calls")
local system = {}

-------------------------------------------------

function system.stub()
end

function system.getSelfScriptPath()
    for runLevel = 0, math.huge do
        local info = debug.getinfo(runLevel)

        if info then
            if info.what == "main" then
                return info.source:sub(2, -1)
            end
        else
            error("Failed to get debug info for runlevel " .. runLevel)
        end
    end
end

function system.getDeviceType()
    local function isType(ctype)
        return natives.component.list(ctype)() and ctype
    end
    
    local function isServer()
        local obj = lastinfo.deviceinfo[computer.address()]
        if obj and obj.description and obj.description:lower() == "server" then
            return "server"
        end
    end
    
    return isType("tablet") or isType("microcontroller") or isType("drone") or isType("robot") or isServer() or isType("computer") or "unknown"
end

function system.getCpuLevel()
    local processor = -1

    for _, value in pairs(lastinfo.deviceinfo) do
        if value.class == "processor" then
            if value.clock == "1500" or value.clock == "1000+1280/1280/160/2560/640/1280" or value.clock == "1500+2560/2560/320/5120/1280/2560" then
                processor = 3
                break
            elseif value.clock == "1000" or value.clock == "500+640/640/40/1280/320/640" then
                processor = 2
                break
            elseif value.clock == "500" then
                processor = 1
                break
            end
        end
    end

    return processor
end

function system.getCurrentComponentCount()
    local count = 0
    for _, ctype in natives.component.list() do
        if ctype == "filesystem" then --файловые системы жрут 0.25 бюджета компанентов, и их можно подключить в читыри раза больше чем других компанентов
            count = count + 0.25
        else
            count = count + 1
        end
    end
    return count - 1 --свой комп не учитываеться в opencomputers
end

function system.getMaxComponentCount() --пока что не учитывает компанентные шины, так как они не детектяться в getDeviceInfo
    local cpu = system.getCpuLevel()
    if cpu == 1 then
        return 8
    elseif cpu == 2 then
        return 12
    elseif cpu == 3 then
        return 16
    else
        return -1
    end
end

function system.getDiskLevel(address) --fdd, tier1, tier2, tier3, raid, tmp, unknown
    local info = lastinfo.deviceinfo[address]
    local clock = info and info.clock

    if address == computer.tmpAddress() then
        return "tmp"
    elseif clock == "20/20/20" then
        return "fdd"
    elseif clock == "300/300/120" then
        return "raid"
    elseif clock == "80/80/40" then
        return "tier1"
    elseif clock == "140/140/60" then
        return "tier2"
    elseif clock == "200/200/80" then
        return "tier3"
    else
        return "unknown"
    end
end

function system.isLikeOSDisk(address)
    local signature = "--likeOS core"

    local file = component.invoke(address, "open", "/init.lua", "rb")
    if file then
        local data = invoke(address, "read", file, #signature)
        component.invoke(address, "close", file)
        return signature == data
    end
    return false
end

function system.checkExitinfo(...)
    local result = {...}
    if not result[1] and type(result[2]) == "table" and result[2].reason == "interrupted" then
        if result[2].code == 0 then
            return true
        else
            return false, "terminated with exit-code: " .. tostring(result[2].code)
        end
    end
    return table.unpack(result)
end

function system.getCharge()
    return math.clamp(math.round(math.map(computer.energy(), 0, computer.maxEnergy(), 0, 100)), 0, 100)
end

-------------------------------------------------

local function cacheMode(tbl, state)
    local mt = getmetatable(tbl)
    if mt then
        if state then
            mt.__mode = 'v'
        else
            mt.__mode = nil
        end
    else
        mt = {}
        if state then
            mt.__mode = 'v'
        end
        setmetatable(tbl, mt)
    end
end

local currentUnloadState
function system.setUnloadState(state)
    checkArg(1, state, "boolean")
    if currentUnloadState == state then return end
    currentUnloadState = state

    cacheMode(package.libStubsCache, state)
    cacheMode(package.cache, state)
    cacheMode(calls.cache, state)
end
system.setUnloadState(false)

local oldFree
system.timerId = event.timer(2, function()
    --check RAM
    local free = computer.freeMemory()
    if not oldFree or free > oldFree then --проверка сборшика мусора
        if free < computer.totalMemory() / 3 then
            system.setUnloadState(true)
            cache.clearCache()
        else
            system.setUnloadState(false)
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

return system