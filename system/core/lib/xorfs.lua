local fs = require("filesystem")
local xorfs = {}

function xorfs.toggleData(data, xorcode, offset)
    
end

function xorfs.toggleFile(path, xorcode)
    local file = assert(fs.open(path, "rb"))
    local xordata = {}
    local offset = 0
    while true do
        local chunk = file.readMax()
        if not chunk then
            file.close()
            break
        else
            table.insert(xordata, xorfs.toggleData(chunk, xorcode, offset))
            offset = offset + #chunk
        end
    end
    file = assert(fs.open(path, "wb"))
    file.write(table.concat(xordata))
    file.close()
end

function xorfs.xorcode(password)
    local sha256 = require("sha256")
    local xorcode = {}
    for i = 1, 16 do
        table.insert(xorcode, sha256.sha256bin(i .. password))
    end
    return table.concat(xorcode)
end

return xorfs