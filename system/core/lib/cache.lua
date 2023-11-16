local fs = require("filesystem")
local paths = require("paths")

local runtimeCache = "/data/cache/runtime"
fs.remove(runtimeCache)
fs.makeDirectory(runtimeCache)

local constCache = "/data/cache/const"
fs.makeDirectory(constCache)


local function createRuntimeCache(folder)
    
end


local cache = {}
cache.cache = {} --can be cleaned at any time
cache.data = {} --in the future it will be saved to the hard disk
cache.runtime = {} --immediately saved to the hard disk(cleared after reboot)
cache.const = {} --instantly saved to the hard disk (not deleted)

function cache.clearCache()
    for key, value in pairs(cache.cache) do
        cache.cache[key] = nil
    end
    cache.cache = {}
end

return cache