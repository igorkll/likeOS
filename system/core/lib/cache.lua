local fs = require("filesystem")
local paths = require("paths")

local runtimeCache = "/data/cache/runtime"
fs.remove(runtimeCache)

--------------------------------------------------

local cache = {}

cache.hddCacheMt = {}
function cache.hddCacheMt:__index(key)
    for name, value in pairs(cache.cache.caches[self._folder]) do
        if paths.hideExtension(name) == key then
            return value
        end
    end

    for _, name in ipairs(fs.list(self._folder)) do
        local lkey = paths.hideExtension(name)
        if lkey == key then
            local path = paths.concat(self._folder, key .. "." .. paths.extension(name))
            if fs.exists(path) then
                if fs.isDirectory(path) then
                    return cache.createHddCache(path)
                else
                    return fs.readFile(path)
                end
            end
        end
    end
end

function cache.hddCacheMt:__newindex(key, value)
    local valuetype = type(value)
    key = tostring(key)
    value = tostring(value)
    local valuename = key .. "." .. valuetype
    local path = paths.concat(self._folder, valuename)

    if valuetype == "number" or valuetype == "string" or valuetype == "boolean" then
        cache.cache.caches[self._folder][valuename] = value
        fs.writeFile(path, value)
    elseif valuetype == "nil" then
        cache.cache.caches[self._folder][valuename] = nil
        fs.remove(path)
    elseif valuetype == "table" then
        local tbl = cache.createHddCache(path)
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

function cache.createHddCache(folder)
    folder = paths.canonical(folder)
    fs.makeDirectory(folder)

    if not cache.cache.caches then cache.cache.caches = {} end
    cache.cache.caches[folder] = {}

    return setmetatable({_folder = folder}, cache.hddCacheMt)
end

function cache.clearCache()
    for key, value in pairs(cache.cache) do
        cache.cache[key] = nil
    end
    cache.cache = {}
end

cache.cache = {} --can be cleaned at any time
cache.data = cache.createHddCache(runtimeCache) --in the future it will be saved to the hard disk
cache.const = cache.createHddCache("/data/cache/const") --instantly saved to the hard disk (not deleted)

return cache