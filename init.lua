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

assert(load(assert(readFile(bootproxy, bootfile)), "=" .. bootfile, nil, _ENV))()