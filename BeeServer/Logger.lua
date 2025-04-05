-- This module handles the on-disk inventory format.

---@class Logger
local M = {}

---@param filepath string
---@return string[]
function M.ReadSpeciesLogFromDisk(filepath)
    local speciesFound = {}

    local logfile = io.open(filepath, "r")
    if logfile == nil then
        -- This is not an error. It just means that we haven't logged anything yet.
        Print(string.format("No existing logfile at %s\n", filepath))
        return {}
    end
    for line in logfile:lines("l") do
        table.insert(speciesFound, line)
    end
    logfile:close()

    return speciesFound
end

---@param filepath string
---@param species string
---@return boolean -- whether the operation succeeded.
function M.LogSpeciesToDisk(filepath, species)
    local logfile, fs, errMsg

    logfile, errMsg = io.open(filepath, "r")
    if logfile == nil then
        -- Logfile doesn't already exist, so just create it and write out the new entry.
        logfile, errMsg = io.open(filepath, "w")
        if logfile == nil then
            -- We can't really handle this error. Just print it out and move on.
            Print(string.format("Failed to open new logfile for writing: %s\n", errMsg))
            return false
        end
        fs, errMsg = logfile:write(species)
        if fs == nil then
            Print(string.format("Failed to write to new logfile after creation: %s\n", errMsg))
            logfile:close()
            return false
        end

        local success, exitcode, code = logfile:close()
        if not success then
            Print(string.format("Failed to close new logfile, exitcode: %s, code: %u\n", exitcode, code))
            return false
        end

        return true
    end

    -- We want to keep the file alphabetical so that it's easier for a human to use.
    -- Read in the existing data so it can be moved further down to accomodate the new entry.
    -- This file shouldn't be very large, so we should have enough memory for this.
    local alreadyFound = false
    local speciesInLog = {}
    for line in logfile:lines("l") do
        if (not alreadyFound) and ((line > species) or (line == species)) then  -- String comparison operators compare based on current locale.
            alreadyFound = true

            -- We have found the correct position for the new log line. Add it to the log.
            table.insert(speciesInLog, species)

            -- If we are not overwriting something, then we still need to add this line as well.
            if line > species then
                table.insert(speciesInLog, line)
            end
        else
            table.insert(speciesInLog, line)
        end
    end


    -- OpenComputers does not support read/write streams, so we have to close the log, then reopen in "write" mode to overwrite the whole file.
    local success, exitcode, code = logfile:close()
    if not success then
        Print(string.format("Failed to close logfile after reading in existing data, exitcode: %s, code: %u\n", exitcode, code))
        return false
    end
    logfile = nil

    -- Write out new file with the ordering modifications made above.
    -- Technically, we could serialize a table and just store that, but a csv is easier to edit for a human, if necessary.
    logfile, errMsg = io.open(filepath, "w")
    if logfile == nil then
        Print(string.format("Failed to open logfile for writing: %s\n", errMsg))
        return false
    end

    for _, line in ipairs(speciesInLog) do
        fs, errMsg = logfile:write(line .. "\n")
        if _ == nil then
            Print(string.format("Failed to overwrite logfile: %s\n", errMsg))
            logfile:close()
            return false
        end
    end
    logfile:flush()
    success, exitcode, code = logfile:close()
    if not success then
        Print(string.format("Failed to close logfile after overwriting, exitcode: %s, code: %u\n", exitcode, code))
        return false
    end

    return true
end

return M
