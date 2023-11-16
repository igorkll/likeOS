--позваляет получить доступ к оригинальным методам библиотек computer и component
--например если нужно исключить влияния vcomponent

local function deepclone(tbl, newtbl)
    local cache = {}
    local function recurse(tbl, newtbl)
        local newtbl = newtbl or {}

        for k, v in pairs(tbl) do
            if type(v) == "table" then
                local ltbl = cache[v]
                if not ltbl then
                    cache[v] = {}
                    ltbl = cache[v]
                    recurse(v, cache[v])
                end
                newtbl[k] = ltbl
            else
                newtbl[k] = v
            end
        end

        return newtbl
    end

    return recurse(tbl, newtbl)
end

local natives = {}
natives.component = deepclone(component)
natives.computer = deepclone(computer)
natives.pcall = pcall
natives.xpcall = xpcall
natives.pairs = pairs
natives.ipairs = ipairs
return natives