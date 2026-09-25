---@class MutationConditionSet
---@field biome string | nil
---@field dimension string | nil
---@field foundation string | nil
---@field humidity string | nil
---@field temperature1 string | nil
---@field temperature2 string | nil
---@field timeCalendar string | nil
---@field timePeriodic string | nil
local MutationConditionSet = {}

-- Note that these functions are not class members because we must be able to serialize the data from the server to the robot.
local ConditionFunctions = {}

---@param conditions string[] | nil
---@return MutationConditionSet | nil
function ConditionFunctions.ParseFromForestry(conditions)
    if (conditions == nil) or (#conditions == 0) then
        -- Nothing to do.
        return nil
    end

    ---@type MutationConditionSet
    local conditionSet = {}

    -- Each line specifies exactly one condition.
    for i, condition in ipairs(conditions) do
        -- Conditions are inconsistent on capitalization. Just make it lowercase to make parsing easier.
        local conditionLower = condition:lower()

        -- Foundations (both solid and liquid).
        local foundation, foundationCount = conditionLower:gsub("^requires (.*) as a foundation.?$", "%1")
        if foundationCount > 0 then
            conditionSet.foundation = foundation
            goto continue
        end

        -- Humidity.
        local humidity, humidityCount = conditionLower:gsub("^requires ([a-z]*) humidity.?$", "%1")
        if humidityCount > 0 then
            conditionSet.humidity = humidity
            goto continue
        end

        -- Temperature.
        local temperature1, temperature1Count = conditionLower:gsub("^requires ([a-z]*) temperature.?$", "%1")
        if temperature1Count > 0 then
            conditionSet.temperature1 = temperature1
            goto continue
        end
        local temperatures, temperature2Count = conditionLower:gsub("^requires temperature between ([a-z]*) and ([a-z]*).?$", "%1-%2")
        if temperature2Count > 0 then
            conditionSet.temperature1 = temperatures:gsub("^([a-z]*)-([a-z]*)$", "%1")
            conditionSet.temperature2 = temperatures:gsub("^([a-z]*)-([a-z]*)$", "%2")
            goto continue
        end

        -- Dimensions.
        local dimension1, dimension1Count = conditionLower:gsub("^required dimension ([a-z%s]*).?$", "%1")
        if dimension1Count > 0 then
            conditionSet.dimension = dimension1
            goto continue
        end

        -- Biomes.
        -- Note: Technically, we can see conditions for a "nether" biome or "end" biome or other similar biomes that really
        -- indicate dimension rather than biome. We will still treat them like a biome here.
        local biome1, biome1Count = conditionLower:gsub("^occurs within a ([a-z%s]*) biome.$", "%1")
        if biome1Count > 0 then
            conditionSet.biome = biome1
            goto continue
        end
        local biome2, biome2Count = conditionLower:gsub("^required biome ([a-z%s]*).?$", "%1")
        if biome2Count > 0 then
            conditionSet.biome = biome2
            goto continue
        end
        local biome3, biome3Count = conditionLower:gsub("^occurs within biomes like: (.*)$", "%1")
        if biome3Count > 0 then
            -- TODO: This only shows up for [ocean, hot] and [ocean, wet]. Unclear what this actually means.
            conditionSet.biome = biome3
            goto continue
        end

        -- "Periodic" time - will occur frequently enough that we don't really need to do anything special for it.
        -- e.g. "night", "day", "waxing crescent".
        local timePeriodic1, timePeriodic1Count = conditionLower:gsub("^during the ([a-z%s]*).?$", "%1")
        if timePeriodic1Count > 0 then
            conditionSet.timePeriodic = timePeriodic1
            goto continue
        end
        local moonDirectionMatches = {"waxing", "waning"}
        local moonPhaseMatches = {"crescent", "half", "gibbous"}
        for i2, moonDirection in ipairs(moonDirectionMatches) do
            local match1, count1 = conditionLower:gsub("^occurs between the (" .. moonDirection .. ").*$", "")
            if count1 > 0 then
                for i3, moonPhase in ipairs(moonPhaseMatches) do
                    local match2, count2 = conditionLower:gsub("^occurs between the (" .. moonDirection .. ") (" .. moonPhase .. ").*", "")
                    if count2 > 0 then
                        conditionSet.timePeriodic = conditionLower:gsub("^occurs ([a-z%s]*).?$", "%1")
                        goto continue
                    end
                end
            end
        end

        -- "Calendar" time - depends on real-life calendar days. Players either need to change the clocks or wait a long time.
        local months = {"january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"}
        for i2, month in ipairs(months) do
            local timeCalendar, timeCalendarCount = conditionLower:gsub("^occurs between (" .. month .. ").*$", "%1")
            if timeCalendarCount > 0 then
                conditionSet.timeCalendar = conditionLower:gsub("^occurs ([a-z0-9%s]*).?$", "%1")
                goto continue
            end
        end

        -- We can technically have condition strings that don't match any of the above.
        -- These strings typically say "inspired by" and some player names, which for some reason,
        -- is placed in the special conditions text. It has no actual effect.
        -- TODO: Figure out how to generate an error on something that *should* be parsed as a real condition, but isn't.
        ::continue::
    end

    return conditionSet
end

---@param conditions MutationConditionSet
---@return boolean
function ConditionFunctions.IsTrivialConditions(conditions)
    -- The only trivial condition is a periodic time.
    -- All others are nontrivial.
    -- TODO: Periodic time might not even be trivial since we might be able to wait for it with world sensor.
    return (
        (conditions.biome == nil) and
        (conditions.dimension == nil) and
        (conditions.foundation == nil) and
        (conditions.humidity == nil) and
        (conditions.temperature1 == nil) and
        (conditions.temperature2 == nil) and
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
        (conditions.foundation ~= "α centauri bb surface block") and
        (conditions.foundation ~= "aura node") and
        (conditions.foundation ~= "ender goo") and
        (conditions.foundation ~= "ic2 coolant") and
        (conditions.foundation ~= "ic2 hot coolant") and
        (conditions.foundation ~= "lava") and
        (conditions.foundation ~= "short mead") and
        (conditions.foundation ~= "water")
    )
end

---@param conditions MutationConditionSet
---@return boolean
function ConditionFunctions.IsManualFoundation(conditions)
    return (
        (conditions.foundation ~= nil) and

        -- TODO: Verify whether this name will match correctly. It might not need to be manual.
        ((conditions.foundation == "α centauri bb surface block") or
        (conditions.foundation == "aura node") or
        (conditions.foundation == "ender goo") or
        (conditions.foundation == "ic2 coolant") or
        (conditions.foundation == "ic2 hot coolant") or
        (conditions.foundation == "lava") or
        (conditions.foundation == "short mead") or
        (conditions.foundation == "water"))
    )
end

---@param conditions MutationConditionSet
function ConditionFunctions.RequiresManual(conditions)
    return (
        ConditionFunctions.IsManualFoundation(conditions) or
        (conditions.biome ~= nil) or
        (conditions.dimension ~= nil) or
        (conditions.humidity ~= nil) or
        (conditions.temperature1 ~= nil) or
        (conditions.temperature2 ~= nil) or
        (conditions.timeCalendar ~= nil)
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
    if conditions.temperature1 ~= nil then
        Print(string.format("temperature1: %s", conditions.temperature1))
    end
    if conditions.temperature2 ~= nil then
        Print(string.format("temperature2: %s", conditions.temperature2))
    end
    if conditions.timeCalendar ~= nil then
        Print(string.format("Calendar time: %s", conditions.timeCalendar))
    end
    if conditions.timePeriodic ~= nil then
        Print(string.format("Periodic time: %s", conditions.timePeriodic))
    end
end

return ConditionFunctions
