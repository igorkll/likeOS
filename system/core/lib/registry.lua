local fs = require("filesystem")
local serialization = require("serialization")

--------------------------------

local function new(path, data)
    checkArg(1, path, "string")
    checkArg(2, data, "table", "nil")

    local lreg = {path = path, data = data or {}}
    if fs.exists(lreg.path) then
        local tbl = serialization.load(lreg.path)
        if tbl then
            lreg.data = tbl
        end
    end

    function lreg.save()
        return fs.writeFile(lreg.path, serialization.serialize(lreg.data))
    end

    function lreg.apply(tbl)
        if type(tbl) == "string" then
            local ntbl, err = serialization.load(tbl)
            if not ntbl then
                return nil, err
            end
            tbl = ntbl
        end
        local function recurse(ltbl, native)
            for _, reg_rm in ipairs(ltbl.reg_rm_list or {}) do
                native[reg_rm] = nil
            end
            for key, value in pairs(ltbl) do
                if type(value) == "table" then
                    if type(native[key]) ~= "table" then
                        native[key] = {}
                    end
                    recurse(value, native[key])
                else
                    native[key] = value
                end
            end
        end
        recurse(tbl, lreg.data)
        lreg.save()
        return term
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