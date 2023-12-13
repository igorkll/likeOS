local system = require("system")
local thread = {}
thread.threads = {}
thread.mainthread = coroutine.running()

function thread.decode(th)
    if th:status() ~= "dead" then
        error("thread.decode only works with dead thread", 2)
    end

    local out = th.out or {true}
    if out[1] then
        return table.unpack(out)
    else
        return nil, (tostring(out[2]) or "unknown error") .. "\n" .. (tostring(out[3]) or "")
    end
end

function thread.stub(func, ...)
    local event = require("event")

    local th = thread.create(func, ...)
    th:resume()
    
    while th:status() ~= "dead" do
        event.yield()
    end

    return thread.decode(th)
end

function thread.xpcall(co, ...)
    local output = {system.checkExitinfo(coroutine.resume(co, ...))}
    if not output[1] then
        return nil, output[2], debug.traceback(co)
    end
    return table.unpack(output)
end

function thread.current()
    local currentT = coroutine.running()
    local function find(tbl)
        local parsetbl = tbl.childs
        if not parsetbl then parsetbl = tbl end
        for i = #parsetbl, 1, -1 do
            local v = parsetbl[i]
            if v.thread then
                if v.thread == currentT then
                    return v
                else
                    local obj = find(v)
                    if obj then
                        return obj
                    end
                end
            end
        end
    end
    return find(thread.threads)
end

function thread.all()
    local list = {}
    
    local function find(tbl)
        local parsetbl = tbl.childs
        if not parsetbl then parsetbl = tbl end
        for i = #parsetbl, 1, -1 do
            local v = parsetbl[i]
            if v.thread then
                table.insert(list, v)

                local obj = find(v)
                if obj then
                    return obj
                end
            end
        end
    end
    find(thread.threads)

    return list
end

function thread.attachThread(t, obj)
    if obj then
        t.parentData = table.deepclone(obj.parentData)
        t.parent = obj
        if obj.childs then
            table.insert(obj.childs, t)
        else
            table.insert(obj, t)
        end
        return true
    end
    table.insert(thread.threads, t)
    return true
end

local function create(func, ...)
    local t = coroutine.create(func)
    local obj = {
        args = {...},
        childs = {},
        thread = t,
        enable = false,
        raw_kill = raw_kill,
        kill = kill,
        resume = resume,
        suspend = suspend,
        status = status,
        decode = thread.decode,
        parentData = {},

        func = func,
    }
    return obj
end

function thread.create(func, ...)
    local obj = create(func, ...)
    thread.attachThread(obj, thread.current())
    return obj
end

function thread.createBackground(func, ...)
    local obj = create(func, ...)
    thread.attachThread(obj)
    return obj
end

function thread.createTo(func, connectTo, ...)
    local obj = create(func, ...)
    thread.attachThread(obj, connectTo)
    return obj
end

function thread.listen(eventType, func)
    return require("event").listen(eventType, func, thread.current())
end

function thread.timer(time, func, times)
    return require("event").timer(time, func, times, thread.current())
end

local function wait(timeout, forAny, threads)
    while true do
        
    end
end

local function parseWait(forAny, ...)
    local threads = {...}
    local timeout = math.huge
    if type(threads[#threads]) == "number" then
        timeout = threads[#threads]
        table.remove(threads, #threads)
    end
    wait(timeout, forAny, threads)
end

function thread.waitForAll(...)
    local threads = {}
end

------------------------------------thread functions

function raw_kill(t) --не стоит убивать паток через raw_kill
    t.dead = true
    t.enable = false
end

function kill(t) --вы сможете переопределить это в своем потоке, наример чтобы закрыть таймеры
    t:raw_kill()
end

function resume(t)
    t.enable = true
end

function suspend(t)
    t.enable = false
end

function status(t)
    if t.dead or not t.thread or coroutine.status(t.thread) == "dead" then
        t:kill()
        return "dead"
    end
    if t.parent then
        local status = t.parent:status()
        if status == "dead" then
            t:kill()
            return "dead"
        elseif status == "suspended" then
            return "suspended"
        end
    end
    if t.enable then
        return "running"
    else
        return "suspended"
    end
end

return thread