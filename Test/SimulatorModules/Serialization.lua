-- This is a module that simulates OC's serialization API for testing.
-- For the purposes of testing, this is actually a dummy wrapper module.
-- Serialization is already implemented by OpenComputers, and all of the
-- communication during testing is simulated anyway, so we can just hand
-- over the table directly to keep things simple.
---@class Serialization
local M = {}

-- Serializes the given table into a string for sending over the wire.
---@param obj any
---@return string
function M.serialize(obj)
    return obj
end

-- Deserializes the given string into the original table.
---@param str string
---@return any
function M.unserialize(str)
    return str
end

return M
