--likeOS classic bootloader

------------------------------------base init

local component, computer, unicode = component, computer, unicode
pcall(computer.setArchitecture, "Lua 5.3")

local pullSignal = computer.pullSignal
local shutdown = computer.shutdown
local error = error
local pcall = pcall

_G._COREVERSION = "likeOS-v1.8"
_G._OSVERSION = _G._COREVERSION --это перезаписываеться в дистрибутивах

local bootloader = {} --библиотека загрузчика
bootloader.firstEeprom = component.list("eeprom")() --хранит адрес eeprom с которого произошла загрузка
bootloader.tmpaddress = computer.tmpAddress()

bootloader.bootaddress = computer.getBootAddress()
bootloader.bootfs = component.proxy(bootloader.bootaddress)

bootloader.coreversion = _G._COREVERSION
bootloader.runlevel = "init"

function computer.runlevel()
    return bootloader.runlevel
end

------------------------------------ bootloader constants

bootloader.defaultShellPath = "/system/main.lua"

------------------------------------ base functions

function bootloader.yield() --катыльный способ вызвать прирывания дабы избежать краша(звук издаваться не будет так как функция завершаеться ошибкой из за переданого 0)
    pcall(computer.beep, 0)
end

function bootloader.createEnv() --создает _ENV для программы, где _ENV будет личьный, а _G обший
    return setmetatable({_G = _G}, {__index = _G})
end

function bootloader.find(name)
    local checkList = {"/data/", "/vendor/", "/system/", "/system/core/"} --в порядке уменьшения приоритета(data самый приоритетный)
    for index, pathPath in ipairs(checkList) do
        local path = pathPath .. name
        if bootloader.bootfs.exists(path) and not bootloader.bootfs.isDirectory(path) then
            return path
        end
    end
end

function bootloader.readFile(fs, path)
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

function bootloader.writeFile(fs, path, data)
    local file, err = fs.open(path, "wb")
    if not file then return nil, err end
    local ok, err = fs.write(file, data)
    if not ok then
        pcall(fs.close, file)
        return nil, err
    end
    fs.close(file)
    return true
end

function bootloader.loadfile(path, mode, env)
    local data, err = bootloader.readFile(bootloader.bootfs, path)
    if not data then return nil, err end
    return load(data, "=" .. path, mode or "bt", env or _G)
end

function bootloader.dofile(path, env, ...)
    return assert(bootloader.loadfile(path, nil, env))(...)
end

------------------------------------ bootloader functions

function bootloader.unittests(path, ...)
    local fs = require("filesystem")
    local paths = require("paths")
    local programs = require("programs")

    for _, file in ipairs(fs.list(path)) do
        local lpath = paths.concat(path, file)
        local ok, state, log = assert(programs.execute(lpath, ...))
        if not ok then
            error("error \"" .. (state or "unknown error") .. "\" in unittest: " .. file, 0)
        elseif not state then
            error("warning unittest \"" .. file .. "\" \"" .. (log and (", log:\n" .. log) or "") .. "\"", 0)
        end
    end
end

function bootloader.autorunsIn(path, ...)
    local fs = require("filesystem")
    local paths = require("paths")
    local event = require("event")
    local programs = require("programs")

    for i, v in ipairs(fs.list(path)) do
        local full_path = paths.concat(path, v)

        local func, err = programs.load(full_path)
        if not func then
            event.errLog("err \"" .. (err or "unknown error") .. "\", to load programm: " .. full_path)
        else
            local ok, err = pcall(func, ...)
            if not ok then
                event.errLog("err \"" .. (err or "unknown error") .. "\", in programm: " .. full_path)
            end
        end        
    end
end

function bootloader.initScreen(gpu, screen, rx, ry)
    pcall(component.invoke, screen, "turnOn")
    pcall(component.invoke, screen, "setPrecise", false)

    if gpu.getScreen() ~= screen then
        gpu.bind(screen, false)
    end

    if gpu.setActiveBuffer and gpu.getActiveBuffer() ~= 0 then
        gpu.setActiveBuffer(0)
    end
    
    local mx, my = gpu.maxResolution()
    rx = rx or mx
    ry = ry or my
    if rx > mx then rx = mx end
    if ry > my then ry = my end

    gpu.setDepth(1)
    gpu.setDepth(gpu.maxDepth())
    gpu.setResolution(rx, ry)
    gpu.setBackground(0)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, rx, ry, " ")
end

function bootloader.bootstrap()
    if bootloader.runlevel ~= "init" then error("bootstrap can only be started with runlevel init", 0) end

    --natives позваляет получить доступ к нетронутым методами библиотек computer и component
    _G.natives = bootloader.dofile("/system/core/lib/natives.lua", bootloader.createEnv())

    --на lua 5.3 нет встроеной либы bit32, но она нужна для совместимости, так что хай будет
    if not bit32 then 
        _G.bit32 = bootloader.dofile("/system/core/lib/bit32.lua", bootloader.createEnv())
    end

    --бут скрипты. тут инициализации всего и вся
    do 
        local path = "/system/core/boot/"
        for i, v in ipairs(bootloader.bootfs.list(path) or {}) do
            bootloader.dofile(path .. v, _G)
        end
    end

    --package инициализирует библиотек
    bootloader.dofile("/system/core/luaenv/a_base.lua", bootloader.createEnv())
    local package = bootloader.dofile("/system/core/lib/package.lua", bootloader.createEnv(), bootloader)
    _G.require = package.require
    _G.computer = nil
    _G.component = nil
    _G.unicode = nil
    _G.natives = nil
   
    package.raw_reg("paths",      "/system/core/lib/paths.lua")
    package.raw_reg("filesystem", "/system/core/lib/filesystem.lua")
    require("vcomponent")
    require("calls")
    local event = require("event")
    local system = require("system")
    local lastinfo = require("lastinfo")

    --проверка целосности системмы (юнит тесты)
    bootloader.unittests("/system/core/unittests")
    bootloader.unittests("/system/unittests")

    --запуск автозагрузочных файлов ядра и дистрибутива
    bootloader.autorunsIn("/system/core/luaenv")
    bootloader.autorunsIn("/system/core/autoruns")
    bootloader.autorunsIn("/system/autoruns")

    --инициализация компонентов
    lastinfo.update()
    for address, ctype in component.list() do
        event.push("component_added", address, ctype)
    end
    event.events(0.1, {["component_added"] = true})

    --установка runlevel
    bootloader.runlevel = "kernel"

    --инициализация процессов
    event.push("init")
    event.sleep(0.1)
