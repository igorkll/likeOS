local component = require("component")
local fs = require("filesystem")
local paths = require("paths")
local internet = {}

function internet.get(url)
    local inet = component.proxy(component.list("internet")() or "")

    if not inet then
        return nil, "no internet-card"
    end

    local handle = inet.request(url)
    if handle then
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
        return nil, "invalid address"
    end
end

function internet.download(url, path)
    local inet = component.proxy(component.list("internet")() or "")

    if not inet then
        return nil, "no internet-card"
    end

    local handle = inet.request(url)
    if handle then
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

                if dataSize >= 1024 * 32 then
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
        return nil, "invalid address"
    end
end

internet.getInternetFile = internet.get
internet.unloadable = true
return internet