--likeOS core
local bootfs = component.proxy(computer.getBootAddress())
local tmpfs = component.proxy(computer.tmpAddress())

local function readFile(fs, path)
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

local function loadfile(fs, path, mode, env)
    local data, err = readFile(fs, path)
    if not data then return nil, err end
    return load(data, "=" .. path, mode or "bt", env or _G)
end

--------------------------------------------

local bootfile = "/system/core/bootloader.lua"
local bootproxy = bootfs

--------------------------------------------

local bootloaderSettingsPath = "/bootloader"
local bootloaderSettingsPath_bootfile = "/bootloader/bootfile"
local bootloaderSettingsPath_bootaddr = "/bootloader/bootaddr"

--------------------------------------------

if tmpfs.exists(bootloaderSettingsPath_bootfile) then
    bootfile = assert(readFile(tmpfs, bootloaderSettingsPath_bootfile))
end

if tmpfs.exists(bootloaderSettingsPath_bootaddr) then
    local bootaddr = assert(readFile(tmpfs, bootloaderSettingsPath_bootaddr))
    computer.getBootAddress = function()
        return bootaddr
    end
    bootproxy = assert(component.proxy(bootaddr))
end

tmpfs.remove(bootloaderSettingsPath)

--------------------------------------------

if bootproxy.exists(bootfile) and not bootproxy.isDirectory(bootfile) then
    assert(load(assert(readFile(bootproxy, bootfile)), "=" .. bootfile, nil, _ENV))()
else
    local lowLevelInitializer = "/likeOS_startup.lua" --может использоваться для запуска обновления системы
    if bootproxy.exists(lowLevelInitializer) and not bootproxy.isDirectory(lowLevelInitializer) then
        assert(loadfile(bootproxy, lowLevelInitializer))()
    end
end