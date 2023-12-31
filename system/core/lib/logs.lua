local fs = require("filesystem")
local logs = {}
logs.defaultLogPath = "/data/errorlog.log"
logs.timeZone = 0

function logs.timetag()
    local time = require("time")
    return time.formatTime(time.addTimeZone(time.getRealTime(), logs.timeZone), true, true)
end

function logs.log(logdata, tag, path)
    fs.makeDirectory("/data")
    local file = assert(fs.open(path or logs.defaultLogPath, "ab"))
    assert(file.write(logs.timetag() .. (tag and (" \"" .. tag .. "\"") or "") .. ": " .. tostring(logdata or "unknown error") .. "\n"))
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