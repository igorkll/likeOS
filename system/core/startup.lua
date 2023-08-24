------------------------------------base init

local component, computer, unicode = component, computer, unicode
_G._COREVERSION = "likeOS v1.5"

local bootaddress = computer.getBootAddress()
local bootfs = component.proxy(bootaddress)

------------------------------------background

do
    local shutdown = computer.shutdown
    function computer.shutdown(reboot)
        if sendTelemetry then
            pcall(sendTelemetry, "power off", (reboot and "reboot" or "shutdown"))
        end
        return shutdown(reboot)
    end
end

------------------------------------base funcs

local function getFile(fs, path)
    local file, err = fs.open(path, "rb")
    if not file then return nil, err end

    local buffer = ""
    repeat
        local data = fs.read(file, math.huge)
        buffer = buffer .. (data or "")
    until not data
    fs.close(file)

    return buffer
end

local function saveFile(fs, path, data)
    local file, err = fs.open(path, "wb")
    if not file then return nil, err end

    fs.write(file, data)
    fs.close(file)

    return true
end

local function raw_loadfile(path, mode, env)
    local data, err = getFile(bootfs, path)
    if not data then return nil, err end
    return load(data, "=" .. path, mode or "bt", env or _G)
end

------------------------------------registry

local registry = {}

do
    local registryPath = "/data/registry.dat"

    local mainRegistryPath
    if bootfs.exists("/vendor/registry.dat") then
        mainRegistryPath = "/vendor/registry.dat"
    elseif bootfs.exists("/system/registry.dat") then
        mainRegistryPath = "/system/registry.dat"
    elseif bootfs.exists("/system/core/registry.dat") then
        mainRegistryPath = "/system/core/registry.dat"
    end

    if mainRegistryPath and bootfs.exists(mainRegistryPath) and not bootfs.exists(registryPath) then
        bootfs.makeDirectory("/data")
        saveFile(bootfs, registryPath, getFile(bootfs, mainRegistryPath))
    end

    if bootfs.exists(registryPath) then
        local file = bootfs.open(registryPath, "rb")
        if file then
            local buffer = ""
            repeat
                local data = bootfs.read(file, math.huge)
                buffer = buffer .. (data or "")
            until not data
            bootfs.close(file)

            local code = load("return " .. buffer)
            if code then
                local result = {pcall(code)}
                if result[1] and type(result[2]) == "table" then
                    registry = result[2]
                end
            end
        end
    end
end

------------------------------------functions

local function initScreen(gpu, screen)
    if gpu.setActiveBuffer and gpu.getActiveBuffer() ~= 0 then
        gpu.setActiveBuffer(0)
    end
    if gpu.getScreen() ~= screen then
        gpu.bind(screen, false)
    end
    gpu.setDepth(1)
    gpu.setDepth(gpu.maxDepth())
    gpu.setResolution(50, 16)
    gpu.setBackground(0)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, 50, 16, " ")
end

do
    local gpu = component.proxy(component.list("gpu")() or "")
    if gpu then
        for screen in component.list("screen") do
            initScreen(gpu, screen)
        end
    end

    local logoPath
    if bootfs.exists("/data/logo.lua") then
        logoPath = "/data/logo.lua"
    elseif bootfs.exists("/vendor/logo.lua") then
        logoPath = "/vendor/logo.lua"
    elseif bootfs.exists("/system/logo.lua") then
        logoPath = "/system/logo.lua"
    elseif bootfs.exists("/system/core/logo.lua") then
        logoPath = "/system/core/logo.lua"
    end

    local logoenv = {gpu = gpu, unicode = unicode, computer = computer, component = component}
    local logo = raw_loadfile(logoPath, nil, setmetatable(logoenv, {__index = _G}))
    
    function printText(text)
        if registry.disableLogo or not logo or not gpu then return end
        logoenv.text = text
        for screen in component.list("screen") do
            initScreen(gpu, screen)
            logo()
        end
    end

    function waitEnter()
        if registry.disableLogo or not logo or not gpu then return end
        while true do
            local eventData = {computer.pullSignal()}
            if eventData[1] == "key_down" then
                if eventData[4] == 28 then
                    return
                end
            end
        end
    end
end

------------------------------------recovery menu

if not registry.disableRecovery then
    printText("Press R to open recovery menu")

    local gpu = component.proxy(component.list("gpu")() or "")

    if gpu and component.list("screen")() then
        local recoveryScreen
        for i = 1, 10 do
            local eventData = {computer.pullSignal(0.1)}
            if eventData[1] == "key_down" and eventData[4] == 19 then
                for address in component.list("screen") do
                    local keyboards = component.invoke(address, "getKeyboards")
                    for i, keyboard in ipairs(keyboards) do
                        if keyboard == eventData[2] then
                            recoveryScreen = address
                            goto exit
                        end
                    end
                end
            end
        end
        ::exit::

        if recoveryScreen then
            printText("RECOVERY MOD")
            initScreen(gpu, recoveryScreen)

            local recoveryPath
            if bootfs.exists("/data/recovery.lua") then
                recoveryPath = "/data/recovery.lua"
            elseif bootfs.exists("/vendor/recovery.lua") then
                recoveryPath = "/vendor/recovery.lua"
            elseif bootfs.exists("/system/recovery.lua") then
                recoveryPath = "/system/recovery.lua"
            elseif bootfs.exists("/system/core/recovery.lua") then
                recoveryPath = "/system/core/recovery.lua"
            end

            if recoveryPath then
                assert(xpcall(raw_loadfile(recoveryPath), debug.traceback, gpu, bootfs))
            else
                printText("failed to open recovery. press enter to continue")
                waitEnter()
            end
        end
    end
end

------------------------------------main init

printText("Booting...")

------------------------------------check error

local ok, err = xpcall(function()
    local code, err = raw_loadfile("/system/core/boot.lua")
    if not code then
        error("err to load bootloader " .. (err or "unknown error"), 0)
    end

    code(raw_loadfile)
end, debug.traceback)

if not err then
    err = "unknown"
end

pcall(sendTelemetry, "globalError", err)

------------------------------------log error

if require and pcall then
    local function local_require(name)
        local result = {pcall(require, name)}
        if result[1] and type(result[2]) == "table" then
            return result[2]
        end
    end
    local event = local_require("event")
    if event and event.errLog then
        pcall(event.errLog, "global error: " .. err)
    end
end

------------------------------------error output

computer.shutdown(true)
--error(err, 0)