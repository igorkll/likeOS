local fs = require("filesystem")
local serialization = require("serialization")

--------------------------------

local function new(path, data)
    local lreg = {path = path, data = data or {}}
    if fs.exists(lreg.path) then
        local content = fs.readFile(lreg.path)
        if content then
            local result = {pcall(serialization.unserialize, content)}
            if result[1] and type(result[2]) == "table" then
                lreg.data = result[2]
            end
        end
    end

    function lreg.save()
        fs.writeFile(lreg.path, serialization.serialize(lreg.data))
    end
    
    setmetatable(lreg, {__newindex = function(_, key, value)
        if lreg.data[key] ~= value then
            lreg.data[key] = value
            lreg.save()
        end
    end, __index = function(_, key)
        return lreg.data[key]
    end})

    return lreg
end

local registry = new("/data/registry.dat")
rawset(registry, "new", new)
rawset(registry, "unloadable", true)
return registry