local cache = {}
cache.cache = {} --can be cleaned at any time
cache.data = {}

function cache.clearCache()
    for key, value in pairs(cache.cache) do
        cache.cache[key] = nil
    end
    cache.cache = {}
end

return cache