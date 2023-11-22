local computer = require("computer")
local fs = require("filesystem")
local package = require("package")

------------------------------------

--raw_computer_pullSignal насамом деле некакой не raw и уже несколько раз хукнут в boot скриптах
local raw_computer_pullSignal = computer.pullSignal

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

event.minTime = 0 --минимальное время прирывания, можно увеличить, это вызовет подения производительности но уменьшет энергопотребления
event.listens = {}

------------------------------------------------------------------------

function event.errLog(data)
    require("logs").log(data)
end

function event.sleep(waitTime)
    waitTime = waitTime or 0.1

    local startTime = computer.uptime()
    repeat
        computer.pullSignal(waitTime - (computer.uptime() - startTime))
    until computer.uptime() - startTime >= waitTime
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

function event.listen(eventType, func, th)
    checkArg(1, eventType, "string", "nil")
    checkArg(2, func, "function")
    return tableInsert(event.listens, {th = th, eventType = eventType, func = func, type = "l"}) --нет класический table.insert не подайдет, так как он не дает понять, нуда вставил значения
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

function event.timer(time, func, times, th)
    checkArg(1, time, "number")
    checkArg(2, func, "function")
    checkArg(3, times, "number", "nil")
    return tableInsert(event.listens, {th = th, time = time, func = func, times = times or 1,
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

function event.pull(waitTime, ...) --реализует фильтер
    local filters = table.pack(...)

    if type(waitTime) == "string" then
        table.insert(filters, 1, waitTime)
        filters.n = filters.n + 1
        waitTime = math.huge
    elseif not waitTime then
        waitTime = math.huge
    end

    if #filters == 0 then
        return computer.pullSignal(waitTime)
    end
    
    local startTime = computer.uptime()
    while true do
        local ltime = waitTime - (computer.uptime() - startTime)
        if ltime <= 0 then break end
        local eventData = {computer.pullSignal(ltime)}

        local ok = true
        for i = 1, filters.n do
            local value = filters[i]
            if value and value ~= eventData[i] then
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
                v:status()
                if v.dead or not v.thread or coroutine.status(v.thread) == "dead" then
                    table.remove(parsetbl, i)
                    v.thread = nil
                    v.dead = true
                elseif v.enable then --если поток спит или умер то его потомки так-же не будут работать
                    v.out = {thread.xpcall(v.thread, table.unpack(v.args or eventData))}
                    if not v.out[1] then
                        event.errLog("thread error: " .. tostring(v.out[2] or "unknown") .. "\n" .. tostring(v.out[3] or "unknown"))
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
    local current
    if thread then
        current = thread.current()
    end

    local startTime = computer.uptime()
    while true do
        local realWaitTime = waitTime - (computer.uptime() - startTime)
        local isEnd = realWaitTime <= 0

        if thread then
            realWaitTime = event.minTime
        else
            --поиск времени до первого таймера, что обязательно на него успеть
            for k, v in pairs(event.listens) do --нет ipairs неподайдет, так могут быть дырки
                if v.type == "t" and not v.killed and v.th == current then
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

        local eventData
        if not current then
            eventData = {raw_computer_pullSignal(realWaitTime)} --обязательно повисеть в pullSignal
            if not event.isListen then
                runThreads(eventData)
            end
        else
            eventData = {coroutine.yield()}
        end

        for k, v in pairs(event.listens) do --таймеры. нет ipairs неподайдет, там могуть быть дырки
            if v.type == "t" and not v.killed and v.th == current then
                if not v.th or v.th:status() == "running" then
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
                elseif v.th:status() == "dead" then
                    event.listens[k] = nil
                end
            end
        end

        if #eventData > 0 then
            for k, v in pairs(event.listens) do --слушатели. нет ipairs неподайдет, так могут быть дырки
                if v.type == "l" and not v.killed and v.th == current then
                    if not v.th or v.th:status() == "running" then
                        if not v.eventType or v.eventType == eventData[1] then
                            runCallback(false, v.func, k, table.unpack(eventData))
                        end
                    elseif v.th:status() == "dead" then
                        event.listens[k] = nil
                    end
                end
            end
            return table.unpack(eventData)
        end

        if isEnd then
            break
        end
    end
end

return event