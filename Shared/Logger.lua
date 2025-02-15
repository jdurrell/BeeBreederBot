-- This module handles the on-disk inventory format.

---@class Logger
local M = {}

---@param filepath string
---@return ChestArray | nil
function M.ReadSpeciesLogFromDisk(filepath)
    local logfile = io.open(filepath, "r")
    if logfile == nil then
        -- This is not an error. It just means that we haven't logged anything yet.
        Print("No existing logfile at " .. tostring(filepath))
        return {}
    end

    local log = {}
    local newManualAdjusts = {}
    local count = 0
    for line in logfile:lines("l") do
        count = count + 1
        local fields = {}
        for field in string.gmatch(line, "[%w]+") do  -- TODO: Handle species with spaces in their name.
            local stringfield = string.gsub(field, ",", "")
            table.insert(fields, stringfield)
        end

        -- We should get 4 fields from each line. If we don't, then we don't know what we're reading.
        if #fields ~= 4 then
            logfile:close()
            Print("Error: failed to parse logfile on line " .. tostring(count) .. ": " .. line)
            Print("Got " .. tostring(#fields) .. " fields:")
            for _,v in ipairs(fields) do
                Print(v)
            end
            return nil
        end

        log[fields[1]] = {
            loc = {
                x = tonumber(fields[2]),
                y = tonumber(fields[3]),
            },
            timestamp = fields[4] == "0" and GetCurrentTimestamp() or tonumber(fields[4])  -- Set manually adjusted values to override pre-existing versions.
        }

        -- If this is the first read of something manually adjusted, then we will need to write out the new time afterwards.
        if fields[4] == "0" then
            table.insert(newManualAdjusts, fields[1])
        end
    end
    logfile:close()

    -- Write out the new time for any manually adjusted species.
    for _, newlyAdjustedSpecies in ipairs(newManualAdjusts) do
        M.LogSpeciesToDisk(filepath, newlyAdjustedSpecies, log[newlyAdjustedSpecies].loc, GetCurrentTimestamp())
    end

    return log
end

---@param filepath string
---@param species string
---@param location Point
---@param timestamp integer
---@return boolean -- whether the operation succeeded.
function M.LogSpeciesToDisk(filepath, species, location, timestamp)
    local thisLogLine = species .. "," .. tostring(location.x) .. "," .. tostring(location.y) .. "," .. tostring(timestamp) .. "\n"
    local logfile, fs, errMsg

    logfile, errMsg = io.open(filepath, "r")
    if logfile == nil then
        -- Logfile doesn't already exist, so just create it and write out the new entry.
        logfile, errMsg = io.open(filepath, "w")
        if logfile == nil then
            -- We can't really handle this error. Just print it out and move on.
            Print("Failed to open new logfile for writing: " .. errMsg .. "\n")
            return false
        end
        fs, errMsg = logfile:write(thisLogLine)
        if fs == nil then
            Print("Failed to write to new logfile after: " .. errMsg .. "\n")
            logfile:close()
            return false
        end

        local success, exitcode, code = logfile:close()
        if not success then
            Print("Failed to close new logfile, exitcode: " .. exitcode .. ", code: " .. tostring(code) .. "\n")
            return false
        end

        return true
    end

    -- We want to keep the file alphabetical so that it's easier for a human to use.
    -- Read in the existing data so it can be moved further down to accomodate the new entry.
    -- This file shouldn't be very large, so we should have enough memory for this.
    --    TODO: Optimize for memory usage to be more sure about this.
    local alreadyFound = false
    local lines = {}
    for line in logfile:lines("L") do
        -- The species name is the first field in the line.
        local name = string.sub(line, 0, string.find(line, ",") - 1)

        if (not alreadyFound) and ((name > species) or (name == species)) then  -- String comparison operators compare based on current locale.
            alreadyFound = true

            -- We have found the correct position for the new log line. Add it to the log.
            table.insert(lines, thisLogLine)

            -- If we are not overwriting something, then we still need to add this line as well.
            if name > species then
                table.insert(lines, line)
            end
        else
            table.insert(lines, line)
        end
    end


    -- OpenComputers does not support read/write streams, so we have to close the log, then reopen in "write" mode to overwrite the whole file.
    local success, exitcode, code = logfile:close()
    if not success then
        Print("Failed to close logfile after reading in existing data, exitcode: " .. exitcode .. ", code: " .. tostring(code) .. "\n")
        return false
    end
    logfile = nil

    -- Write out new file with the ordering modifications made above.
    -- Technically, we could serialize a table and just store that, but a csv is easier to edit for a human, if necessary.
    logfile, errMsg = io.open(filepath, "w")
    if logfile == nil then
        Print("Failed to open logfile for writing: " .. errMsg .. "\n")
        return false
    end

    for _, line in ipairs(lines) do
        fs, errMsg = logfile:write(line)
        if _ == nil then
            Print("Failed to overwrite logfile: " .. errMsg .. "\n")
            logfile:close()
            return false
        end
    end
    logfile:flush()
    success, exitcode, code = logfile:close()
    if not success then
        Print("Failed to close logfile after overwriting, exitcode: " .. exitcode .. ", code: " .. tostring(code) .. "\n")
        return false
    end

    return true
end

return M
