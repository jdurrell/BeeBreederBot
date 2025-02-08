-- This file sets up constants and functionality that are used by both the robot and server.

IS_TEST = false  -- Backdoor for testing to suppress print statements, sleeps, and other things.

function GetCurrentTimestamp()
    return math.floor(os.time())
end

---@param time number Time to sleep in seconds
function Sleep(time)
    if IS_TEST then
        return
    end

    -- os.sleep() only exists inside OpenComputers, so outside IntelliSense doesn't recognize it.
    ---@diagnostic disable-next-line: undefined-field
    os.sleep(time)
end

---@param filepath string
---@param species string
---@param location Point
---@param timestamp integer
function LogSpeciesToDisk(filepath, species, location, timestamp)
    local logfile = io.open(filepath, "r")
    if logfile == nil then
        -- We can't really handle this error. Just print it out and move on.
        Print("Failed to get logfile.")
        return
    end

    -- We want to keep the file alphabetical so that it's easier for a human to use.
    -- Find the correct spot to insert this species.
    -- TODO: Is it necessary to maintain some index so that we don't have to do a linear search through the whole file?
    local pos = 0
    local replaceUntil = 0
    local replaceLine = false
    for line in logfile:lines("l") do
        -- The species name is the first field in the line.
        local name = string.sub(line, 0, string.find(line, ",") - 1)
        Print("got name " .. name)
        if name > species then  -- String comparison operators compare based on current locale.
            -- On the previous iteration, we set 'pos' to the start of this line.
            -- Now that we've found the species that comes right after this one, we can just break.
            break
        elseif name == species then
            -- Since we are replacing this line and overwriting the previous entry for this species,
            -- We will cut out the data from pos (start of this line) up to the end of this line.
            replaceUntil = logfile:seek("cur", 0)
            replaceLine = true
            break
        end

        pos = logfile:seek("cur", 0)
    end

    -- Read in the existing data so it can be moved further down to accomodate the new entry.
    if replaceLine then
        logfile:seek("set", replaceUntil)
    else
        logfile:seek("set", pos)
    end
    local restOfFile = logfile:read("a")  -- TODO: Will we always have enough memory for this?
    Print("rest of file:\n" .. restOfFile)

    -- OpenComputers does not support the "r+"" file mode, so we have to close the log, then reopen in "append" mode.
    logfile:close()
    logfile = nil
    logfile = io.open(filepath, "a")
    if logfile == nil then
        Print("Failed to open logfile for writing.")
        return
    end
    logfile:seek("set", pos)

    -- Write out the new entry, then the rest of the file.
    -- Technically, we could serialize a table and just store that, but a csv is easier to edit for a human, if necessary.
    logfile:write(species .. "," .. tostring(location.x) .. "," .. tostring(location.y) .. "," .. tostring(timestamp), "\n")
    logfile:write(restOfFile)
    logfile:flush()
    logfile:close()
end

---@param filepath string
---@return ChestArray | nil
function ReadSpeciesLogFromDisk(filepath)
    local logfile = io.open(filepath, "r")
    if logfile == nil then
        Print("Failed to open logfile at " .. tostring(filepath))
        return nil
    end

    local log = {}
    local newManualAdjusts = {}
    local count = 0
    for line in logfile:lines("l") do
        count = count + 1
        local fields = {}
        for field in string.gmatch(line, "[%w]+") do
            local stringfield = string.gsub(field, ",", "")
            table.insert(fields, stringfield)
        end

        -- We should get 4 fields from each line. If we don't then we don't know what we're reading.
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
        LogSpeciesToDisk(filepath, newlyAdjustedSpecies, log[newlyAdjustedSpecies].loc, GetCurrentTimestamp())
    end

    return log
end

function DebugPromptForKeyPress(message)
    Print(tostring(message))
    Sleep(0.25)
    Event.pull("key_up")
end

--- This helps keep Intellisense happy.
---@generic T
---@param value T | nil
---@return T
function UnwrapNull(value)
    return value
end

---@param str any
function Print(str)
    if IS_TEST then
        return
    end

    print(str)
end

---@param code integer
function ExitProgram(code)
    if IS_TEST then
        -- If we're running in the test environment, then don't take down the whole Lua instance
        -- because the tests are still running.
        coroutine.yield("exit", code)
    else
        os.exit(code)
    end
end

function __ActivateTestMode()
    IS_TEST = true
end
