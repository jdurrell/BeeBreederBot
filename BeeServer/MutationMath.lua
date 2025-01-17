-- This file contains math for determining chances of getting a given mutation from given combinations of species.

---@param x integer
---@return integer
function Factorial(x)
    local output = 1
    for i = 1, x do
        output = output * i
    end

    return output
end

---@param list number[]
---@return number[][]
function ComputeCombinations(list)
    local combinations = {}
    for combinationSize=1, #list do

        -- Initialize list of pointers
        local pointers = {}
        for i=1, combinationSize do
            pointers[i] = i
        end

        while true do
            -- Set of items pointed to by the pointers is a unique combination. Add that to the output list.
            table.insert(combinations, {})
            for i=1, #pointers do
                table.insert(combinations[#combinations], list[pointers[i]])
            end

            -- Starting from the end, check whether the pointers can be advanced or need to be reset.
            local pointersToReset = {}
            local advancingPointer = #pointers
            while (advancingPointer > 0) and (pointers[advancingPointer] == (#list - (#pointers - advancingPointer))) do
                table.insert(pointersToReset, advancingPointer)
                advancingPointer = advancingPointer - 1
            end

            -- If we can't advance any of the pointers, then we have seen every combination of this size. Continue to next size.
            if advancingPointer <= 0 then
                break
            end

            -- Advance the pointer to advance and reset the other pointers to closely follow it.
            pointers[advancingPointer] = pointers[advancingPointer] + 1
            for _, resetPointer in ipairs(pointersToReset) do
                pointers[resetPointer] = pointers[advancingPointer] + (resetPointer - advancingPointer)
            end
        end
    end

    return combinations
end

---@param chanceForTarget number
---@param siblingChances number[]
---@return number
local function calculateMutationChanceForTarget(chanceForTarget, siblingChances)
    -- TODO: Explain why this math is necessary instead of just taking the mutation chance straight from the import.
    -- In theory, this algorithm runs in factorial time because it takes every permutation of the mutation shuffle.
    -- In practice, though, there are usually very few mutations (< 3) for a given set of parents, so this doesn't take very long.

    -- Get the list of all combinations of siblings could be tested for mutation by Forestry before the target.
    local combinations = ComputeCombinations(siblingChances)

    -- For each combination, compute the chance for that combination.
    -- Then, multiply that chance by the number of species order permutations that
    --   result in the combination being evaluated by Forestry before the target.
    -- This weights that chance in the sum according to the probability of it coming up.
    -- Add all the weighted chances together, then divide by the total number of permutations to get the actual chance.
    local weightedChanceSum = 0
    local denominator = Factorial(#siblingChances + 1)
    for _, combo in ipairs(combinations) do
        local weightedChance = chanceForTarget
        for _, chance in ipairs(combo) do
            weightedChance = weightedChance * chance
        end
        local numerator = Factorial(#combo)

        weightedChanceSum = weightedChanceSum + (weightedChance * numerator)
    end

    return weightedChanceSum / denominator
end

---@param target string
---@param beeGraph SpeciesGraph
---@return table<string, table<string, number>>
function CalculateBreedInfo(target, beeGraph)
    -- TODO: Refactor breedInfo to be a mapping of unique key (probably something like "<parent1>-<parent2>") instead of a 2D matrix
    --       to prevent duplicating data and achieve lower memory usage.
    local breedInfo = {}

    -- For each mutation, calculate the chance of getting that mutation (taking into account the other possible mutations)
    local node = beeGraph[target]
    for i, v in ipairs(node.parentMutations) do
        -- Collect the chances for all other siblings this set of parents could possibly make.
        ---@type number[]
        local comboSiblings = {}
        local targetChance = 0.0

        local parent1Node = beeGraph[v.parents[1]]
        for sibling, possibleParents in pairs(parent1Node.childMutations) do
            -- TODO: Refactor childMutations[sibling] to be a hashset instead of an array for faster lookup. 
            for _, mut in ipairs(possibleParents) do
                if mut.parent == v.parents[2] then
                    if sibling == target then
                        targetChance = mut.chance
                    else
                        table.insert(comboSiblings, mut.chance)
                    end
                end
            end
        end

        assert(targetChance > 0.0, "Didn't find target in its parent mutations.")

        -- Initialize breedInfo for each parent, if necessary.
        if breedInfo[v.parents[1]] == nil then
            breedInfo[v.parents[1]] = {}
        end
        if breedInfo[v.parents[2]] == nil then
            breedInfo[v.parents[2]] = {}
        end

        -- Calculate the chance of this target being chosen over the other siblings, taking into account every possible genome shuffle permutation.
        -- TODO: Actually do this.
        local mutationChance = calculateMutationChanceForTarget(targetChance, comboSiblings)
        breedInfo[v.parents[1]][v.parents[2]] = mutationChance
        breedInfo[v.parents[2]][v.parents[1]] = mutationChance
    end

    return breedInfo
end

