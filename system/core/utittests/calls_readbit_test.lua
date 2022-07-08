local calls = require("calls")
local readbit = calls.load("readbit")

local values = {
    {
        [0] = 0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 255,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1
    },
    {
        [0] = 1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 2,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 3,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 4,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 5,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 6,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        0
    },
    {
        [0] = 127,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        0
    },
}

local okcount = 0

for i, v in ipairs(values) do
    
end

return okcount == #values