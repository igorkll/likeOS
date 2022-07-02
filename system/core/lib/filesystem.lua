local component = require("component")
local computer = require("computer")
local unicode = require("unicode")
local paths = require("paths")

------------------------------------

local filesystem = {}
filesystem.mountList = {}

function filesystem.mount(proxy, path)
    path = paths.canonical(path)
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == path then
            return "another filesystem is already mounted here"
        end
    end
    table.insert(filesystem.mountList, {proxy, path})
end

function filesystem.umount(path)
    path = paths.canonical(path)
    for i, v in ipairs(filesystem.mountList) do
        if v[2] == path then
            table.remove(filesystem.mountList, i)
            return true
        end
    end
    return false
end

function filesystem.get(path)
    path = paths.canonical(path)
    for i = 1, #filesystem.mountList do
        if unicode.sub(path, 1, unicode.len(filesystem.mountList[i][2])) == filesystem.mountList[i][2] then
            return filesystem.mountList[i][1], unicode.sub(path, unicode.len(filesystem.mountList[i][2]) + 1, -1)
        end
    end
end

function filesystem.exists(path)
	local proxy, proxyPath = filesystem.get(path)
	return proxy.exists(proxyPath)
end

function filesystem.size(path)
	local proxy, proxyPath = filesystem.get(path)
	return proxy.size(proxyPath)
end

function filesystem.isDirectory(path)
	local proxy, proxyPath = filesystem.get(path)
	return proxy.isDirectory(proxyPath)
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

function filesystem.list(path)
	local proxy, proxyPath = filesystem.get(path)
	
	local list, reason = proxy.list(proxyPath)	
	if list then return list end
	return list, reason
end

function filesystem.rename(fromPath, toPath)
	local fromProxy, fromProxyPath = filesystem.get(fromPath)
	local toProxy, toProxyPath = filesystem.get(toPath)

	-- If it's the same filesystem component
	if fromProxy.address == toProxy.address then
		return fromProxy.rename(fromProxyPath, toProxyPath)
	else
		-- Copy files to destination
		filesystem.copy(fromPath, toPath)
		-- Remove original files
		filesystem.remove(fromPath)
	end
end

function filesystem.open(path, mode)
	local proxy, proxyPath = filesystem.get(path)
	local result, reason = proxy.open(proxyPath, mode)
	if result then
		local handle = { --а нам он и нафиг не нужен цей файл buffer...
            read = function(...) return proxy.read(result, ...) end,
            write = function(...) return proxy.write(result, ...) end,
            close = function(...) return proxy.close(result, ...) end,
            seek = function(...) return proxy.seek(result, ...) end,
            handle = result,
		}

        return handle
	end
    return nil, reason
end

function filesystem.copy(fromPath, toPath)
	local function copyRecursively(fromPath, toPath)
		if filesystem.isDirectory(fromPath) then
			filesystem.makeDirectory(toPath)

			local list = filesystem.list(fromPath)
			for i = 1, #list do
				copyRecursively(fromPath .. "/" .. list[i], toPath .. "/" .. list[i])
			end
		else
			local fromHandle = filesystem.open(fromPath, "rb")
			if fromHandle then
				local toHandle = filesystem.open(toPath, "wb")
				if toHandle then
					while true do
						local chunk = fromHandle.read(math.huge)
						if chunk then
							if not toHandle.write(chunk) then
								break
							end
						else
							toHandle.close()
							fromHandle.close()

							break
						end
					end
				end
			end
		end
	end

	copyRecursively(fromPath, toPath)
end

filesystem.mount("/", computer.getBootAddress())

return filesystem