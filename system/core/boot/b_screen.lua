local shutdown = computer.shutdown
local list = component.list --учитываються только реальные компаненты, так как скрипт выполняеться до загрузки vcomponent, а методы кешируються
local proxy = component.proxy

function computer.shutdown(mode) --очистка экранов при выключении компьютера
    pcall(function()
        local gpu = proxy(list("gpu")() or "")
        for screen in list("screen") do
            if gpu.getScreen() ~= screen then
                gpu.bind(screen, false)
            end
            if gpu.setActiveBuffer then
                gpu.setActiveBuffer(0)
            end
            gpu.setDepth(1)
            gpu.setDepth(gpu.maxDepth())
            gpu.setResolution(50, 16)
            gpu.setBackground(0)
            gpu.setForeground(0xFFFFFF)
            gpu.fill(1, 1, 50, 16, " ")
        end
    end)
    shutdown(mode)
end