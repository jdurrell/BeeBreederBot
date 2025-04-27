-- This module contains strategies for deleting drones as the drone chest fills up to capacity.
local M = {}

local AnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

---@alias GarbageCollector fun(droneStackList: AnalyzedBeeStack[], minDronesToClear: integer): integer[]

---@param target string
---@return GarbageCollector
function M.ClearDronesByFertilityPurityStackSizeCollector(target)
    return function (droneStackList, minDronesToClear)
        return M.GenericLowestScoreRemoval(
            droneStackList,
            minDronesToClear,
            function (droneStack)
                local numTargetAlleles = (
                    (((droneStack.individual.active.species.uid == target) and 1) or 0) +
                    (((droneStack.individual.inactive.species.uid == target) and 1) or 0)
                )
                return (numTargetAlleles << 6) + droneStack.size
            end,
            function (droneStack)
                return ((droneStack.individual.active.fertility < 2) or (droneStack.individual.inactive.fertility < 2))
            end
        )
    end
end

---@param targetTraits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@return GarbageCollector
function M.ClearDronesByFurthestAlleleMatchingCollector(targetTraits)
    return function (droneStackList, minDronesToClear)
        return M.GenericLowestScoreRemoval(
            droneStackList,
            minDronesToClear,
            function (droneStack)
                -- Avoid garbage-collecting the starter drone stacks so that we don't forever lose the traits from the population.
                if (droneStack.slotInChest == 1) or (droneStack.slotInChest == 2) then
                    return 1 << 20
                end

                local numTraitsAtLeastOneAllele = 0
                local totalNumMatchingAlleles = 0
                for trait, value in pairs(targetTraits) do
                    local numberMatchingAllelesOfTrait = AnalysisUtil.NumberOfMatchingAlleles(droneStack.individual, trait, value)

                    if numberMatchingAllelesOfTrait >= 1 then
                        numTraitsAtLeastOneAllele = numTraitsAtLeastOneAllele + 1
                    end
                    totalNumMatchingAlleles = totalNumMatchingAlleles + numberMatchingAllelesOfTrait
                end

                local score = 0

                -- We want to try to ensure that we don't accidentally breed any target traits out of the population, so prioritize
                -- getting as many traits with a target allele as possible.
                score = score + numTraitsAtLeastOneAllele << 5

                -- Then, prioritize getting the maximum number of target alleles to eventually get pure-breds.
                score = score + totalNumMatchingAlleles

                return score
            end,
            function (droneStack)
                return (
                    (droneStack.individual ~= nil) and
                    ((droneStack.individual.active.fertility < 2) or (droneStack.individual.inactive.fertility < 2)) and
                    ((targetTraits.fertility == nil) or targetTraits.fertility > 1)
                )
            end
        )
    end
end

---@param droneStackList AnalyzedBeeStack[]
---@param minDronesToClear integer
---@param scoreFunction ScoreFunction
---@param shouldAutoRemove fun(droneStack: AnalyzedBeeStack): boolean
---@return integer[]
function M.GenericLowestScoreRemoval(droneStackList, minDronesToClear, scoreFunction, shouldAutoRemove)
    local slotsToRemove = {}

    local worstScores = {}
    local worstScoreIndices = {}
    for _, droneStack in ipairs(droneStackList) do
        if droneStack.individual == nil then
            goto continue
        end

        if shouldAutoRemove(droneStack) then
            -- TODO: Add a way to override this for cases where we are starting with a low-fertility drone and breeding the fertility trait in.
            -- Always clear drones that have any allele with fertility less than 2.
            table.insert(slotsToRemove, droneStack.slotInChest)
            if #worstScores > (minDronesToClear - #slotsToRemove) then
                table.remove(worstScores)
                table.remove(worstScoreIndices)
            end
            goto continue
        end

        if #slotsToRemove >= minDronesToClear then
            -- No reason to try to remove other drones if we're already making enough room.
            -- Still continue in case we need to auto-remove any, though.
            goto continue
        end

        local score = scoreFunction(droneStack)

        local insertionIdx = #worstScores + 1
        while insertionIdx > 1 do
            if score > worstScores[insertionIdx - 1] then
                break
            end

            insertionIdx = insertionIdx - 1
        end
        if insertionIdx <= (minDronesToClear  - #slotsToRemove) then
            if #worstScores >= (minDronesToClear  - #slotsToRemove) then
                table.remove(worstScores, #worstScores)
                table.remove(worstScoreIndices, #worstScoreIndices)
            end

            -- For large `minDronesToClear`, this is very inefficient since it could require shifting every element of `minDronesToClear`.
            -- However, `minDronesToClear` is likely small (no greater than 4), so this is probably faster than the overhead of a more complex structure.
            table.insert(worstScores, insertionIdx, score)
            table.insert(worstScoreIndices, insertionIdx, droneStack.slotInChest)
        end
        ::continue::
    end

    for _, idx in ipairs(worstScoreIndices) do
        table.insert(slotsToRemove, idx)
    end

    return slotsToRemove
end

return M
