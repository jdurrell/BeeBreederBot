-- This file contains math for determining chances of getting a given mutation from given combinations of species.

---@return boolean
local function arrayContainsValue(tab, val)
    for i, v in ipairs(tab) do
        if v == val then
            return true
        end
    end
    return false
end

---@param target string
---@param siblings table<string, boolean>
---@return number
local function CalculateMutationChanceForTarget(target, siblings)
    -- TODO: Implement this math.
    -- TODO: Explain why this math is necessary instead of just taking the mutation chance straight from the import.
    return 1
end

---@param target string
---@param beeGraph SpeciesGraph
function CalculateBreedInfo(target, beeGraph)
    -- TODO: Refactor breedInfo to be a mapping of unique key (probably something like "<parent1>-<parent2>") instead of a 2D matrix
    --       to prevent duplicating data and achieve lower memory usage.
    local breedInfo = {}

    -- For each mutation, calculate the chance of getting that mutation (taking into account the other possible mutations)
    local node = beeGraph[target]
    for i, v in ipairs(node.parentMutations) do
        -- Collect all other siblings this set of parents could possibly make.
        local comboSiblings = {}
        local parent1Node = beeGraph[v[1]]
        for sibling, possibleParents in pairs(parent1Node.childMutations) do
            -- TODO: Refactor childMutations[sibling] to be a hashset instead of an array for faster lookup. 
            if arrayContainsValue(possibleParents, v[2]) then
                comboSiblings[sibling] = true
            end
        end

        -- Initialize breedInfo for each parent, if necessary.
        if breedInfo[v[1]] == nil then
            breedInfo[v[1]] = {}
        end
        if breedInfo[v[2]] == nil then
            breedInfo[v[2]] = {}
        end

        -- Calculate the chance of this target being chosen over the other siblings, taking into account every possible genome shuffle permutation.
        -- TODO: Actually do this.
        local mutationChance = CalculateMutationChanceForTarget(target, comboSiblings)
        breedInfo[v[1]][v[2]] = mutationChance
        breedInfo[v[2]][v[1]] = mutationChance
    end

    return breedInfo
end

