local component = require("component")
local fs = require("filesystem")
local paths = require("paths")
local event = require("event")
local internet = {settings = {}}
internet.settings.timeout = 3
internet.settings.downloadPart = 1024 * 32

local unknown = "unknown error"

function internet.wait(handle)
    while true do
        local successfully, err = handle.finishConnect()
        if successfully then
            return true
        elseif successfully == nil then
            return nil, tostring(err or unknown)
        end
        event.yield()
    end
end

function internet.get(url)
    local inet = component.proxy(component.list("internet")() or "")
    if not inet then
        return nil, "no internet-card"
    end

    local handle, err = inet.request(url)
    if handle then
        local successfully, err = internet.wait(handle)
        if not successfully then
            return nil, err
        end

        local data = {}
        while true do
            local result, reason = handle.read(math.huge) 
            if result then
                table.insert(data, result)
            else
                handle.close()
                
                if reason then
                    return nil, reason
                else
                    return table.concat(data)
                end
            end
        end
    else
        return nil, tostring(err or unknown)
    end
end

function internet.download(url, path)
    local inet = component.proxy(component.list("internet")() or "")
    if not inet then
        return nil, "no internet-card"
    end

    local handle, err = inet.request(url)
    if handle then
        local successfully, err = internet.wait(handle)
        if not successfully then
            return nil, err
        end

        fs.makeDirectory(paths.path(path))
        local file, err = fs.open(path, "wb")
        if not file then
            return nil, err
        end
        
        local data = {}
        local dataSize = 0
        while true do
            local result, reason = handle.read(math.huge) 
            if result then
                table.insert(data, result)
                dataSize = dataSize + #result

                if dataSize >= internet.settings.downloadPart then
                    file.write(table.concat(data))
                    data = {}
                    dataSize = 0
                end
            else
                if #data > 0 then
                    file.write(table.concat(data))
                end
                file.close()
                handle.close()
                
                if reason then
                    return nil, reason
                else
                    return true
                end
            end
        end
    else
        return nil, tostring(err or unknown)
    end
end

internet.getInternetFile = internet.get
internet.unloadable = true
return internet