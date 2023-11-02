local component = require("component")
local fs = require("filesystem")
local internet = {}

function internet.get(url)
    local inet = component.proxy(component.list("internet")() or "")

    if not inet then
        return nil, "no internet-card"
    end

    local handle = inet.request(url)
    local data = {}
    local dataI = 1
    if handle then
        while true do
            local result, reason = handle.read(math.huge) 
            if result then
                data[dataI] = result
                dataI = dataI + 1
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
        local file, err = fs.open(path, "wb")
        if not file then
            return nil, err
        end
        
        while true do
            local result, reason = handle.read(math.huge) 
            if result then
                file.write(result)
            else
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