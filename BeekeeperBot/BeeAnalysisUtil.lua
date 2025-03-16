local M = {}

---@param bee AnalyzedBeeIndividual
---@param trait string
---@param value any
---@return integer
function M.NumberOfMatchingAlleles(bee, trait, value)
    if trait == "species" then
        return (
            (((bee.active.species.uid == value.uid) and 1) or 0) +
            (((bee.inactive.species.uid == value.uid) and 1) or 0)
        )
    elseif trait == "territory" then
        return (
            (((bee.active.territory[1] == value[1]) and 1) or 0) +
            (((bee.inactive.territory[1] == value[1]) and 1) or 0)
        )
    else
        return (
            (((bee.active[trait] == value) and 1) or 0) +
            (((bee.inactive[trait] == value) and 1) or 0)
        )
    end
end

---@param bee AnalyzedBeeIndividual
---@param targetTraits AnalyzedBeeTraits
---@return boolean
function M.AllTraitsEqual(bee, targetTraits)
    for trait, value in pairs(targetTraits) do
        -- "Species" and "Territory" traits are tables, so compare them one level deeper.
        -- TODO: This would look nicer as a "deep equal" that could be used for all of them,
        --       but I'm not sure that the test infrastructure is actually setting every field.
        if trait == "species" then
            if ((bee.active.species.uid ~= targetTraits.species.uid) or (bee.inactive.species.uid ~= targetTraits.species.uid)) then
                return false
            end
        elseif trait == "territory" then
            if ((bee.active.territory[1] ~= targetTraits.territory[1]) or (bee.inactive.territory[1] ~= targetTraits.territory[1])) then
                return false
            end
        else
            if (bee.active[trait] ~= value) or (bee.inactive[trait] ~= value) then
                return false
            end
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

return M
