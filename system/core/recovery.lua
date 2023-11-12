local bootloader = bootloader
local component = component
local computer = computer
local unicode = unicode

local screen = ...
local deviceinfo = computer.getDeviceInfo()
local gpu = component.proxy(component.list("gpu")() or "")
if not gpu then return end
bootloader.initScreen(gpu, screen, 80, 25) --на экране с более низким разрешениям будет выбрано максимальное. на экране с более высоким установленное
local rx, ry = gpu.getResolution()
local centerY = math.floor(ry / 2)
local keyboard = component.invoke(screen, "getKeyboards")[1]

-------------------------------------------------------------- local api

local function getDeviceType()
    local function isType(ctype)
        return component.list(ctype)() and ctype
    end
    
    local function isServer()
        local obj = deviceinfo[computer.address()]
        if obj and obj.description and obj.description:lower() == "server" then
            return "server"
        end
    end
    
    return isType("tablet") or isType("microcontroller") or isType("drone") or isType("robot") or isServer() or isType("computer") or "unknown"
end

local function invertColor()
    gpu.setBackground(gpu.setForeground(gpu.getBackground()))
end

local function centerPrint(y, text)
    gpu.set(((rx / 2) - (unicode.len(text) / 2)) + 1, y, text)
end

local function screenFill(y)
    gpu.fill(8, y, rx - 15, 1, " ")
end

local function clearScreen()
    gpu.fill(1, 1, rx, ry, " ")
end

local function menu(label, strs, funcs, withoutBackButton, refresh)
    local selected = 1

    if not withoutBackButton then
        table.insert(strs, "Back")
    end

    local function redraw()
        clearScreen()
        invertColor()
        centerPrint(2, label)
        invertColor()

        for i, str in ipairs(strs) do
            if i == selected then
                invertColor()
                screenFill(3 + i)
            end
            centerPrint(3 + i, str)
            if i == selected then invertColor() end
        end
    end
    redraw()

    while true do
        local eventData = {computer.pullSignal()}
        if eventData[1] == "key_down" and eventData[2] == keyboard then
            if eventData[4] == 28 then
                if funcs[selected] then
                    if funcs[selected](strs[selected], eventData[5]) then
                        break
                    else
                        if refresh then
                            local lstrs, lfuncs = refresh()
                            if not withoutBackButton then
                                table.insert(lstrs, "Back")
                            end
                            strs = lstrs
                            funcs = lfuncs
                        end
                        redraw()
                    end
                else
                    break
                end
            elseif eventData[4] == 200 then
                selected = selected - 1
                if selected < 1 then
                    selected = 1
                else 
                    redraw()
                end
            elseif eventData[4] == 208 then
                selected = selected + 1
                if selected > #strs then
                    selected = #strs
                else
                    redraw()
                end
            end
        end
    end
end

