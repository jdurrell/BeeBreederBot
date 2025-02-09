-- This is a module that simulates OC's term API for testing.
-- Mostly, it is used for interacting with the BeeServer from the test environment.
local M = {}

local Coroutine = require("coroutine")
local Queue = require("Test.SimulatorModules.EventQueue")

-- Static private queue of commands. This is implementation-specific,
-- so it can't be exposed to production code.
---@type table<thread, Queue>
M.__events = {}

function M.__Initialize()
    M.__events = {}
end

-- Writes the given message into the simulated stdin of the given thread.
-- Technically, the real API does have a real write function, so maybe this
-- will get promoted someday. For now, though, it's not used in production.
---@param thread thread
---@param message string
function M.__write(thread, message)
    if M.__event[thread] == nil then
        M.__event[thread] = Queue:Create()
    end

    M.__event[thread]:Push(message)
end

-- Attempts to read a string from the simulated stdin of the calling thread.
---@param timeout number
---@return string | nil
function M.pull(timeout)
    -- We actually ignore the timeout since it's largely pointless in the testing environment.

    local thread = Coroutine.running()
    return M.__event[thread]:Pull()
end
