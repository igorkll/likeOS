local fs = require("filesystem")
local paths = require("paths")
local logs = {}
logs.defaultLogPath = "/data/errorlog.log"
logs.timeZone = 0

function logs.timetag()
    local time = require("time")
    return time.formatTime(time.addTimeZone(time.getRealTime(), logs.timeZone), true, true)
end

function logs.log(logdata, tag, path)
    path = path or logs.defaultLogPath
    fs.makeDirectory(paths.path(path))

    local file = assert(fs.open(path, "ab"))
    assert(file.write(logs.timetag() .. (tag and (" \"" .. tag .. "\"") or "") .. ": " .. tostring(logdata or "unknown error") .. "\n"))
    file.close()
end

function logs.logs(logsdata, tag, path)
    path = path or logs.defaultLogPath
    fs.makeDirectory(paths.path(path))

    local timetag = logs.timetag()
    local file = assert(fs.open(path, "ab", true))
    for i, logdata in ipairs(logsdata) do
        assert(file.write(timetag .. (tag and (" \"" .. tag .. "\"") or "") .. ": " .. tostring(logdata or "unknown error") .. "\n"))
    end
    file.close()
end

function logs.assert(ok, err)
    if not ok then
        logs.log(err)
    end
end

function logs.check(...)
    local ok, err = ...
    if not ok then
        logs.log(err)
    end
    return ...
end

logs.unloadable = true
return logs