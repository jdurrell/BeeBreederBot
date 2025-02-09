-- This is a module that simulates OC's term API for testing.
-- Mostly, it is used for interacting with the BeeServer from the test environment.
local Coroutine = require("coroutine")
local Queue = require("Test.SimulatorModules.EventQueue")

---@class Term
---@field __events table<thread, Queue>
local M = {}

-- Static private queue of commands. This is implementation-specific,
-- so it can't be exposed to production code.
M.__events = {}

-- Testing-only function to initialize this to a common state.
function M.__Initialize()
    M.__events = {}
end

-- Testing-only function that registers a thread for simulated terminal input.
---@param thread thread
function M.__registerThread(thread)
    M.__events[thread] = Queue:Create()
end

-- Writes the given message into the simulated stdin of the given thread.
-- Technically, the real API does have a real write function, so maybe this
-- will get promoted someday. For now, though, it's not used in production.
-- Automatically registers the thread for simulated terminal input if it
-- wasn't registered previously.
---@param thread thread
---@param message string
function M.__write(thread, message)
    if M.__events[thread] == nil then
        M.__events[thread] = Queue:Create()
    end

    M.__events[thread]:Push(message)
end

-- Attempts to read a string from the simulated stdin of the calling thread.
---@param timeout number
---@return string | nil, string | nil
function M.pull(timeout)
    Coroutine.yield("term_pull")

    -- We actually ignore the timeout since it's largely pointless in the testing environment.
    local thread = Coroutine.running()
    if M.__events[thread] == nil then
        return nil, nil
    end

    -- TODO: Technically, I don't actually know the right name of this event.
    --       It shouldn't really matter for testing though since we only care whether it's nil or not.
    return "term", M.__events[thread]:Pull()
end

return M
