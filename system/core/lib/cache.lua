local fs = require("filesystem")
local paths = require("paths")

local runtimeCache = "/data/cache/runtime"
fs.remove(runtimeCache)

--------------------------------------------------

local cache = {}

cache.hddCacheMt = {}
function cache.hddCacheMt:__index(key)
    if cache.cache.caches and cache.cache.caches[self._folder] then
        for name, value in pairs(cache.cache.caches[self._folder]) do
            if paths.hideExtension(name) == key then
                return value
            end
        end
    end

    if not cache.cache.caches then cache.cache.caches = {} end
    if not cache.cache.caches[self._folder] then cache.cache.caches[self._folder] = {} end

    for _, name in ipairs(fs.list(self._folder)) do
        local lkey = paths.hideExtension(name)
        if lkey == key then
            local objtype = paths.extension(name)
            local valuename = key .. "." .. objtype
            local path = paths.concat(self._folder, valuename)
            if fs.exists(path) then
                if fs.isDirectory(path) then
                    local tbl = cache.createHddCache(path)
                    cache.cache.caches[self._folder][valuename] = tbl
                    return tbl
                else
                    local str = fs.readFile(path)
                    local obj
                    if objtype == "number" then
                        obj = tonumber(str)
                    elseif objtype == "boolean" then
                        obj = toboolean(str)
                    else
                        obj = str
                    end
                    cache.cache.caches[self._folder][valuename] = obj
                    return obj
                end
            end
        end
    end
end

function cache.hddCacheMt:__newindex(key, value)
    local valuetype = type(value)
    key = tostring(key)
    local valuename = key .. "." .. valuetype
    local path = paths.concat(self._folder, valuename)

    if not cache.cache.caches then cache.cache.caches = {} end
    if not cache.cache.caches[self._folder] then cache.cache.caches[self._folder] = {} end

    if valuetype == "number" or valuetype == "string" or valuetype == "boolean" then
        cache.cache.caches[self._folder][valuename] = tostring(value)
    elseif valuetype == "nil" then
        cache.cache.caches[self._folder][valuename] = nil
        fs.remove(path)
    elseif valuetype == "table" then
        local tbl = cache.createHddCache(path, value)
        cache.cache.caches[self._folder][valuename] = tbl
        return tbl
    else
        error("the cache does not support the type: " .. key, 2)
    end
end

function cache.hddCacheMt:__pairs()
    local tbl = {}
    for _, name in ipairs(fs.list(self._folder)) do
        local key = paths.hideExtension(name)
        tbl[key] = self(key)
    end
    return pairs(tbl)
end

--------------------------------------------------

function cache.createHddCache(folder, base)
    local tbl
    if base then
        tbl = base
        tbl._folder = paths.canonical(folder)
    else
        tbl = {_folder = paths.canonical(folder)}
    end
    return setmetatable(base, cache.hddCacheMt)
end

function cache.clearCache()
    if cache.cache.caches then
        local function process(tbl)
            for lpath, values in pairs(tbl) do
                for valuename, value in pairs(values) do
                    local path = paths.concat(lpath, valuename)
                    local valuetype = type(value)

                    if valuetype == "number" or valuetype == "string" or valuetype == "boolean" then
                        fs.writeFile(path, tostring(value))
                    elseif valuetype == "table" then
                        fs.makeDirectory(path)
                        process(value)
                    end
                end
            end
        end
        process(cache.cache.caches)
    end

    for key, value in pairs(cache.cache) do
        cache.cache[key] = nil
    end
    cache.cache = {}
end

cache.cache = {} --can be cleaned at any time
cache.data = cache.createHddCache(runtimeCache) --it can be cached on the hard disk if there is a lack of RAM
cache.const = cache.createHddCache("/data/cache/const") --instantly saved to the hard disk (not deleted)

return cache