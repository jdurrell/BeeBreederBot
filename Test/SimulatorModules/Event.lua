-- This is a module that simulates OC's event API for testing.
-- Mostly, this is used for simulating communication between robot and server.
-- We yield immediately before polling for an event. We could also yield
-- directly after publishing an event, but we will do that at the modem
-- layer instead of in here because broadcasting could publish several times.
-- The test procedure will need to figure out exactly when it responds to
-- each one because some messages are sent without waiting for a response,
-- and the server constantly waits for a message until it gets one.
local Coroutine = require("coroutine")
local Queue = require("Test.SimulatorModules.EventQueue")

---@class Event
---@field __events table<thread, table<string, Queue>>
local M = {}

-- Static private queue of events. This is implementation-specific,
-- so it can't be exposed to production code.
M.__events = {}

-- Testing-only function to initialize this to a common state.
function M.__Initialize()
    M.__events = {}
end

-- Registers a thread for simulated events.
---@param thread thread
function M.__registerThread(thread)
    M.__events[thread] = Queue:Create()
end

-- This is technically external since it's needed by the component modem library,
-- but it shouldn't be used by the BeeServer or BeeBot because it's not truly
-- part of OpenComputers' event library.
---@param thread thread
---@param key string
---@param event any
function M.__push(thread, key, event)
    if M.__events[thread] == nil then
        M.__events[thread] = {}
    end

    if M.__events[thread][key] == nil then
        M.__events[thread][key] = Queue:Create()
    end

    M.__events[thread][key]:Push(event)
end

-- Attempts to pull an event of the given key from the event queue. Returns nil if nothing was found.
---@param timeout number
---@param key string
---@return string | nil, ...
function M.pull(timeout, key)
    -- We actually ignore the timeout since it's largely pointless in the testing environment.

    -- Yield from code under test in case we want something to respond here.
    Coroutine.yield("event_pull")
    return M.__pullNoYield(key)
end

-- Attempts to pull an event of the given key from the event queue. Returns nil if nothing was found.
-- This does not yield the coroutine so that it can be called from test verification code.
---@param key string
---@return string | nil, ...
function M.__pullNoYield(key)
    local thread = Coroutine.running()

    if (M.__events[thread] == nil) or M.__events[thread][key] == nil then
        return nil
    end

    local event = M.__events[thread][key]:Pull()
    if event == nil then
        return nil
    end

    return key, table.unpack(event)
end

return M
