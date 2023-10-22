local computer = require("computer")
local fs = require("filesystem")
local package = require("package")

------------------------------------

--raw_computer_pullSignal насамом деле некакой не raw и уже несколько раз хукнут в boot скриптах
local raw_computer_pullSignal = computer.pullSignal
local thread_computer_pullSignal = function(time)
    if not time then time = math.huge end
    local inTime = computer.uptime()
    repeat
        local eventData = {coroutine.yield()}
        if #eventData > 0 then
            return table.unpack(eventData)
        end
    until computer.uptime() - inTime > time
end

local function tableInsert(tbl, value) --кастомный insert с возвращения значения
    for i = 1, #tbl + 1 do
        if not tbl[i] then
            tbl[i] = value
            return i
        end
    end
end

local event = {push = computer.pushSignal}
event.isListen = false --если текуший код timer/listen

event.minTime = 0.01 --минимальное время прирывания, можно увеличить, это вызовет подения производительности но уменьшет энергопотребления
event.listens = {}

event.allowInterrupt = true
event.interruptFlag = nil --вы можете записать сюда true чтобы вызвать прирывания, или обьект патока чтобы кильнуть только его
event.interruptFunc = nil

------------------------------------------------------------------------

function event.errLog(data)
    fs.makeDirectory("/data")
    local file = assert(fs.open("/data/errorlog.log", "ab"))
    assert(file.write(data .. "\n"))
    file.close()
end

function event.sleep(waitTime)
    waitTime = waitTime or 0.1

    local inTime = computer.uptime()
    repeat
        computer.pullSignal(waitTime - (computer.uptime() - inTime))
    until computer.uptime() - inTime >= waitTime
end
os.sleep = event.sleep

function event.yield()
    computer.pullSignal(event.minTime)
end

function event.events(timeout, types, maxcount) --получает эвенты пока сыпуться
    timeout = timeout or 0.1
    local eventList = {}
    local lastEventTime = computer.uptime()
    while true do
        local ctime = computer.uptime()
        local eventData = {computer.pullSignal(timeout)}
        if #eventData > 0 and (not types or types[eventData[1]]) then
            lastEventTime = ctime
            table.insert(eventList, eventData)
            if maxcount and #eventList >= maxcount then
                break
            end
        elseif ctime - lastEventTime > timeout then
            break
        end
    end
    return eventList
end

function event.wait() --ждать то тех пор пока твой поток не убьют
    event.sleep(math.huge)
end

function event.listen(eventType, func)
    checkArg(1, eventType, "string", "nil")
    checkArg(2, func, "function")
    return tableInsert(event.listens, {eventType = eventType, func = func, type = "l"}) --нет класический table.insert не подайдет, так как он не дает понять, нуда вставил значения
end

--имеет самый самый высокий приоритет из возможных
--не может быть как либо удален до перезагрузки
--вызываеться при каждом завершении pullSignal даже если события не пришло
--ошибки в функции переданой в hyperListen будут переданы в вызвавщий pullSignal
function event.hyperListen(func)
    checkArg(1, func, "function")
    local pullSignal = raw_computer_pullSignal
    local unpack = table.unpack
    raw_computer_pullSignal = function (time)
        local eventData = {pullSignal(time)}
        func(unpack(eventData))
        return unpack(eventData)
    end
end

function event.hyperTimer(func)
    checkArg(1, func, "function")
    local pullSignal = raw_computer_pullSignal
    raw_computer_pullSignal = function (time)
        func()
        return pullSignal(time)
    end
end

function event.hyperHook(func)
    checkArg(1, func, "function")
    local pullSignal = raw_computer_pullSignal
    raw_computer_pullSignal = function (time)
        return func(pullSignal(time))
    end
end

function event.timer(time, func, times)
    checkArg(1, time, "number")
    checkArg(2, func, "function")
    checkArg(3, times, "number", "nil")
    return tableInsert(event.listens, {time = time, func = func, times = times or 1,
    type = "t", lastTime = computer.uptime()})
end

function event.cancel(num)
    checkArg(1, num, "number")

    local ok = not not event.listens[num]
    if ok then
        event.listens[num].killed = true
        event.listens[num] = nil
    end
    return ok
end

function event.pull(waitTime, ...) --добавляет фильтер
    local filters = {...}

    if #filters == 0 then
        return computer.pullSignal(waitTime)
    end

    if type(waitTime) == "string" then
        table.insert(filters, 1, waitTime)
        waitTime = math.huge
    elseif not waitTime then
        waitTime = math.huge
    end
    
    local inTime = computer.uptime()
    while true do
        local ltime = waitTime - (computer.uptime() - inTime)
        if ltime <= 0 then break end
        local eventData = {computer.pullSignal(ltime)}

        local ok = true
        for i, v in ipairs(filters) do
            if v ~= eventData[i] then
                ok = false
                break
            end
        end

        if ok then
            return table.unpack(eventData)
        end
    end
