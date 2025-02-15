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

-- This function taken from http://lua-users.org/wiki/CopyTable.
-- Save copied tables in `copies`, indexed by original table.
local function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
            end
            setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

---@generic T
---@param original T
---@return T
function Copy(original)
    return deepcopy(original, nil)
end
