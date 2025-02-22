-- This file contains math for determining chances of getting a given mutation from given combinations of species.

local M = {}

---@param x integer
---@return integer
function M.Factorial(x)
    local output = 1
    for i = 1, x do
        output = output * i
    end

    return output
end

---@param list number[]
---@return number[][]
-- Returns the powerset of the elements of `list`. This treats all elements of `list` as unique elements,
-- regardless of whether any have the same value. Thus, it can return duplicates in the case of duplicate
-- elements provided.
function M.ComputePowerset(list)
    local combinations = {}

    -- Empty set.
    table.insert(combinations, {})

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

---@generic T
---@param list T[]
---@return T[][]
function M.ComputePermutations(list)
    if #list == 1 then
        return {{list[1]}}  -- In theory, we could just return list, but I'm a little scared of the reference being misused.
    end

    local permutationsList = {}

    for i, val in ipairs(list) do
        local subValues = {}
        for j, subV in ipairs(list) do
            if i ~= j then
                table.insert(subValues, subV)
            end
        end

        local subPermutations = M.ComputePermutations(subValues)
        for _, subPermutation in ipairs(subPermutations) do
            table.insert(subPermutation, val)
            table.insert(permutationsList, subPermutation)
        end
    end

    return permutationsList
end

-- TODO: Decide whether this function can be removed.
-- Forestry provides a `chance` of getting a given mutation from a given set of parents (call this "p"). This is also viewable in NEI in-game.
-- However, p is *not* the true chance of getting that mutation from that set of parents because multiple sets of mutations exist.
-- Internally, if Forestry decides that a species mutation will occur, it shuffles the list of possible child mutations to a random order,
-- then iterates over this order. On each iteration, there is a chance p for that mutation to "succeed". The *first* mutation to "succeed"
-- is chosen as the resulting child, and no other mutations later in the list are evaluated.
-- Therefore, for a given permutation of the list, the chance of the target mutation actually resulting is equal to p times the chance of all
-- mutations evaluated *before* the target *not* occurring. Thus, the *true* chance of the target mutation occurring (given that a mutation
-- *is* occurring) is the sum of chances of occurence *in each permutation* times the probability of *that permutation actually appearing*.
--
-- Just because each permutation of the evaluation order is equally likely (Forestry uses a Fisher-Yates shuffle), that does *not*
-- mean that p is equal to the true chance! (consider the simple example of a 0.25 target mutation and a 0.5 non-target mutation)
---@param chanceForTarget number
---@param siblingChances number[]
---@return number
function M.CalculateMutationChanceForTarget(chanceForTarget, siblingChances)
    -- TODO: Account for escritoire reseach. - Probably won't do this. If you're doing escritoire, you would probably just do everything else by hand.

    -- In theory, this algorithm runs in factorial time because it takes every permutation of the mutation shuffle.
    -- In practice, though, there are usually very few mutations (< 3) for a given set of parents, so this doesn't take very long.

    -- Get the list of all combinations of siblings could be tested for mutation by Forestry before the target.
    local combinations = M.ComputePowerset(siblingChances)

    -- For each combination, compute the chance for that combination.
    -- Then, multiply that chance by the number of Forestry evaluation-order permutations that
    --   result in the combination being evaluated by Forestry before the target.
    -- This weights that chance in the sum according to the probability of it coming up.
    -- Add all the weighted chances together, then divide by the total number of permutations to get the actual chance.
    local weightedChanceSum = 0
    local numPermutationsTotal = M.Factorial(#siblingChances + 1)
    for _, combo in ipairs(combinations) do
        local weightedChance = chanceForTarget
        for _, chance in ipairs(combo) do
            weightedChance = weightedChance * (1 - chance)
        end

        -- Number of permutations this chances applies to is the number of permutations of siblings in this combo (evaluated before target)
        -- multiplied by the number of permutations of siblings not in this combo (evaluated after target).
        local numPermutationsThisCombo = M.Factorial(#combo) * M.Factorial(#siblingChances - #combo)

        weightedChanceSum = weightedChanceSum + (weightedChance * numPermutationsThisCombo)
    end

    return weightedChanceSum / numPermutationsTotal
end

-- Forestry provides a chance of getting a given mutation from a given set of parents (call this "p"). This is also viewable in NEI in-game.
-- However, p is *not* the true chance of getting that mutation from that set of parents because multiple sets of mutations exist.
-- Internally, if Forestry decides that a species mutation will occur, it shuffles the list of possible child mutations to a random order,
-- then iterates over this order. On each iteration, there is a chance p for that mutation to "succeed". The *first* mutation to "succeed"
-- is chosen as the resulting child, and no other mutations later in the list are evaluated.
-- Therefore, for a given permutation of the list, the chance of the target mutation actually resulting is equal to p times the chance of all
-- mutations evaluated *before* the target *not* occurring. Thus, the *true* chance of the target mutation occurring (given that a mutation
-- *is* occurring) is the sum of chances of occurence *in each permutation* times the probability of *that permutation actually appearing*.
-- 
-- Just because each permutation of the evaluation order is equally likely (Forestry uses a Fisher-Yates shuffle), that does *not*
-- mean that p is equal to the true chance! (consider the simple example of a 0.25 target mutation and a 0.5 non-target mutation)
---@param target string
---@param siblings string[]
---@param chances table<string, number>  Mappings of species to "NEI" mutation chance.
---@return number, number  -- targetMutChance, nonTargetMutChance
function M.CalculateMutationChances(target, siblings, chances)
    if #siblings == 0 then
        return 0.0, 0.0
    end

    local permutations = M.ComputePermutations(siblings)

    -- For each permutation, calculate the probability of getting a target or non-target and add the probability to the total sum.
    -- Then, divide that sum by the total number of permutations to get the true probability of that event happening.
    -- TODO: Are there significant floating point problems here?
    local targetMutChanceSum = 0.0
    local nonTargetMutChanceSum = 0.0
    for _, permutation in ipairs(permutations) do
        local noPriorMutChance = 1.0
        for _, species in ipairs(permutation) do
            -- Chance of this mutation happening is equal to the chance that no prior mutation happened
            -- times the chance that this mutation happens.
            if species == target then
                targetMutChanceSum = targetMutChanceSum + (noPriorMutChance * chances[species])
            else
                nonTargetMutChanceSum = nonTargetMutChanceSum + (noPriorMutChance * chances[species])
            end

            -- Update the no-prior-mutation chance for the next item with the chance that this mutation didn't happen.
            noPriorMutChance = noPriorMutChance * (1.0 - chances[species])
        end
    end
    targetMutChanceSum = targetMutChanceSum / #permutations
    nonTargetMutChanceSum = nonTargetMutChanceSum / #permutations

    return targetMutChanceSum, nonTargetMutChanceSum
end

-- Calculates the probability of the given parent alleles mutating into the target and mutating into a species that is not the target.
---@param parent1 string
---@param parent2 string
---@param target string
---@param beeGraph SpeciesGraph
---@return number, number  -- targetMutationProbability, nonTargetMutationProbability
function M.CalculateBreedInfo(parent1, parent2, target, beeGraph)
    local parent1Node = beeGraph[parent1]

    -- Fetch each possible child mutation and their "NEI" chances from these parents.
    local siblings = {}
    local childMutationChances = {}
    for result, info in pairs(parent1Node.childMutations) do
        for _, v in ipairs(info) do
            if v.parent == parent2 then
                childMutationChances[result] = v.chance
                table.insert(siblings, result)
            end
        end
    end

    return M.CalculateMutationChances(target, siblings, childMutationChances)
end

return M
