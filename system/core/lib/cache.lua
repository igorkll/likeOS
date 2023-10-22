local cache = {}
cache.cache = {}
cache.copiedText = nil --put the copied text here

function cache.clearCache()
    for key, value in pairs(cache.cache) do
        cache.cache[key] = nil
    end
    cache.cache = {}
end

return cache