local function info(strs, withoutWaitEnter)
    clearScreen()

    if type(strs) ~= "table" then
        strs = {strs}
    end

    if not withoutWaitEnter then
        table.insert(strs, "Press Enter To Continue")
    end
    for i, str in ipairs(strs) do
        centerPrint((centerY + (i - 1)) - math.floor((#strs / 2) + 0.5), str)
    end
    
    while not withoutWaitEnter do
        local eventData = {computer.pullSignal()}
        if eventData[1] == "key_down" and eventData[2] == keyboard then
            if eventData[4] == 28 then
                break
            end
        end
    end
end

local function input(str)
    
end

local function raw_selectfile(proxy, folder)
    folder = folder or "/"

    local rpath, rname
    local files = {}
    local funcs = {}
    local list = proxy.list(folder)
    table.sort(list)
    for _, filename in ipairs(list) do
        local path = folder .. filename
        table.insert(files, filename)
        table.insert(funcs, function (_, nickname)
            if proxy.isDirectory(path) then
                rpath, rname = raw_selectfile(proxy, path)
                if rpath then
                    return true
                end
            else
                rpath, rname = path, nickname
                return true
            end
        end)
    end

    menu("Select A File: " .. proxy.address:sub(1, 4) .. "-" .. folder, files, funcs)
    return rpath, rname
end

local function selectFilesystem(callback)
    local files, funcs = {}, {}
    local added = {}
    local function add(addr, label)
        if added[addr] then return end
        added[addr] = true
        table.insert(files, addr:sub(1, 4) .. " " .. (component.invoke(addr, "getLabel") or "no-label") .. (label and (" " .. label) or ""))
        table.insert(funcs, function ()
            return callback(component.proxy(addr))
        end)
    end
    add(bootloader.bootaddress, "(system)")
    add(bootloader.tmpaddress, "(tmp)")
    for addr in component.list("filesystem", true) do
        add(addr)
    end
    menu("Select A Drive", files, funcs)
end

local function selectfile()
    local rpath, rproxy, rname
    selectFilesystem(function (proxy)
        rpath, rname = raw_selectfile(proxy)
        if rpath then
            rproxy = proxy
            return true
        end
    end)
    return rpath, rproxy, rname
end

local function loadfile(fs, path, mode, env)
    local data, err = bootloader.readFile(fs, path)
    if not data then return nil, err end
    return load(data, "=" .. path, mode or "bt", env or _G)
end

-------------------------------------------------------------- micro programs

local function micro_userControl(str)
    local function refresh()
        local strs = {"Add User", "Auto User Add"}
        local function add(nickname)
            if nickname then
                local ok, err = computer.addUser(nickname)
                if not ok then
                    info(err or "Unknown Error")
                end
            end
        end
        local funcs = {function ()
            add(input("Enter Nickname> "))
        end, function (_, nickname)
            add(nickname)
        end}
        for _, nickname in ipairs({computer.users()}) do
            table.insert(strs, nickname)
            table.insert(funcs, function ()
                local ok, err = computer.removeUser(nickname)
                if not ok then
                    info(err or "Unknown Error")
                end
            end)
        end
        return strs, funcs
    end
    local strs, funcs = refresh()
    menu(str, strs, funcs, nil, refresh)
end

local function micro_robotMoving(str)
    local robot = component.proxy(component.list("robot")() or "")
    if not robot then
        info("This Program Only Works On The Robot")
        return
    end

    clearScreen()
    centerPrint(centerY - 1, "WASD - control")
    centerPrint(centerY, "space/shift - up/down")
    centerPrint(centerY + 1, "enter - exit")

    while true do
        local eventData = {computer.pullSignal()}
        if eventData[1] == "key_down" and eventData[2] == keyboard then
            if eventData[4] == 28 then
                break
            elseif eventData[4] == 17 then
                robot.move(3)
            elseif eventData[4] == 31 then
                robot.move(2)
            elseif eventData[4] == 30 then
                robot.turn(false)
            elseif eventData[4] == 32 then
                robot.turn(true)
            elseif eventData[4] == 57 then
                robot.move(1)
            elseif eventData[4] == 42 then
                robot.move(0)
            end
        end
    end
end

local function micro_microprograms(str)
    menu(str, 
        {
            "User Control",
            "Robot Moving"
        },
        {
            micro_userControl,
            micro_robotMoving
        }
    )
end

-------------------------------------------------------------- sandbox

local recoveryApi = {
    getDeviceType = getDeviceType,
    centerPrint = centerPrint,
    invertColor = invertColor,
    screenFill = screenFill,
    clearScreen = clearScreen,
    menu = menu,
    info = info,
    input = input,
    raw_selectfile = raw_selectfile,
    selectFilesystem = selectFilesystem,
    selectfile = selectfile,
    loadfile = loadfile
}

local function createSandbox()
    local env = bootloader.createEnv()
    env.bootloader = bootloader
    env.recoveryApi = recoveryApi
    return env
end

-- проверка доступа к recovery
local path = bootloader.find("recoveryAccess.lua")
if path then
    local code, err = bootloader.loadfile(path, nil, createSandbox())
    if code then
        code()
    else
        info(err or "Unknown Syntax Error")
    end
end

-------------------------------------------------------------- menu

menu(bootloader.coreversion .. " recovery",
    {
        "Run System Recovery Script",
        "Wipe Data / Factory Reset",
        "Run Script From Url",
        "Run Script From Disk",
        "Micro Programs",
        "Bootstrap",
        "Shutdown",
        "Info",
    }, 
    {
        function ()
            local path = bootloader.find("recoveryScript.lua") --скрипт востановления системы, у каждой оськи на базе likeOS должен быть
            if path then
                local code, err = bootloader.loadfile(path, nil, createSandbox())
                if code then
                    code()
                else
                    info(err or "Unknown Syntax Error")
                end
            else
                info("The System Does Not Provide A Script For Recovery")
            end
        end,
        function (str)
            menu(str,
                {
                    "No",
                    "No",
                    "No",
                    "No",
                    "No",
                    "No",
                    "Yes",
                    "No",
                    "No",
                    "No"
                },
                {
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    function ()
                        local result = {bootloader.bootfs.remove("/data")}
                        if not result[1] then
                            info(result[2] or "No Data Partition Found")
                        else
                            info("Data Successfully Wiped")
                        end
                        return true
                    end
                },
                true
            )
        end,
        function ()
            
        end,
        function ()
            local path, proxy, nickname = selectfile()
            if path then
                local code, err = loadfile(proxy, path, nil, createSandbox())
                if code then
                    local ok, err = pcall(code, screen, nickname)
                    if not ok then
                        info({"Script Error", err})
                    end
                else
                    info({"Script Error(syntax)", err})
                end
            end
        end,
        micro_microprograms,
        function ()
            info({"Initializing The Kernel", "Please Wait"}, true)
            local result = "Successful Kernel Initialization"
            local ok, err = pcall(bootloader.bootstrap)
            if not ok then
                result = tostring(err or "Unknown Error")
            end
            info(result)
        end,
        function (str)
            menu(str,
                {
                    "Shutdown",
                    "Reboot",
                    "Fast Reboot",
                    "Reboot To Bios",
                },
                {
                    function ()
                        computer.shutdown()
                    end,
                    function ()
                        computer.shutdown(true)
                    end,
                    function ()
                        computer.shutdown("fast") --поддерживаеться малым количеством bios`ов(по сути только моими)
                    end,
                    function ()
                        computer.shutdown("bios") --поддерживаеться малым количеством bios`ов(по сути только моими)
                    end
                }
            )
        end,
        function ()
            local deviceType = getDeviceType()
            local function short(str)
                str = tostring(str)
                if rx <= 50 then
                    return str:sub(1, 8)
                end
                return str
            end

            local ramSize = tostring(math.floor((computer.totalMemory() / 1024) + 0.5)) .. "KB"
            ramSize = ramSize .. " / " .. tostring(math.floor(((computer.totalMemory() - computer.freeMemory()) / 1024) + 0.5)) .. "KB"

            local hddSize = tostring(math.floor((bootloader.bootfs.spaceTotal() / 1024) + 0.5)) .. "KB"
            hddSize = hddSize .. " / " .. tostring(math.floor((bootloader.bootfs.spaceUsed() / 1024) + 0.5)) .. "KB"

            local computerAddr = short(computer.address())
            
            info(
                {
                    "Computer Address: " .. computerAddr,
                    "Disk     Address: " .. short(bootloader.bootfs.address),
                    "Device      Type: " .. short(deviceType .. string.rep(" ", #computerAddr - #deviceType)),
                    "System  Runlevel: " .. short(bootloader.runlevel .. string.rep(" ", #computerAddr - #bootloader.runlevel)),
                    "Total/Used   RAM: " .. ramSize .. string.rep(" ", #computerAddr - #ramSize),
                    "Total/Used   HDD: " .. hddSize .. string.rep(" ", #computerAddr - #hddSize)
                }
            )
        end,
    }
)