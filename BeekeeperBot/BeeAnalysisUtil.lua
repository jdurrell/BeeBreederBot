local M = {}

---@param bee AnalyzedBeeIndividual
---@param trait string
---@param value TraitValue
---@return integer
function M.NumberOfMatchingAlleles(bee, trait, value)
    return (
        ((M.TraitIsEqual(bee.active, trait, value) and 1) or 0) +
        ((M.TraitIsEqual(bee.inactive, trait, value) and 1) or 0)
    )
end

---@param bee AnalyzedBeeIndividual
---@param targetTraits AnalyzedBeeTraits | PartialAnalyzedBeeTraits 
---@return boolean
function M.AllBeeTraitsEqual(bee, targetTraits)
    for trait, value in pairs(targetTraits) do
        if (not M.TraitIsEqual(bee.active, trait, value)) or (not M.TraitIsEqual(bee.inactive, trait, value)) then
            return false
        end
    end

    return true
end

---@param traitSet AnalyzedBeeTraits
---@param targetTraits AnalyzedBeeTraits | PartialAnalyzedBeeTraits
---@return boolean
function M.HasAllTraits(traitSet, targetTraits)
    for trait, value in pairs(targetTraits) do
        if not M.TraitIsEqual(traitSet, trait, value) then
            return false
        end
    end

    return true
end

---@param beeTraits AnalyzedBeeTraits
---@param trait string
---@param value TraitValue
function M.TraitIsEqual(beeTraits, trait, value)
    -- "Species" and "Territory" traits are tables, so compare them one level deeper.
    -- TODO: This would look nicer as a "deep equal" that could be used for all of them,
    --       but I'm not sure that the test infrastructure is actually setting every field.
    if trait == "species" then
        return (beeTraits.species.uid == value.uid)
    elseif trait == "territory" then
        return (beeTraits.territory[1] == value[1])
    elseif trait == "speed" then
        -- "Speed" often has weird floating-point problems.
        return math.abs(beeTraits.speed - value) <= 0.01
    end

    return (beeTraits[trait] == value)
end

---@param beeTraits AnalyzedBeeTraits
---@param toleranceString string
---@return integer, integer
function M.GetTotalTolerance(beeTraits, toleranceString)
    local val = beeTraits[toleranceString]
    local toleranceNumber = tonumber(val:sub(val:len(), val:len()), 10)
    if toleranceNumber == nil then
        return 0, 0
    end

    if val:find("BOTH") ~= nil then
        return -1 * toleranceNumber, toleranceNumber
    elseif val:find("UP") ~= nil then
        return 0, toleranceNumber
    elseif val:find("DOWN") ~= nil then
        return -1 * toleranceNumber, 0
    end

    return 0, 0
end

---@return boolean
---@param individual AnalyzedBeeIndividual
function M.AllTraitsPure(individual)
    for trait, value in pairs(individual.active) do
        if not M.TraitIsEqual(individual.inactive, trait, value) then
            return false
        end
    end

    return true
end

-- Returns whether the bee represented by the given stack is a pure bred version of the given species.
---@param individual AnalyzedBeeIndividual
---@param species string
---@return boolean
function M.IsPureBred(individual, species)
    return (individual.active.species.uid == species) and (individual.active.species.uid == individual.inactive.species.uid)
end

-- TODO: We can reduce the memory requirement in these functions by simply deleting fields instead of constructing new tables.
--       Figure out how to do this without sacrificing type safety.

---@param stack RawAnalyzedBeeStack
---@param slot integer
---@return AnalyzedBeeStack
function M.AnalyzedBeeStackFromRaw(stack, slot)
    ---@type AnalyzedBeeStack
    return {
        individual = {
            active = M.AnalyzedBeeTraitsFromRaw(stack.individual.active),
            inactive = M.AnalyzedBeeTraitsFromRaw(stack.individual.inactive),
            __genome = nil,  -- Testing-only field.
        },
        size = stack.size,
        slotInChest = slot,
        __hash = nil  -- Testing-only field.
    }
end

---@param traits RawAnalyzedBeeTraits
---@return AnalyzedBeeTraits
function M.AnalyzedBeeTraitsFromRaw(traits)
    ---@type AnalyzedBeeTraits
    return {
        caveDwelling = traits.caveDwelling,
        effect = traits.effect,
        fertility = traits.fertility,
        flowering = traits.flowering,
        flowerProvider = traits.flowerProvider,
        humidityTolerance = traits.humidityTolerance,
        lifespan = traits.lifespan,
        nocturnal = traits.nocturnal,
        species = {uid = traits.species.uid},
        speed = traits.speed,
        temperatureTolerance = traits.temperatureTolerance,
        territory = traits.territory,
        tolerantFlyer = traits.tolerantFlyer,
    }
end

return M
