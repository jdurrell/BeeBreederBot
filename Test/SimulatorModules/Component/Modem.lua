-- This is a module that simulates the OpenComputers modem component.
-- It is admittedly a little odd to have asserts embedded directly into the
-- test fixture, but there's not a fantastic better way to test this.

local Coroutine = require("coroutine")
local Luaunit = require("Test.luaunit")

local Event = require("Test.SimulatorModules.Event")

---@class Modem
---@field __openPorts table<integer, thread[]>
local M = {}

-- Semi-private table that stores the currently open ports from 
M.__openPorts = {}

-- Testing-only function to initialize this to a common state.
function M.__Initialize()
    M.__openPorts = {}
end

-- Opens a communication port on the modem.
---@param port integer
---@return boolean
function M.open(port)
    local thread = Coroutine.running()

    if M.__openPorts[port] == nil then
        M.__openPorts[port] = {}
    end

    -- Can't open a port that has already been opened.
    Luaunit.assertNotTableContains(M.__openPorts[port], thread)
    table.insert(M.__openPorts[port], thread)

    return true
end

-- Closes a communication port on the modem.
---@param port integer
function M.close(port)
    local thread = Coroutine.running()

    -- Can't close a port that is not open.
    Luaunit.assertNotIsNil(M.__openPorts[port])
    Luaunit.assertTableContains(M.__openPorts[port], thread)

    -- TODO: Refactor M.__openPorts[port] to be a set instead of a list so we don't have to do this nonsense.
    local idx = -1
    for i, v in ipairs(M.__openPorts[port]) do
        if v == thread then
            idx = i
            break
        end
    end
    table.remove(M.__openPorts[port], idx)
end

-- Transmits the given message to all other receivers that have opened this port.
---@param port integer
---@param message string
function M.broadcast(port, message)
    local thread = Coroutine.running()

    Luaunit.assertTableContains(M.__openPorts[port], thread)
    local portReceivers = M.__openPorts[port]

    for _, receiver in portReceivers do
        if receiver ~= thread then
            local eventToPush = {receiver, thread, port, 0, message}
            Event.__push(receiver, "modem_message", eventToPush)
        end
    end

    -- We must yield here to give receivers a chance to respond to this.
    -- Because we have (possibly) multiple receivers, we do this here instead
    -- of in the event layer.
    Coroutine.yield("modem_broadcast")
end

-- Transmits the given message to the receiver identified by addr.
---@param addr string
---@param port integer
---@param message string
function M.send(addr, port, message)

    M.__sendNoYield(addr, port, message)

    -- We must yield here to give receivers a chance to respond to this.
    -- Because broadcast messages have (possibly) multiple receivers, we
    --  do this here instead of in the event layer.
    Coroutine.yield("modem_send")

    return true
end

-- Transmits the given message to the receiver identified by addr.
-- This does not yield the coroutine so that it can be called from test verification code.
---@param addr any
---@param port integer
---@param message any
function M.__sendNoYield(addr, port, message)
    local thread = Coroutine.running()
    Luaunit.assertNotIsNil(M.__openPorts[port])

    if M.__openPorts[port] == nil then
        return nil
    end

    -- Note: We can *not* assert that addr is present because it is legal for the destination to shut down.
    -- TODO: Refactor M.__openPorts[port] to be a set instead of a list so we don't have to do this nonsense.
    for _, receiver in ipairs(M.__openPorts[port]) do
        if receiver == addr then
            Event.__push(receiver, "modem_message", M.__CreateModemEvent(receiver, thread, port, message))
        end
    end
end

---@param receiver thread
---@param sender thread
---@param port integer
---@param message any
---@return any
function M.__CreateModemEvent(receiver, sender, port, message)
    return {receiver, sender, port, 0, message}
end

return M
