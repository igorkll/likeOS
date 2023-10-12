local vec = {}

function vec:len()
    
end

function vec.vec3(x, y, z)
    local vec3 = setmetatable({__index = vec}, {
        __add = function (a, b)
            return vec.vec3(a.x + b.x, a.y + b.y, a.z + b.z)
        end,
        __sub = function (a, b)
            return vec.vec3(a.x - b.x, a.y - b.y, a.z - b.z)
        end,
        __mul = function (a, b)
            return vec.vec3(a.x * b.x, a.y * b.y, a.z * b.z)
        end,
        __div = function (a, b)
            return vec.vec3(a.x / b.x, a.y / b.y, a.z / b.z)
        end,
        __eq = function (a, b)
            return a.x == b.x and a.y == b.y and a.z == b.z
        end
    })
    vec3.x = x
    vec3.y = y
    vec3.z = z

    return vec3
end

function vec.vec2(x, y)
    
end

vec.unloadable = true
return vec