local utils = {}

function utils.check(func, ...)
    local result = {pcall(func, ...)}
    if result[1] then
        return table.unpack(result, 2)
    else
        return nil, result[2] or "unknown error"
    end
end

function utils.openPort(modem, port)
    local result = modem.open(port)
    if result == nil then --если открыто больше портов чем поддерживает модем(false означает что выбраный порт уже открыт)
        modem.close()
        return modem.open(port)
    end
    return result
end

utils.unloadable = true
return utils