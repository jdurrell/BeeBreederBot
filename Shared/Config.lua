-- This module contains functions for loading config options from a config file.
local M = {}

---@param path string
---@param config table<string, boolean | number | string>
---@param debug boolean
---@return boolean
function M.LoadConfig(path, config, debug)
    local configfile, err = io.open(path, "r")
    if configfile == nil then
        if debug then
            Print(("Did not find existing config file at %s: %s."):format(path, err))
        end

        return false
    end

    for line in configfile:lines("l") do
        local fields = {}
        for match in line:gmatch("[^=]+") do
            table.insert(fields, match)
        end

        if #fields ~= 2 then
            Print(("Failed to parse config file. Invalid line: '%s'."):format(line))
            configfile:close()
            return false
        end

        if config[fields[1]] == nil then
            Print(("Unrecognized config option '%s'."):format(fields[1]))
            configfile:close()
            return false
        end

        if type(config[fields[1]]) == "boolean" then
            if fields[2] == "true" then
                config[fields[1]] = true
            elseif fields[2] == "false" then
                config[fields[1]] = false
            else
                Print(("Unrecognized boolean option '%s'."):format(fields[2]))
            end
        elseif type(config[fields[1]]) == "number" then
            config[fields[1]] = tonumber(fields[2])
        else
            config[fields[1]] = fields[2]
        end
    end

    configfile:close()
    return true
end

function M.PrintConfig(config)
    for k, v in pairs(config) do
        Print(("%s=%s"):format(k, tostring(v)))
    end
    Print("")
end

return M
