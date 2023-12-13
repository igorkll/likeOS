local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local paths = require("paths")
local bootloader = require("bootloader")

------------------------------------

local filesystem = {}
filesystem.mountList = {}
filesystem.baseFileDirectorySize = 512 --задаеться к конфиге мода(по умалчанию 512 байт)
filesystem.autoMount = true
filesystem.inited = false

local function startSlash(path)
    if unicode.sub(path, 1, 1) ~= "/" then
        return "/" .. path
    end
    return path
end

local function endSlash(path)
    if unicode.sub(path, unicode.len(path), unicode.len(path)) ~= "/" then
        return path .. "/"
    end
    return path
end

local function noEndSlash(path)
    if unicode.len(path) > 1 and unicode.sub(path, unicode.len(path), unicode.len(path)) == "/" then
        return unicode.sub(path, 1, unicode.len(path) - 1)
    end
    return path
end

function filesystem.mount(proxy, path)
    if type(proxy) == "string" then
        local lproxy, err = component.proxy(proxy)
        if not lproxy then
            return nil, err
        end
        proxy = lproxy
    end

    path = paths.absolute(path)
    if filesystem.inited then
        filesystem.makeDirectory(paths.path(path))
    end

    path = endSlash(path)
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == path then
            return nil, "another filesystem is already mounted here"
        end
    end

    table.insert(filesystem.mountList, {proxy, path, {}})
    table.sort(filesystem.mountList, function(a, b) --просто нужно, иначе все по бараде пойдет
        return unicode.len(a[2]) > unicode.len(b[2])
    end)

    return true
end

function filesystem.umount(path)
    path = endSlash(paths.absolute(path))
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == path then
            table.remove(filesystem.mountList, i)
            return true
        end
    end
    return false
end

function filesystem.mounts()
    local list = {}
    for i, v in ipairs(filesystem.mountList) do
        local proxy, path = v[1], v[2]
        list[path] = v
        list[proxy.address] = v
        list[i] = v
    end
    return list
end

function filesystem.get(path)
    path = endSlash(paths.absolute(path))
    
    for i = #filesystem.mountList, 1, -1 do
        if component.isConnected and not component.isConnected(filesystem.mountList[i][1]) then
            table.remove(filesystem.mountList, i)
        end
    end

    for i = 1, #filesystem.mountList do
        if unicode.sub(path, 1, unicode.len(filesystem.mountList[i][2])) == filesystem.mountList[i][2] then
            return filesystem.mountList[i][1], noEndSlash(startSlash(unicode.sub(path, unicode.len(filesystem.mountList[i][2]) + 1, unicode.len(path)))), filesystem.mountList[i][3]
        end
    end

    if filesystem.mountList[1] then
        return filesystem.mountList[1][1], filesystem.mountList[1][2], filesystem.mountList[1][3]
    end
end

