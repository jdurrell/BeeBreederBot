-- This module contains strategies for deleting drones as the drone chest fills up to capacity.
local M = {}

---@alias GarbageCollector fun(droneStackList: AnalyzedBeeStack[], minDronesToClear: integer): integer[]

---@param target string
---@return GarbageCollector
function M.ClearDronesByFertilityPurityStackSizeCollector(target)
    return function (droneStackList, minDronesToClear)
        local slotsToRemove = {}

        local worstScores = {}
        local worstScoreIndices = {}
        for _, droneStack in ipairs(droneStackList) do
            if droneStack.individual == nil then
                goto continue
            end

            if (droneStack.individual.active.fertility < 2) or (droneStack.individual.inactive.fertility < 2) then
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
                goto continue
            end

            local numTargetAlleles = (((droneStack.individual.active.species.uid == target) and 1) or 0) +
                (((droneStack.individual.inactive.species.uid == target) and 1) or 0)
            local score = (numTargetAlleles << 6) + droneStack.size

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
end

return M
