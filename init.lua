do
    local bootaddress, invoke = computer.getBootAddress(), component.invoke
    local function raw_loadfile(path)
        local file, buffer = assert(invoke(bootaddress, "open", path, "rb")), ""
        repeat
            local data = assert(invoke(bootaddress, "read", file, math.huge))
            buffer = buffer .. (data or "")
        until not data
        return load(buffer, "=" .. path, "bt", _ENV)
    end
end

while true do
    
end