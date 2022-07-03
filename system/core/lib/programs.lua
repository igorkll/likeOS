local fs = require("filesystem")
local paths = require("paths")
local calls = require("calls")

------------------------------------

local programs = {}
programs.paths = {"/system/core/bin", "/system/bin"}

function programs.find(name)
    for i, v in ipairs(programs.paths) do
        local path = paths.concat(v, name .. ".lua")
        if fs.exists(path) then
            return path
        end
    end
end

function programs.load(name)
    local path
    if name:sub(1, 1) == "/" then
        path = name
    else
        path = programs.find(name)
    end
    if not path then return nil, "no such programm" end

    local file, err = fs.open(path, "rb")
    if not file then return nil, err end
    local data = file.readAll()
    file.close()
    
    local code, err = load(data, "=" .. path, nil, calls.call("createEnv"))
    if not code then return nil, err end

    return code
end

return programs