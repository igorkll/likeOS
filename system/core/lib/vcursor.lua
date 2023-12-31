local lastinfo = require("lastinfo")
local utils = require("utils")
local event = require("event")
local graphic = require("graphic")
local vcursor = {}
local hooked = {}
local enabled = {}

function vcursor.hook(screen)
    if hooked[screen] then return false end
    hooked[screen] = true

    local active = false
    local pressed1 = false
    local pressed2 = false
    local posx, posy = 1, 1

    local function invertPos(x, y)
        local char, fore, back = graphic.get(screen, x or posx, y or posy)
        if char then
            graphic.set(screen, x or posx, y or posy, 0xffffff - back, 0xffffff - fore, char)
        end
    end

    event.hyperHook(function (...)
        local eventData = {...}

        return utils.safeExec(function ()
            if not enabled[screen] then
                if active then
                    invertPos()
                end
                active = false
                return
            end

            if (eventData[1] == "key_down" or eventData[1] == "key_up") and table.exists(lastinfo.keyboards[screen], eventData[2]) then
                if eventData[3] == 0 and eventData[4] == 56 then
                    if eventData[1] == "key_down" then
                        active = true
                        invertPos()
                    else
                        active = false
                        pressed1 = false
                        pressed2 = false
                        invertPos()
                    end
                end

                if active then
                    if eventData[1] == "key_down" then
                        local rx, ry = graphic.getResolution(screen)
                        local newposx, newposy = posx, posy
                        local cursorMove, cursorAction = false, false

                        if eventData[4] == 17 then
                            cursorMove = true
                            newposy = newposy - 1
                            if newposy < 1 then newposy = 1 end
                        elseif eventData[4] == 31 then
                            cursorMove = true
                            newposy = newposy + 1
                            if newposy > ry then newposy = ry end
                        elseif eventData[4] == 30 then
                            cursorMove = true
                            newposx = newposx - 1
                            if newposx < 1 then newposx = 1 end
                        elseif eventData[4] == 32 then
                            cursorMove = true
                            newposx = newposx + 1
                            if newposx > rx then newposx = rx end
                        elseif eventData[4] == 16 then
                            cursorAction = true
                            if not pressed1 then
                                event.push("touch", screen, posx, posy, 0, eventData[5])
                            end
                            pressed1 = true
                        elseif eventData[4] == 18 then
                            cursorAction = true
                            if not pressed2 then
                                event.push("touch", screen, posx, posy, 1, eventData[5])
                            end
                            pressed2 = true
                        end

                        if newposx ~= posx or newposy ~= posy then
                            invertPos()
                            posx, posy = newposx, newposy
                            invertPos()

                            if cursorMove then
                                if pressed1 then
                                    event.push("drag", screen, posx, posy, 0, eventData[5])
                                end
            
                                if pressed2 then
                                    event.push("drag", screen, posx, posy, 1, eventData[5])
                                end
                            end
                        end

                        if cursorMove or cursorAction then
                            eventData[1] = "vcursor_" .. eventData[1]
                        end
                    elseif eventData[1] == "key_up" then
                        if eventData[4] == 16 then
                            if pressed1 then
                                event.push("drop", screen, posx, posy, 0, eventData[5])
                            end
                            pressed1 = false
                        elseif eventData[4] == 18 then
                            if pressed2 then
                                event.push("drop", screen, posx, posy, 1, eventData[5])
                            end
                            pressed2 = false
                        end
                    end
                else
                    if pressed1 then
                        event.push("drop", screen, posx, posy, 0, eventData[5])
                    end

                    if pressed2 then
                        event.push("drop", screen, posx, posy, 1, eventData[5])
                    end
                    
                    pressed1 = false
                    pressed2 = false
                end
            end

            return table.unpack(eventData)
        end, eventData, "vcursor error")
    end)

    return true
end

function vcursor.setEnable(screen, state)
    enabled[screen] = state
end

return vcursor