function filesystem.exists(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.exists(proxyPath)
end

function filesystem.size(path)
    local proxy, proxyPath = filesystem.get(path)
    local size = 0
    local sizeWithBaseCost = 0
    local function recurse(lpath)
        sizeWithBaseCost = sizeWithBaseCost + filesystem.baseFileDirectorySize
        for _, filename in ipairs(filesystem.list(lpath)) do
            local fullpath = paths.concat(lpath, filename)
            if proxy.isDirectory(fullpath) then
                recurse(fullpath)
            else
                local lsize = proxy.size(fullpath)
                size = size + lsize
                sizeWithBaseCost = sizeWithBaseCost + lsize + filesystem.baseFileDirectorySize
            end
        end
    end
    if proxy.isDirectory(proxyPath) then
        recurse(proxyPath)
    else
        local lsize = proxy.size(proxyPath)
        size = size + lsize
        sizeWithBaseCost = sizeWithBaseCost + lsize + filesystem.baseFileDirectorySize
    end
    return size, sizeWithBaseCost
end

function filesystem.isDirectory(path)
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == paths.absolute(path) then
            return true
        end
    end

    local proxy, proxyPath = filesystem.get(path)
    return proxy.isDirectory(proxyPath)
end

function filesystem.isReadOnly(path)
    local proxy, proxyPath, mountData = filesystem.get(path)
    if mountData.ro ~= nil then return mountData.ro end
    mountData.ro = proxy.isReadOnly()
    return mountData.ro
end

function filesystem.isLabelReadOnly(path)
    local proxy, proxyPath, mountData = filesystem.get(path)
    if mountData.lro ~= nil then return mountData.lro end
    mountData.lro = not pcall(proxy.setLabel, proxy.getLabel() or nil)
    return mountData.lro
end

function filesystem.makeDirectory(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.makeDirectory(proxyPath)
end

function filesystem.lastModified(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.lastModified(proxyPath)
end

function filesystem.remove(path)
    local proxy, proxyPath = filesystem.get(path)
    return proxy.remove(proxyPath)
end

function filesystem.list(path, fullpaths)
    local proxy, proxyPath = filesystem.get(path)
    local tbl = proxy.list(proxyPath)

    if tbl then
        tbl.n = nil
        for i = 1, #filesystem.mountList do
            if paths.absolute(path) == paths.path(filesystem.mountList[i][2]) then
                table.insert(tbl, paths.name(filesystem.mountList[i][2]))
            end
        end
        if fullpaths then
            for i, v in ipairs(tbl) do
                tbl[i] = paths.concat(path, v)
            end
        end
        table.sort(tbl)
        return tbl
    else
        return {}
    end
end

function filesystem.rename(fromPath, toPath)
    fromPath = paths.absolute(fromPath)
    toPath = paths.absolute(toPath)
    if paths.equals(fromPath, toPath) then return end

    local fromProxy, fromProxyPath = filesystem.get(fromPath)
    local toProxy, toProxyPath = filesystem.get(toPath)

    if fromProxy.address == toProxy.address then
        return fromProxy.rename(fromProxyPath, toProxyPath)
    else
        local success, err = filesystem.copy(fromPath, toPath)
        if not success then
            return nil, err
        end
        local success, err = filesystem.remove(fromPath)
        if not success then
            return nil, err
        end
    end

    return true
end

function filesystem.open(path, mode, bufferSize)
    mode = mode or "rb"
    local proxy, proxyPath = filesystem.get(path)
    local result, reason = proxy.open(proxyPath, mode)
    if result then
        if bufferSize == true then
            bufferSize = 16 * 1024
        end

        local tool = mode:sub(#mode, #mode) == "b" and string or unicode
        local readBuffer
        local writeBuffer

        local handle = {
            handle = result,

            read = function(readsize)
                if not readsize then
                    readsize = 1
                end

                if bufferSize then
                    if not readBuffer then
                        readBuffer = proxy.read(result, bufferSize) or ""
                    end

                    local str = tool.sub(readBuffer, 1, readsize)
                    readBuffer = tool.sub(readBuffer, readsize + 1, tool.len(readBuffer))
                    if tool.len(readBuffer) == 0 then readBuffer = nil end
                    if tool.len(str) > 0 then
                        return str
                    end
                else
                    return proxy.read(result, readsize)
                end
            end,
            write = function(writedata)
                if bufferSize then
                    writeBuffer = (writeBuffer or "") .. writedata
                    if tool.len(writeBuffer) > bufferSize then
                        local result = proxy.write(result, writeBuffer)
                        writeBuffer = nil
                        return result
                    end
                else
                    return proxy.write(result, writedata)
                end
            end,
            close = function(...)
                if writeBuffer then
                    return proxy.write(result, writeBuffer)
                end
                return proxy.close(result, ...)
            end,

            --don`t use with buffered mode!
            seek = function(...)
                return proxy.seek(result, ...)
            end,
            readAll = function()
                local buffer = ""
                repeat
                    local data = proxy.read(result, math.huge)
                    buffer = buffer .. (data or "")
                until not data
                return buffer
            end,
            readMax = function()
                return proxy.read(result, math.huge)
            end
        }

        return handle
    end
    return nil, reason
end

function filesystem.copy(fromPath, toPath, fcheck)
    fromPath = paths.absolute(fromPath)
    toPath = paths.absolute(toPath)
    if paths.equals(fromPath, toPath) then return end
    local function copyRecursively(fromPath, toPath)
        if not fcheck or fcheck(fromPath, toPath) then
            if filesystem.isDirectory(fromPath) then
                filesystem.makeDirectory(toPath)

                local list = filesystem.list(fromPath)
                for i = 1, #list do
                    local from = paths.concat(fromPath, list[i])
                    local to =  paths.concat(toPath, list[i])
                    local success, err = copyRecursively(from, to)
                    if not success then
                        return nil, err
                    end
                end
            else
                local fromHandle, err = filesystem.open(fromPath, "rb")
                if fromHandle then
                    local toHandle, err = filesystem.open(toPath, "wb")
                    if toHandle then
                        while true do
                            local chunk = fromHandle.read(math.huge)
                            if chunk then
                                if not toHandle.write(chunk) then
                                    return nil, "failed to write file"
                                end
                            else
                                toHandle.close()
                                fromHandle.close()

                                break
                            end
                        end
                    else
                        return nil, err
                    end
                else
                    return nil, err
                end
            end
        end

        return true
    end

    return copyRecursively(fromPath, toPath)
end

function filesystem.writeFile(path, data)
    filesystem.makeDirectory(paths.path(path))
    local file, err = filesystem.open(path, "wb")
    if not file then return nil, err or "unknown error" end
    local ok, err = file.write(data)
    if not ok then
        pcall(file.close)
        return err or "unknown error"
    end
    file.close()
    return true
end

function filesystem.readFile(path)
    local file, err = filesystem.open(path, "rb")
    if not file then return nil, err or "unknown error" end
    local result = {file.readAll()}
    file.close()
    return table.unpack(result)
end

function filesystem.readSignature(path, size)
    local file, err = filesystem.open(path, "rb")
    if not file then return nil, err or "unknown error" end
    local result = {file.read(size or 8)}
    file.close()
    return table.unpack(result)
end

function filesystem.equals(path1, path2)
    local file1 = assert(filesystem.open(path1, "rb"))
    local file2 = assert(filesystem.open(path2, "rb"))
    while true do
        local chunk1 = file1.readMax()
        local chunk2 = file2.readMax()
        if not chunk1 and not chunk2 then
            break
        elseif chunk1 ~= chunk2 then
            return false
        end
    end
    file1.close()
    file2.close()
    return true
end

filesystem.bootaddress = bootloader.bootaddress
filesystem.tmpaddress = bootloader.tmpaddress

assert(filesystem.mount(filesystem.bootaddress, "/"))
if filesystem.autoMount then
    assert(filesystem.mount(filesystem.tmpaddress, "/tmp"))
    assert(filesystem.mount(filesystem.tmpaddress, "/mnt/tmpfs"))
    assert(filesystem.mount(filesystem.bootaddress, "/mnt/root"))
end

filesystem.inited = true
return filesystem