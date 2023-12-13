local setmetatable = setmetatable
local rawget = rawget
local invoke = component.invoke
local ctype = component.type

local pcache = setmetatable({}, {__mode = "v"})
function component.proxy(address)
    if not pcache[address] then
        pcache[address] = setmetatable({__cache = {address = address, type = ctype(address)}}, {__index = function(self, key)
            local cache = rawget(self, "__cache")
            if not cache[key] then
                cache[key] = function(...)
                    return invoke(address, key, ...)
                end
            end
            return cache[key]
        end})
    end
    return pcache[address]
end