local raw_loadfile = ...

----------------------------------

local component = component
local computer = computer
local unicode = unicode

local function dofile(path)
    return assert(raw_loadfile(path))
end

do --оптимизация для computer.getDeviceInfo
    local computer_pullSignal = computer.pullSignal
    local deviceinfo = computer.getDeviceInfo()

    function computer.getDeviceInfo()
        return deviceinfo
    end
    function computer.pullSignal(time)
        local eventData = {computer_pullSignal(time)}
        if eventData[1] == "component_added" or eventData[1] == "component_removed" then
            deviceinfo = computer.getDeviceInfo()
        end
        return table.unpack(eventData)
    end
end

do --package
    local package = dofile("/system/core/lib/package.lua")
    package.loaded.computer = computer
    package.loaded.component = component
    package.loaded.unicode = unicode

    _G.computer = nil
    _G.component = nil
    _G.unicode = nil
end