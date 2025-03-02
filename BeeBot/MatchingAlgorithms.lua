-- This module contains algorithms for selecting the right drone to use with a given princess during the breeding process.
local M = {}
local MatchingMath = require("BeeBot.MatchingMath")

---@alias Matcher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[], target: string, cacheElement: BreedInfoCacheElement, traitInfo: TraitInfo): integer

-- Computes the optimal matching of the given princess and set of drones for breeding the target.
---@param princessStack AnalyzedBeeStack
---@param droneStackList AnalyzedBeeStack[]
---@param target string
---@param cacheElement BreedInfoCacheElement  map of target to parent1 to parent2 to breed chance (basically a lookup matrix for breeding chance).
---@param traitInfo TraitInfo
---@return integer droneSlot  The slot of the optimal drone in ANALYZED_DRONE_CHEST.
function M.HighestPureBredChance(princessStack, droneStackList, target, cacheElement, traitInfo)
    -- Determine the drone that has the highest chance of breeding the result when paired with the given princess.
    -- This is important because we will be making use of ignoble princesses, which start dying after they breed too much.
    -- Being efficient with their use lowers the numbers of other princesses we have to manually load into the system.
    local maxDroneStack
    local maxChance = 0.0
    for _, droneStack in ipairs(droneStackList) do
        -- This doesn't really happen in production, but it helps avoid some nasty recomputation in the simulator.
        if droneStack.individual == nil then
            goto continue
        end

        -- TODO: Is this likely to converge? Are there better methods with higher probability or fewer generations?
        -- TODO: We want to favor higher fertility of drones, but this doesn't actually do that since the number of offspring is only dependent
        --       the princess's active fertility. We especially want to prevent using drones with 1 fertility whenever possible.
        local chance = MatchingMath.CalculateChanceAtLeastOneOffspringIsPureBredTarget(target, princessStack.individual, droneStack.individual, cacheElement, traitInfo)
        if chance > maxChance then
            maxDroneStack = droneStack
            maxChance = chance
            if maxChance == 1 then
                break
            end
        end
        ::continue::
    end

    -- TODO: We will accumulate more drones than we use during the operation of this breeder, so we need to garbage-collect the chest at some point.

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
        if (droneStack.individual ~= nil) and M.isPureBred(droneStack.individual, target) and droneStack.size == 64 then
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
