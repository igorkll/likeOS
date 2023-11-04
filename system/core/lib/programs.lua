local fs = require("filesystem")
local unicode = require("unicode")
local paths = require("paths")
local package = require("package")
local bootloader = require("bootloader")
local event = require("event")

------------------------------------

local programs = {}
programs.paths = {"/data/bin", "/vendor/bin", "/system/bin", "/system/core/bin"} --позиция по мере снижения приоритета(первый элемент это самый высокий приоритет)
programs.unloadable = true

function programs.find(name)
    if unicode.sub(name, 1, 1) == "/" then
        if fs.exists(name) then
            if fs.isDirectory(name) then
                local executeFile = paths.concat(name, "main.lua")
                if fs.exists(executeFile) and not fs.isDirectory(executeFile) then
                    return executeFile
                end
            else
                return name
            end
        end
    else
        for i, v in ipairs(programs.paths) do
            local path = paths.concat(v, name)
            if fs.exists(path .. ".lua") and not fs.isDirectory(path .. ".lua") then
                return path .. ".lua"
            else
                if fs.exists(path .. ".app") and fs.isDirectory(path .. ".app") then
                    path = paths.concat(path .. ".app", "main.lua")
                    if fs.exists(path) and not fs.isDirectory(path) then
                        return path
                    end
                end
            end
        end
    end
end

function programs.load(name, mode, env)
    local path = programs.find(name)
    if not path then return nil, "no such program" end

    local file, err = fs.open(path, "rb")
    if not file then return nil, err end
    local data = file.readAll()
    file.close()
    
    local code, err = load(data, "=" .. path, mode, env or bootloader.createEnv())
    if not code then return nil, err end

    return code
end

function programs.execute(name, ...)
    local code, err = programs.load(name)
    if not code then return nil, err end

    --return pcall(code, ...)
    
    local thread = package.get("thread")
    if not thread then
        return pcall(code, ...)
    else
        local t = thread.create(code, ...)
        t:resume() --потому что по умолчанию поток спит
        while t:status() ~= "dead" do event.yield() end
        return table.unpack(t.out or {true})
    end
end

return programs