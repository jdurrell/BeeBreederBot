-- This module contains functions for loading config options from a config file.
local M = {}

---@param path string
---@param config table<string, number | string>
---@param debug boolean
---@return boolean
function M.LoadConfig(path, config, debug)
    local configfile, err = io.open(path, "r")
    if configfile == nil then
        if debug then
            Print(string.format("Did not find existing config file at %s: %s.", path, err))
        end

        return false
    end

    for line in configfile:lines("l") do
        local fields = line:gmatch("[^=]+")
        if #fields ~= 2 then
            Print(string.format("Failed to parse config file. Invalid line: '%s'.", line))
            configfile:close()
            return false
        end

        if config[fields[1]] == nil then
            Print(string.format("Unrecognized config option '%s'.", fields[1]))
            configfile:close()
            return false
        end

        if type(config[fields[1]]) == "number" then
            config[fields[1]] = tonumber(fields[2])
        else
            config[fields[1]] = fields[2]
        end
    end

    configfile:close()
    return true
end

return M