end

function bootloader.runShell(path)
    --запуск оболочки дистрибутива
    if require("filesystem").exists(path) then
        bootloader.bootSplash("Starting The Shell...")
        assert(require("programs").load(path))()
    else
        bootloader.bootSplash("Shell Does Not Exist. Press Enter To Continue.")
        bootloader.waitEnter()
    end
end

------------------------------------ registry

local registry = {}
do
    local registryPath = "/data/registry.dat"
    local mainRegistryPath = bootloader.find("registry.dat") --если он найдет файл в /data, значит он там есть и перезапись не требуеться

    if mainRegistryPath and not bootloader.bootfs.exists(registryPath) then
        pcall(bootloader.bootfs.makeDirectory, "/data")
        pcall(bootloader.writeFile, bootloader.bootfs, registryPath, bootloader.readFile(bootloader.bootfs, mainRegistryPath))
    end

    if bootloader.bootfs.exists(registryPath) then
        local file = bootloader.bootfs.open(registryPath, "rb")
        if file then
            local buffer = ""
            repeat
                local data = bootloader.bootfs.read(file, math.huge)
                buffer = buffer .. (data or "")
            until not data
            bootloader.bootfs.close(file)

            local code = load("return " .. buffer, "=unserialization", "t", {math={huge=math.huge}})
            if code then
                local result = {pcall(code)}
                if result[1] and type(result[2]) == "table" then
                    registry = result[2]
                end
            end
        end
    end
end

------------------------------------ boot splash

do
    local gpu = component.proxy(component.list("gpu")() or "")
    if gpu then
        for screen in component.list("screen") do
            bootloader.initScreen(gpu, screen)
        end
    end

    local logoPath = bootloader.find("logo.lua")
    local logoenv = {gpu = gpu, unicode = unicode, computer = computer, component = component, bootloader = bootloader}
    local logo = bootloader.loadfile(logoPath, nil, setmetatable(logoenv, {__index = _G}))
    
    function bootloader.bootSplash(text)
        if registry.disableLogo or not logo or not gpu then return end
        logoenv.text = text
        for screen in component.list("screen") do
            logoenv.screen = screen
            logo()
        end
    end

    function bootloader.waitEnter()
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

------------------------------------ recovery

if not registry.disableRecovery then
    bootloader.bootSplash("Press R to open recovery menu")

    local gpu = component.proxy(component.list("gpu")() or "")

    if gpu and component.list("screen")() then
        local recoveryScreen, playerNickname
        for i = 1, 10 do
            local eventData = {computer.pullSignal(0.1)}
            if eventData[1] == "key_down" and eventData[4] == 19 then
                for address in component.list("screen") do
                    local keyboards = component.invoke(address, "getKeyboards")
                    for i, keyboard in ipairs(keyboards) do
                        if keyboard == eventData[2] then
                            recoveryScreen = address
                            playerNickname = eventData[6]
                            goto exit
                        end
                    end
                end
            end
        end
        ::exit::

        if recoveryScreen then
            bootloader.bootSplash("RECOVERY MODE")

            local recoveryPath = bootloader.find("recovery.lua")
            if recoveryPath then
                local env = bootloader.createEnv()
                env.bootloader = bootloader
                assert(xpcall(assert(bootloader.loadfile(recoveryPath, nil, env)), debug.traceback, recoveryScreen, playerNickname))
                computer.shutdown("fast")
            else
                bootloader.bootSplash("failed to open recovery. press enter to continue")
                bootloader.waitEnter()
            end
        end
    end
end

------------------------------------ bootstrap

local err = "unknown"

bootloader.bootSplash("Booting...")
bootloader.yield()

local bootstrapResult = {xpcall(bootloader.bootstrap, debug.traceback)}
bootloader.yield()

if bootstrapResult[1] then
    local shellResult = {xpcall(bootloader.runShell, debug.traceback, bootloader.defaultShellPath)}
    bootloader.yield()

    if not shellResult[1] then
        err = tostring(shellResult[2])
    end
else
    err = tostring(bootstrapResult[2])
end

------------------------------------ log error

local log_ok
if require and pcall then
    local function local_require(name)
        local result = {pcall(require, name)}
        if result[1] and type(result[2]) == "table" then
            return result[2]
        end
    end
    local event = local_require("event")
    if event and event.errLog then
        log_ok = pcall(event.errLog, "global error: " .. err)
    end
end

------------------------------------ error output

if log_ok and not registry.disableAutoReboot then --если удалось записать log то комп перезагрузиться, а если не удалось то передаст ошибку в bios
    shutdown(true)
end
error(err, 0)