-- This module simulates OpenOS's thread library.
-- Under the hood, our simulated threads are really just coroutines that yield on blocking calls.
---@class Thread
local M = {}

---@class ThreadHandle
---@field __thread thread the underlying coroutine
local Handle = {}

Coroutine = require("coroutine")
Luaunit = require("Test.luaunit")

Modem = require("Test.SimulatorModules.Component.Modem")

---@param func fun()
---@return ThreadHandle
function M.create(func)
    local parentThread = Coroutine.running()
    local childThread = Coroutine.create(function ()
        -- Child threads should inherit the ability to access the modem port.
        for port, subscribers in pairs(Modem.__openPorts) do
            for _, openThread in ipairs(subscribers) do
                if openThread == parentThread then
                    Modem.open(port)
                end
            end
        end
        Coroutine.yield("startup success")
        func()
    end)

    local ran, response = Coroutine.resume(childThread)
    Luaunit.assertIsTrue(ran)
    Luaunit.assertEquals(response, "startup success")

    return Handle:__Create(childThread)
end

---@param child thread
---@return ThreadHandle
function Handle:__Create(child)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.__thread = child

    return obj
end

return M
