-- This module contains algorithms for selecting the right drone to use with a given princess during the breeding process.
local M = {}
local MatchingMath = require("BeeBot.MatchingMath")

---@alias Matcher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[], target: string, cacheElement: BreedInfoCacheElement, traitInfo: TraitInfo): integer
---@alias ScoreFunction fun(droneStack: AnalyzedBeeStack): number

-- Matches `princessStack` to the drone with the highest chance to immediately create at least one pure-bred target offspring drone.
---@type Matcher
function M.HighestPureBredChance(princessStack, droneStackList, target, cacheElement, traitInfo)
    return M.GenericHighestScore(
        droneStackList,
        function (droneStack)
            return MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(
                target, princessStack.individual, droneStack.individual, cacheElement, traitInfo
            )
        end,
        1
    )
end

---@type Matcher
function M.HighestAverageExpectedAllelesGenerationalPositiveFertility(princessStack, droneStackList, target, cacheElement, traitInfo)
    return M.GenericHighestScore(
        droneStackList,
        function (droneStack)
            if (droneStack.individual.active.fertility < 2) or (droneStack.individual.inactive.fertility < 2) then
                return 0
            end

            return MatchingMath.CalculateExpectedNumberOfTargetAllelesPerOffspring(
                target, princessStack.individual, droneStack.individual, cacheElement, traitInfo
            )
        end,
        2
    )
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

-- If the target has been reached, returns the slot of the finished stack in ANALYZED_DRONE_CHEST.
-- Otherwise, returns nil.
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@return integer | nil
function M.GetFinishedDroneStack(droneStackList, target)
    for _, droneStack in ipairs(droneStackList) do
        -- TODO: It is possible that drones will have a bunch of different traits and not stack up. We will need to decide whether we want to deal with this possibility
        --       or just force them to stack up. For now, it is simplest to force them to stack.
        if (droneStack.individual ~= nil) and (droneStack.individual.active.fertility >= 2) and (droneStack.individual.inactive.fertility >=2) and M.isPureBred(droneStack.individual, target) and droneStack.size == 64 then
            -- If we have a full stack of our target, then we are done.
            return droneStack.slotInChest
        end
    end

    return nil
end

-- Returns whether the bee represented by the given stack is a pure bred version of the given species.
---@param individual AnalyzedBeeIndividual
---@param species string
---@return boolean
function M.isPureBred(individual, species)
    return (individual.active.species.uid == species) and (individual.active.species.uid == individual.inactive.species.uid)
end

return M
