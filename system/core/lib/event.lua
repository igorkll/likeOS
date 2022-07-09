local computer = require("computer")
local fs = require("filesystem")
local package = require("package")

------------------------------------

local raw_computer_pullSignal = computer.pullSignal
local computer_pullSignal = function(time)
    if package.loaded.thread then
        local inTime = computer.uptime()
        repeat
            local eventData = {coroutine.yield()}
            if #eventData > 0 then
                return table.unpack(eventData)
            end
        until computer.uptime() - inTime > time
    else
        return raw_computer_pullSignal(time)
    end
end

local event = {}
event.listens = {}
event.interruptFlag = false

------------------------------------

function event.tmpLog(data)
    local file = assert(fs.open("/tmp/tmplog.log", "ab"))
    file.write(data .. "\n")
    file.close()
end

function event.sleep(time)
    local inTime = computer.uptime()
    repeat
        computer.pullSignal(time - (computer.uptime() - inTime))
    until computer.uptime() - inTime > time
end

function event.listen(eventType, func)
    checkArg(1, eventType, "string", "nil")
    checkArg(2, func, "function")
    table.insert(event.listens, {eventType = eventType, func = func, type = "l"})
    return #event.listens
end

function event.timer(time, func, times)
    checkArg(1, time, "number")
    checkArg(2, func, "function")
    checkArg(3, times, "number", "nil")
    table.insert(event.listens, {time = time, func = func, times = times or 1,
    type = "t", lastTime = computer.uptime()})
    return #event.listens
end

function event.cancel(num)
    event.listens[num] = nil
end

function event.callThreads(eventData)
    local thread = package.loaded.thread
    if thread then
        local function find(tbl)
            local parsetbl = tbl.childs
            if not parsetbl then parsetbl = tbl end
            for i = #parsetbl, 1, -1 do
                local v = parsetbl[i]
                if not v.thread then
                    table.remove(parsetbl, i)
                else
                    --computer.beep(2000, 0.1)
                    assert(coroutine.resume(v.thread, table.unpack(v.args or eventData)))
                    v.args = nil
                    find(v)
                end
            end
        end
        find(thread.threads)
    end
end

function computer.pullSignal(time)
    if event.interruptFlag then
        event.interruptFlag = false
        error("interrupted", 0)
    end
    time = time or math.huge
    
    local thread = package.loaded.thread
    if thread then
        local current = thread.current()
        if current then
            return computer_pullSignal(time)
        end
    end
    
    local inTime = computer.uptime()
    while true do
        local ltime = time - (computer.uptime() - inTime)
        if ltime <= 0 then return end
        local realtime = ltime

        --поиск времени до первого таймера, что обязательно на него успеть
        for k, v in pairs(event.listens) do --нет ipairs неподайдет
            if v.type == "t" then
                local timerTime = v.time - (computer.uptime() - v.lastTime)
                if timerTime < realtime then
                    realtime = timerTime
                end
            end
        end

        local eventData = {computer_pullSignal(realtime)} --обязательно повисеть в pullSignal
        event.callThreads(eventData)

        local function runCallback(func, index, ...)
            local ok, err = pcall(func, ...)
            if ok then
                if err == false then --таймер/слушатель хочет отключиться
                    event.listens[index] = nil
                end
            else
                event.tmpLog((err or "unknown error") .. "\n")
            end
        end

        for k, v in pairs(event.listens) do --нет ipairs неподайдет
            if v.type == "t" then
                local uptime = computer.uptime() 
                if uptime - v.lastTime >= v.time then
                    v.lastTime = uptime --ДО выполнения функции ресатаем таймер, чтобы тайминги не поплывали при долгих функциях
                    if v.times <= 0 then
                        event.listens[k] = nil
                    else
                        runCallback(v.func, k)
                        v.times = v.times - 1
                        if v.times <= 0 then
                            event.listens[k] = nil
                        end
                    end
                end
            end
        end

        if #eventData > 0 then
            for k, v in pairs(event.listens) do
                if v.type == "l" then
                    if not v.eventType or v.eventType == eventData[1] then
                        runCallback(v.func, k, table.unpack(eventData))
                    end
                end
            end
            return table.unpack(eventData)
        end
    end
end

event.push = computer.pushSignal

function event.pull()
    
end
event.pull = computer.pullSignal

event.timer(0.1, function()
    
end, math.huge)

return event