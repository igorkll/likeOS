local fs = require("filesystem")
local logs = {}

function logs.log(logdata)
    local time = require("time")
    local timetag = time.formatTime(time.getRealTime(), true, true)

    fs.makeDirectory("/data")
    local file = assert(fs.open("/data/errorlog.log", "ab"))
    assert(file.write(timetag .. ": " .. tostring(logdata or "unknown error") .. "\n"))
    file.close()
end

function logs.assert(ok, err)
    if not ok then
        logs.log(err)
    end
end

logs.unloadable = true
return logs