end

------------------------------------------------------------------------

local function runThreads(eventData)
    local thread = package.get("thread")
    if thread then
        local function find(tbl)
            local parsetbl = tbl.childs
            if not parsetbl then parsetbl = tbl end
            for i = #parsetbl, 1, -1 do
                local v = parsetbl[i]
                if v.dead or not v.thread or coroutine.status(v.thread) == "dead" then
                    table.remove(parsetbl, i)
                    v.thread = nil
                    v.dead = true
                elseif not v.dead and v.enable then --если поток спит или умер то его потомки так-же не будут работать
                    v.out = {thread.xpcall(v.thread, table.unpack(v.args or eventData))}
                    if not v.out[1] then
                        event.errLog("thread error: " .. tostring(v.out[2] or "unknown") .. " " .. tostring(v.out[3] or "unknown"))
                    end

                    v.args = nil
                    find(v)
                end
            end
        end
        find(thread.threads)
    end
end

local function runCallback(isTimer, func, index, ...)
    local oldState = event.isListen
    event.isListen = true
    local ok, err = xpcall(func, debug.traceback, ...)
    event.isListen = oldState
    if ok then
        if err == false then --таймер/слушатель хочет отключиться
            event.listens[index] = nil
        end
    else
        event.errLog((isTimer and "timer" or "listen") .. " error: " .. tostring(err or "unknown"))
    end
end

function computer.pullSignal(waitTime) --кастомный pullSignal для работы background процессов
    waitTime = waitTime or math.huge
    if waitTime < event.minTime then
        waitTime = event.minTime
    end

    local thread = package.get("thread")

    --само ядро не поднимает event.interruptFlag, это могут делать дистрибутивы для прирывания процессов
    --вы можете записать туда true и убить первый попавшийся на пути поток, а можете записать туда обьект патока, чтобы убить что-то конкретное
    if event.allowInterrupt and event.interruptFlag then
        local interrupt = event.interruptFlag == true
        if not interrupt and thread then
            local current = thread.current()
            if current and event.interruptFlag == current then
                interrupt = true
            end
        end
        if interrupt then
            event.interruptFlag = nil
            if event.interruptFunc then
                event.interruptFunc()
            else
                error("interrupted", 0)
            end
        end
    end

    --pullSignal для патоков
    if thread and thread.current() then
        return thread_computer_pullSignal(waitTime)
    end
    
    --главный pullSignal
    local inTime = computer.uptime()
    while true do
        local realWaitTime = waitTime - (computer.uptime() - inTime)
        if realWaitTime <= 0 then return end

        if thread then
            realWaitTime = event.minTime
        else
            --поиск времени до первого таймера, что обязательно на него успеть
            for k, v in pairs(event.listens) do --нет ipairs неподайдет, так могут быть дырки
                if v.type == "t" and not v.killed then
                    local timerTime = v.time - (computer.uptime() - v.lastTime)
                    if timerTime < realWaitTime then
                        realWaitTime = timerTime
                    end
                end
            end

            if realWaitTime < event.minTime then --если время ожидания получилось меньше минимального времени то ждать минимальное(да таймеры будут плыть)
                realWaitTime = event.minTime
            end
        end

        local eventData = {raw_computer_pullSignal(realWaitTime)} --обязательно повисеть в pullSignal
        if not event.isListen then
            runThreads(eventData)
        end

        for k, v in pairs(event.listens) do --таймеры. нет ipairs неподайдет, там могуть быть дырки
            if v.type == "t" and not v.killed then
                local uptime = computer.uptime() 
                if uptime - v.lastTime >= v.time then
                    v.lastTime = uptime --ДО выполнения функции ресатаем таймер, чтобы тайминги не поплывали при долгих функциях
                    if v.times <= 0 then
                        event.listens[k] = nil
                    else
                        runCallback(true, v.func, k)
                        v.times = v.times - 1
                        if v.times <= 0 then
                            event.listens[k] = nil
                        end
                    end
                end
            end
        end

        if #eventData > 0 then
            for k, v in pairs(event.listens) do --слушатели. нет ipairs неподайдет, так могут быть дырки
                if v.type == "l" and not v.killed then
                    if not v.eventType or v.eventType == eventData[1] then
                        runCallback(false, v.func, k, table.unpack(eventData))
                    end
                end
            end
            return table.unpack(eventData)
        end
    end
end

return event