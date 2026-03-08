---@alias StorageCacheEntry {traits: AnalyzedBeeTraits, stackSize: integer, slot: integer, chestNumber: integer}

local BeeAnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

-- Caches relevant information for drones in the storage row.
-- TODO: If tight on robot memory, we could provide an implementation that stores this on the server.
---@class StorageRowCache
---@field ic any inventory controller library
---@field robot any robot library
---@field sides any sides library
---@field cache StorageCacheEntry[]
local StorageRowCache = {}

-- Creates and returns a new StorageRowCache.
---@return StorageRowCache
function StorageRowCache:Create()
    return {};
end

-- Clears the cache.
function StorageRowCache:Clear()
    self.cache = {}
end

-- Returns whether the cache is empty.
---@return boolean
function StorageRowCache:IsEmpty()
    return #(self.cache) == 0
end

-- Adds the given drone to the cache.
---@param drone AnalyzedBeeStack
---@param chestNumber integer
function StorageRowCache:LoadDrone(drone, chestNumber)
    -- All of the drones in the storage row should be pure-bred, so we only need to store one set of traits.
    table.insert(self.cache, {
        traits=drone.individual.active,
        stackSize=drone.size,
        slot=drone.slotInChest,
        chestNumber=chestNumber,
    })
end

-- Removes the drone in the given chest and slot from the cache.
---@param chestNumber integer
---@param slot integer
function StorageRowCache:RemoveDrone(chestNumber, slot)
    for i, v in ipairs(self.cache) do
        if (v.chestNumber == chestNumber) and (v.slot == slot) then
            table.remove(self.cache, i)
            return
        end
    end
end

--- If a drone stack with the requested traits exists, then returns the entry corresponding to that drone.
--- If no drone stack exists, then returns nil.
---@param traits AnalyzedBeeTraits | PartialAnalyzedBeeTraits
---@return StorageCacheEntry | nil
function StorageRowCache:GetDroneEntry(traits)
    for i, v in ipairs(self.cache) do
        if BeeAnalysisUtil.HasAllTraits(v.traits, traits) then
            return v
        end
    end

    return nil
end
