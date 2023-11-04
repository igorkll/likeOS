--likeOS classic bootloader

-------------------------------------- initialization

do
    if not bit32 then --на lua 5.3 нет встроеной либы bit32, но она нужна для совместимости, так что хай будет
        _G.bit32 = bootloader.dofile("/system/core/lib/bit32.lua", bootloader.createEnv())
    end
    bootloader.dofile("/system/core/boot/a_functions.lua", _G) --загружаю зарания, так как это нужно для инициализации natives
    _G.natives = bootloader.dofile("/system/core/lib/natives.lua", bootloader.createEnv()) --natives позваляет получить доступ к нетронутым методами библиотек computer и component

    do --бут скрипты, тут инициализации всего и вся
        local path = "/system/core/boot/"
        for i, v in ipairs(bootfs.list(path) or {}) do
            bootloader.dofile(path .. v, _G)
        end
    end

    bootloader.dofile("/system/core/lib/package.lua", bootloader.createEnv()) --package инициализирует библиотеки

    _G.computer = nil
    _G.component = nil
    _G.unicode = nil
    _G.natives = nil

    require("event")
    require("system")
end

-------------------------------------- unittests

do
    local fs = require("filesystem")
    local paths = require("paths")
    local programs = require("programs")

    function bootloader.unittests(path, ...) --доступно глобально
        for _, file in ipairs(fs.list(path)) do
            local lpath = paths.concat(path, file)
            local ok, state, log = assert(programs.execute(lpath, ...))
            if not ok then
                error("error \"" .. (state or "unknown error") .. "\" in unittest: " .. file, 0)
            elseif not state then
                error("warning unittest \"" .. file .. "\" \"" .. (log and (", log:\n" .. log) or "") .. "\"", 0)
            end
        end
    end
    bootloader.unittests("/system/core/unittests")
    bootloader.unittests("/system/unittests")
    --unittests("/vendor/unittests") --дабовляйте сами в свой дистрибутив при необходимости(так как может быть необходим запуск после инициализации)
    --unittests("/data/unittests") --дабовляйте сами в свой дистрибутив при необходимости(так как может быть необходим запуск после инициализации)
end

-------------------------------------- используйте автозагрузку для программ выполняешихся быстно, и не требуюших взаимодействий

do
    local fs = require("filesystem")
    local paths = require("paths")
    local event = require("event")
    local programs = require("programs")

    function bootloader.autorunsIn(path, ...) --доступно глобально
        for i, v in ipairs(fs.list(path)) do
            local full_path = paths.concat(path, v)
    
            local func, err = programs.load(full_path)
            if not func then
                event.errLog("err \"" .. (err or "unknown error") .. "\", to load program: " .. full_path)
            else
                local ok, err = pcall(func, ...)
                if not ok then
                    event.errLog("err \"" .. (err or "unknown error") .. "\", in program: " .. full_path)
                end
            end        
        end
    end
    bootloader.autorunsIn("/system/core/luaenv")
    bootloader.autorunsIn("/system/core/autoruns")
    bootloader.autorunsIn("/system/autoruns")
    --autorunsIn("/vendor/autoruns") --дабовляйте сами в свой дистрибутив при необходимости(так как может быть необходим запуск после инициализации)
    --autorunsIn("/data/autoruns") --дабовляйте сами в свой дистрибутив при необходимости(так как может быть необходим запуск после инициализации)
end

--------------------------------------используйте main.lua для запуска оболочьки, или основной программы

bootloader.bootSplash("Running main.lua...")
if require("filesystem").exists("/system/main.lua") then
    local code, err = require("programs").load("/system/main.lua")
    if not code then
        error("failed to loading main.lua" .. err, 0)
    end
    code()
else
    bootloader.bootSplash("main.lua does not exist. press enter to continue")
    bootloader.waitEnter()
end