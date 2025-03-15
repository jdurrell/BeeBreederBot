-- This module contains algorithms for selecting the right drone to use with a given princess during the breeding process.
local M = {}
local MatchingMath = require("BeekeeperBot.MatchingMath")

---@alias Matcher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]): integer
---@alias StackFinisher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]): {princess: integer | nil, drones: integer | nil}
---@alias ScoreFunction fun(droneStack: AnalyzedBeeStack): number

---@param target string
---@param breedInfo BreedInfoCache
---@param traitInfo TraitInfoSpecies
---@return Matcher
function M.HighFertilityAndAllelesMatcher(target, breedInfo, traitInfo)
    return function (princessStack, droneStackList)
        return M.GenericHighestScore(
            droneStackList,
            function (droneStack)
                -- Always attempt to choose a drone with which the princess has a chance to produce a target allele.
                -- If one exists, then prioritize fertility above all else.
                local score = MatchingMath.CalculateExpectedNumberOfTargetAllelesPerOffspring(
                    target, princessStack.individual, droneStack.individual, breedInfo[target], traitInfo
                )
                if score > 0 then
                    -- TODO: This should still filter for zero fertility.
                    score = score + (10000 * (droneStack.individual.active.fertility + droneStack.individual.inactive.fertility))
                end

                return score
            end
        )
    end
end

---@param targetTraits AnalyzedBeeTraits
---@return Matcher
function M.ClosestMatchToTraitsMatcher(targetTraits)
    local maxScore = 0
    for trait, value in pairs(targetTraits) do
        if trait == "fertility" then
            if value < 2 then
                maxScore = maxScore + 2
            else
                maxScore = maxScore + (2 << 14)
            end
        else
            maxScore = maxScore + (4 << 10)
            maxScore = maxScore + (4 << 6)
            maxScore = maxScore + (4 << 2)
        end
    end

    return function (princessStack, droneStackList)
        return M.GenericHighestScore(
            droneStackList,
            function (droneStack)
                ---@param bee AnalyzedBeeIndividual
                ---@param trait string
                ---@return integer
                local function numberOfMatchingAlleles(bee, trait)
                    return (
                        (((bee.active[trait] == targetTraits[trait]) and 1) or 0) +
                        (((bee.inactive[trait] == targetTraits[trait]) and 1) or 0)
                    )
                end

                local score = 0

                -- If breeding for high fertility, then this should always takes highest priority.
                -- If breeding for low fertility, then this should always take lowest priority.
                -- This ensures safer convergence by giving us more chances for better offspring.
                local matchingFertilityAlleles = numberOfMatchingAlleles(droneStack.individual, "fertility")
                if targetTraits.fertility > 1 then
                    score = score + (matchingFertilityAlleles << 14)
                else
                    score = score + matchingFertilityAlleles
                end

                local numTraitsAtLeastOneAllele = 0
                local numTraitsAtLeastTwoAlleles = 0
                local totalNumMatchingAlleles = 0
                for trait, _ in pairs(targetTraits) do
                    if trait == "fertility" then
                        goto continue
                    end

                    local numberMatchingAllelesOfTrait = numberOfMatchingAlleles(droneStack.individual, trait) + numberOfMatchingAlleles(princessStack.individual, trait)

                    if numberMatchingAllelesOfTrait >= 1 then
                        numTraitsAtLeastOneAllele = numTraitsAtLeastOneAllele + 1
                    end
                    if numberMatchingAllelesOfTrait >= 2 then
                        numTraitsAtLeastTwoAlleles = numTraitsAtLeastTwoAlleles + 1
                    end
                    totalNumMatchingAlleles = totalNumMatchingAlleles + numberMatchingAllelesOfTrait
                    ::continue::
                end

                -- We want to try to ensure that we don't accidentally breed any target traits out of the population, so prioritize
                -- getting as many traits with a target allele as possible.
                score = score + numTraitsAtLeastOneAllele << 10
                score = score + numTraitsAtLeastTwoAlleles << 6

                -- Lastly, prioritize getting the maximum number of target alleles to eventually get pure-breds.
                score = score + totalNumMatchingAlleles << 2

                return score
            end,
            maxScore
        )
    end
end

-- Generic function to wrap algorithms that calculate a score for each drone and pick the one with the highest score.
-- `scoreFunc` must only return values greater than or equal to 0.
---@param scoreFunc ScoreFunction
---@param maxPossibleScore number | nil
function M.GenericHighestScore(droneStackList, scoreFunc, maxPossibleScore)
    local maxDroneStack
    local maxScore = -1
    for _, droneStack in ipairs(droneStackList) do
        -- This doesn't really happen in production, but it helps avoid some nasty recomputation in the simulator.
        if droneStack.individual == nil then
            goto continue
        end

        local score = scoreFunc(droneStack)
        if score > maxScore then
            maxDroneStack = droneStack
            maxScore = score
            if maxScore == maxPossibleScore then
                break
            end
        end
        ::continue::
    end

    if maxDroneStack == nil then
        return -1
    end

    return maxDroneStack.slotInChest
end

-- Returns a stack finisher that returns the slot of the finished stack in ANALYZED_DRONE_CHEST if a full stack
-- of drones of the given species has been found. Otherwise, the stack finisher returns nil.
---@param target string
---@return StackFinisher
function M.FullDroneStackOfSpeciesPositiveFertilityFinisher(target)
    return function (princessStack, droneStackList)
        for _, droneStack in ipairs(droneStackList) do
            -- TODO: It is possible that drones will have a bunch of different traits and not stack up. We will need to decide whether we want to
            --       deal with this possibility or just force them to stack up. For now, it is simplest to force them to stack.
            if (droneStack.individual ~= nil) and (droneStack.individual.active.fertility >= 2) and
                (droneStack.individual.inactive.fertility >= 2) and M.isPureBred(droneStack.individual, target) and droneStack.size == 64 then

                -- If we have a full stack of our target, then we are done.
                return {drones = droneStack.slotInChest}
            end
        end

        return {}
    end
end

-- Returns whether the bee represented by the given stack is a pure bred version of the given species.
---@param individual AnalyzedBeeIndividual
---@param species string
---@return boolean
function M.isPureBred(individual, species)
    return (individual.active.species.uid == species) and (individual.active.species.uid == individual.inactive.species.uid)
end

return M
