local raw_dofile, createEnv = ...
local component = component
local computer = computer
local unicode = unicode

------------------------------------

local package = {}
package.libsPaths = {"/system/core/lib"}

function package.findLib(name)
    local fs = require("filesystem")
    local paths = require("paths")
    local path = nil

    for i, v in ipairs(package.libsPaths) do
        local lpath = paths.concat(v, name .. ".lua")
        if fs.exists(lpath) then
            path = lpath
            break
        end
    end

    return path
end

function _G.require(name)
    if not package.loaded[name] then
        local finded = package.findLib(name)
        if not finded then
            error("lib " .. name .. " is not found", 0)
        end
        local fs = require("filesystem")
        local calls = require("calls")

        local file = assert(fs.open(finded, "rb"))
        local data = file.readAll()
        file.close()

        package.loaded[name] = assert(load(data, "=" .. finded, nil, calls.call("createEnv")))()
    end
    return package.loaded[name]
end

------------------------------------

package.loaded = {package = package}

package.loaded.component = component
package.loaded.computer = computer
package.loaded.unicode = unicode

package.loaded.paths = raw_dofile("/system/core/lib/paths.lua", nil, createEnv()) --подгрузить зарания во избежании проблемм
package.loaded.calls = raw_dofile("/system/core/lib/calls.lua", nil, createEnv())
package.loaded.filesystem = raw_dofile("/system/core/lib/filesystem.lua", nil, createEnv())

raw_dofile = nil --чтобы навярника выгрузилось
createEnv = nil

------------------------------------

return package