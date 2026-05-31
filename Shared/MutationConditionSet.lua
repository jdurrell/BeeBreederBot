---@class MutationConditionSet
---@field biome string | nil
---@field dimension string | nil
---@field foundation string | nil
---@field humidity string | nil
---@field temperature string | nil
---@field timeCalendar string | nil
---@field timePeriodic string | nil
local MutationConditionSet = {}

-- Note that these functions are not class members because we must be able to serialize the data from the server to the robot.
local ConditionFunctions = {}

---@param conditions string[] | nil
---@return MutationConditionSet
function ConditionFunctions.ParseFromForestry(conditions)
    ---@type MutationConditionSet
    local conditionSet = {}

    if (conditions == nil) then
        -- Nothing to do.
        return conditionSet
    end

    -- Each line specifies exactly one condition.
    for i, condition in ipairs(conditions) do
        -- Conditions are inconsistent on capitalization. Just make it lowercase to make parsing easier.
        local conditionLower = condition:lower()

        -- Foundations (both solid and liquid).
        local foundation, foundationCount = conditionLower:gsub("^requires (.*) as a foundation\\.?$", "%1")
        if foundationCount > 0 then
            conditionSet.foundation = foundation
            break
        end

        -- Humidity.
        local humidity, humidityCount = conditionLower:gsub("^requires (.*) humidity\\.?$", "%1")
        if humidityCount > 0 then
            conditionSet.humidity = humidity
            break
        end

        -- Temperature.
        local temperature1, temperature1Count = conditionLower:gsub("^requires (.*) temperature\\.?$", "%1")
        if temperature1Count > 0 then
            conditionSet.temperature = temperature1
            break
        end
        local temperature2, temperature2Count = conditionLower:gsub("^requires temperature between (.*)\\.?$", "%1")
        if temperature2Count > 0 then
            temperature2 = temperature2:gsub("\\.", "")
            temperature2 = "between " .. temperature2
            conditionSet.temperature = temperature2
            break
        end

        -- Dimensions.
        local dimension1, dimension1Count = conditionLower:gsub("^required dimension (.*)\\.?$", "%1")
        if dimension1Count > 0 then
            conditionSet.dimension = dimension1
            break
        end

        -- Biomes.
        -- Note: Technically, we can see conditions for a "nether" biome or "end" biome or other similar biomes that really
        -- indicate dimension rather than biome. We will still treat them like a biome here.
        local biome1, biome1Count = conditionLower:gsub("^occurs within a (.*) biome\\.$", "%1")
        if biome1Count > 0 then
            conditionSet.biome = biome1
            break
        end
        local biome2, biome2Count = conditionLower:gsub("^required Biome (.*)\\.?$", "%1")
        if biome2Count > 0 then
            conditionSet.biome = biome2
            break
        end
        local biome3, biome3Count = conditionLower:gsub("^occurs within biomes like: \\[(.*)\\]$", "%1")
        if biome3Count > 0 then
            -- TODO: This only shows up for [ocean, hot] and [ocean, wet]. Unclear what this actually means.
            conditionSet.biome = biome3
            break
        end

        -- "Periodic" time - will occur frequently enough that we don't really need to do anything special for it.
        -- e.g. "night", "day", "waxing crescent".
        local timePeriodic1, timePeriodic1Count = conditionLower:gsub("^during the (.*)\\.?$", "%1")
        if timePeriodic1Count > 0 then
            conditionSet.timePeriodic = timePeriodic1
            break
        end
        local timePeriodic2, timePeriodic2Count = conditionLower:gsub("^occurs between the ((waxing)|(waning))(.*)$", "%1%2")
        if timePeriodic2Count > 0 then
            timePeriodic2 = timePeriodic2:gsub("\\.", "")
            conditionSet.timePeriodic = timePeriodic2
            break
        end

        -- "Calendar" time - depends on real-life calendar days. Players either need to change the clocks or wait a long time.
        local monthMatch = "(january)|(february)|(march)|(april)|(may)|(june)|(july)|(august)|(september)|(october)|(november)|(december)"
        local timeCalendar, timeCalendarCount = conditionLower:gsub("^occurs between (" .. monthMatch .. ".*)$", "%1")
        if timeCalendarCount > 0 then
            timeCalendar = timeCalendar:gsub("\\.", "")
            conditionSet.timeCalendar = timeCalendar
            break
        end

        -- We can technically have condition strings that don't match any of the above.
        -- These strings typically say "inspired by" and some player names, which for some reason,
        -- is placed in the special conditions text. It has no actual effect.
    end

    return conditionSet
end

---@param conditions MutationConditionSet
---@return boolean
function ConditionFunctions.IsTrivialConditions(conditions)
    -- The only trivial condition is a periodic time.
    -- All others are nontrivial.
    return (
        (conditions.biome == nil) and
        (conditions.dimension == nil) and
        (conditions.foundation == nil) and
        (conditions.humidity == nil) and
        (conditions.temperature == nil) and
        (conditions.timeCalendar == nil)
    )
end

---@param conditions MutationConditionSet
---@return boolean
function ConditionFunctions.FoundationIsPlaceableBlock(conditions)
    if conditions.foundation == nil then
        return false
    end

    return (
        -- TODO: Verify whether this name will match correctly. It might not need to be manual.
        (conditions.foundation ~= "α Centauri Bb Surface Block")
        (conditions.foundation ~= "Aura node") and
        (conditions.foundation ~= "Ender Goo") and
        (conditions.foundation ~= "IC2 Coolant") and
        (conditions.foundation ~= "IC2 Hot Coolant") and
        (conditions.foundation ~= "Lava") and
        (conditions.foundation ~= "Short Mead") and
        (conditions.foundation ~= "Water")
    )
end

---@param conditions MutationConditionSet
function ConditionFunctions.PrintConditions(conditions)
    if conditions.biome ~= nil then
        Print(string.format("biome: %s", conditions.biome))
    end
    if conditions.dimension ~= nil then
        Print(string.format("dimension: %s", conditions.dimension))
    end
    if conditions.foundation ~= nil then
        Print(string.format("foundation: %s", conditions.foundation))
    end
    if conditions.humidity ~= nil then
        Print(string.format("humidity: %s", conditions.humidity))
    end
    if conditions.temperature ~= nil then
        Print(string.format("temperature: %s", conditions.temperature))
    end
    if conditions.timeCalendar ~= nil then
        Print(string.format("Calendar time: %s", conditions.timeCalendar))
    end
    if conditions.timePeriodic ~= nil then
        Print(string.format("Periodic time: %s", conditions.timePeriodic))
    end
end

return ConditionFunctions
