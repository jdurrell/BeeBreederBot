-- This module contains algorithms for selecting the right drone to use with a given princess during the breeding process.
local M = {}
local MatchingMath = require("BeekeeperBot.MatchingMath")
local AnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

---@alias Matcher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]): integer
---@alias StackFinisher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]): {princess: integer | nil, drones: integer | nil}
---@alias ScoreFunction fun(droneStack: AnalyzedBeeStack): number

-- Returns a matcher that prioritizes drones that are expected to produce the highest number of target alleles
-- with the given princess while also prioritizing the highest fertility trait available in the pool and filtering out
-- fertility of 1 or lower.
---@param targetTrait string
---@param targetValue any
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfoSpecies
---@return Matcher
function M.HighFertilityAndAllelesMatcher(targetTrait, targetValue, cacheElement, traitInfo)
    return function (princessStack, droneStackList)
        return M.GenericHighestScore(
            droneStackList,
            function (droneStack)
                -- Always attempt to choose a drone with which the princess has a chance to produce a target allele.
                -- If one exists, then prioritize fertility above all else.
                local score = MatchingMath.CalculateExpectedNumberOfTargetAllelesPerOffspring(
                    princessStack.individual, droneStack.individual, targetTrait, targetValue, cacheElement, traitInfo
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

-- Returns matcher that prioritizes drones that, when combined with the princess, give the greatest number of target alleles
-- in the two parents.
---@param targetTraits AnalyzedBeeTraits
---@return Matcher
function M.ClosestMatchToTraitsMatcher(targetTraits)
    local maxScore = 0
    for _, _ in pairs(targetTraits) do
        maxScore = maxScore + (1 << 10)
        maxScore = maxScore + (1 << 6)
        maxScore = maxScore + 4
    end

    return function (princessStack, droneStackList)
        return M.GenericHighestScore(
            droneStackList,
            function (droneStack)
                local score = 0

                local numTraitsAtLeastOneAllele = 0
                local numTraitsAtLeastTwoAlleles = 0
                local totalNumMatchingAlleles = 0
                for trait, value in pairs(targetTraits) do
                    local numberMatchingAllelesOfTrait = (
                        AnalysisUtil.NumberOfMatchingAlleles(droneStack.individual, trait, value) +
                        AnalysisUtil.NumberOfMatchingAlleles(princessStack.individual, trait, value)
                    )

                    if numberMatchingAllelesOfTrait >= 1 then
                        numTraitsAtLeastOneAllele = numTraitsAtLeastOneAllele + 1
                    end
                    if numberMatchingAllelesOfTrait >= 2 then
                        numTraitsAtLeastTwoAlleles = numTraitsAtLeastTwoAlleles + 1
                    end
                    totalNumMatchingAlleles = totalNumMatchingAlleles + numberMatchingAllelesOfTrait
                end

                -- We want to try to ensure that we don't accidentally breed any target traits out of the population, so prioritize
                -- getting as many traits with a target allele as possible.
                score = score + (numTraitsAtLeastOneAllele << 10)
                score = score + (numTraitsAtLeastTwoAlleles << 6)

                -- Lastly, prioritize getting the maximum number of target alleles to eventually get pure-breds.
                score = score + totalNumMatchingAlleles

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
                (droneStack.individual.inactive.fertility >= 2) and AnalysisUtil.IsPureBred(droneStack.individual, target) and droneStack.size == 64 then

                -- If we have a full stack of our target, then we are done.
                return {drones = droneStack.slotInChest}
            end
        end

        return {}
    end
end

-- Returns a stack finisher that returns the slot of the finished princess in ANALYZED_PRINCESS_CHEST and then slot of
-- the finished drones in ANALYZED_DRONE_CHEST if both the princess and a full stack of drones have all the target traits.
---@param targetTraits AnalyzedBeeTraits
---@return StackFinisher
function M.FullDroneStackAndPrincessOfTraitsFinisher(targetTraits)
    return function (princessStack, droneStackList)
        local princessSlot = nil
        if AnalysisUtil.AllTraitsEqual(princessStack.individual, targetTraits) then
            princessSlot = princessStack.slotInChest
        else
            return {}
        end

        for _, stack in ipairs(droneStackList) do
            if (stack.size == 64) and AnalysisUtil.AllTraitsEqual(stack.individual, targetTraits) then
                return {princess = princessSlot, drones = stack.slotInChest}
            end
        end

        return {}
    end
end

return M
