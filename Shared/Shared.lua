-- This file sets up constants and functionality that are used by both the robot and server.

IS_TEST = false  -- Backdoor for testing to suppress print statements, sleeps, and other things.

function __ActivateTestMode()
    IS_TEST = true
end

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

---@generic T, U
---@param tab table<T, U> | U[]
---@param value U
---@return boolean
function TableContains(tab, value)
    for k, v in pairs(tab) do
        if v == value then
            return true
        end
    end

    return false
end

---@param tab table
---@return boolean
function TableIsEmpty(tab)
    return (next(tab) ~= nil)
end

---@generic T, U
---@param tab table<T, U> | U[]
---@param predicate fun(k: T, v: U): boolean
function TableHasCondition(tab, predicate)
    for k, v in pairs(tab) do
        if predicate(k, v) then
            return true
        end
    end

    return false
end

---@generic T, U
---@param tab table<T, U> | U[]
---@param predicate fun(k: T, v: U): boolean
---@return integer
function TableCount(tab, predicate)
    local count = 0
    for k, v in pairs(tab) do
        if predicate(k, v) then
            count = count + 1
        end
    end

    return count
end

---@generic T, U
---@param tab table<T, U> | U[]
---@param valueExtractor fun(k: T, v: U): integer
---@return U
function TableMax(tab, valueExtractor)
    local maxElement
    for k, v in pairs(tab) do
        maxElement = v
        break
    end

    local maxValue = math.mininteger
    for k, v in pairs(tab) do
        local val = valueExtractor(k, v)
        if val > maxValue then
            maxValue = val
            maxElement = v
        end
    end

    return maxElement
end

---@generic T, U
---@param tab table<T, U> | U[]
---@param valueExtractor fun(k: T, v: U): integer
---@return U
function TableMin(tab, valueExtractor)
    local minElement
    for k, v in pairs(tab) do
        minElement = v
        break
    end

    local minValue = math.maxinteger
    for k, v in pairs(tab) do
        local val = valueExtractor(k, v)
        if val < minValue then
            minValue = val
            minElement = v
        end
    end

    return minElement
end

---@generic T
---@param set Set<T>
---@param value T
---@return boolean
function SetContains(set, value)
    return set[value] ~= nil
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

---@param trait string
---@param value TraitValue
function TraitToString(trait, value)
    if trait == "species" then
        return value.uid
    elseif trait == "speed" then
        return string.format("%.1f", value)
    elseif trait == "territory" then
        return string.format("[%d, %d, %d]", value[1], value[2], value[3])
    end
end

---@param traits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@return string
function TraitsToString(traits)
    if traits == nil then
        return "nil"
    end

    local str = "{"

    if traits.species ~= nil then
        str = str .. string.format("species: '%s', ", traits.species.uid)
    end
    if traits.caveDwelling ~= nil then
        str = str .. string.format("caveDwelling: '%s', ", tostring(traits.caveDwelling))
    end
    if traits.effect ~= nil then
        str = str .. string.format("effect: '%s', ", traits.effect)
    end
    if traits.fertility ~= nil then
        str = str .. string.format("fertility: %u, ", traits.fertility)
    end
    if traits.flowering ~= nil then
        str = str .. string.format("flowering: %u, ", traits.flowering)
    end
    if traits.flowerProvider ~= nil then
        str = str .. string.format("flowerProvider: '%s', ", traits.flowerProvider)
    end
    if traits.lifespan ~= nil then
        str = str .. string.format("lifespan: %u, ", traits.lifespan)
    end
    if traits.nocturnal ~= nil then
        str = str .. string.format("nocturnal: '%s', ", tostring(traits.nocturnal))
    end
    if traits.speed ~= nil then
        str = str .. string.format("speed: %.1f, ", traits.speed)
    end
    if traits.territory ~= nil then
        -- During testing, we sometimes only set one of these values, so we have backups here to prevent crashing.
        str = str .. string.format("territory: [%u, %u, %u], ",
            ((traits.territory[1] == nil) and 0) or traits.territory[1],
            ((traits.territory[2] == nil) and 0) or traits.territory[2],
            ((traits.territory[2] == nil) and 0) or traits.territory[3]
        )
    end
    if traits.tolerantFlyer ~= nil then
        str = str .. string.format("tolerantFlyer: '%s', ", tostring(traits.tolerantFlyer))
    end
    if traits.humidityTolerance ~= nil then
        str = str .. string.format("humidityTolerance: '%s', ", traits.humidityTolerance)
    end
    if traits.temperatureTolerance ~= nil then
        str = str .. string.format("temperatureTolerance: '%s', ", traits.temperatureTolerance)
    end

    if str:reverse():find("%s,") == 1 then
        str = str:sub(1, str:len() - 2)
    end

    str = str .. "}"

    return str
end
