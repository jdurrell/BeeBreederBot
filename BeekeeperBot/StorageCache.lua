---@alias StorageCacheEntry {traits: AnalyzedBeeTraits, stackSize: integer, slot: integer, chestNumber: integer}

local BeeAnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

STORAGE_CHEST_NUM_SLOTS = 54  -- We happen to be using gold chests.

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

-- Adds the given drone to the cache. This must be called in sequential order.
---@param traits AnalyzedBeeTraits
---@param amount integer
---@param chestNumber integer
---@param slot integer
---@param index integer | nil
---@return StorageCacheEntry
function StorageRowCache:LoadDrone(traits, amount, chestNumber, slot, index)
    if index == nil then index = #self.cache + 1 end

    -- All of the drones in the storage row should be pure-bred, so we only need to store one set of traits.
    table.insert(self.cache, index, {
        traits=traits,
        stackSize=amount,
        slot=slot,
        chestNumber=chestNumber,
    })

    return self.cache[index]
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

-- Allocates a new chest slot for a drone with the given traits.
---@param traits AnalyzedBeeTraits
---@return StorageCacheEntry
function StorageRowCache:AllocateSlot(traits)
    -- TODO: We need to have knowledge of a maximum number of chests here and return a failure if there are no open slots.

    -- For compaction purposes, always try to use the earliest slot.
    local nextChest = 1
    local nextSlot = 1
    for i, v in ipairs(self.cache) do
        if v.chestNumber == nextChest and v.slot ~= nextSlot then
            -- Gap within one chest.
            return self:LoadDrone(traits, 0, nextChest, nextSlot, i)
        elseif v.chestNumber ~= nextChest then
            -- Gap between chests.
            return self:LoadDrone(traits, 0, nextChest, nextSlot, i)
        end

        nextSlot = nextSlot + 1
        if nextSlot > STORAGE_CHEST_NUM_SLOTS then
            nextSlot = 1
            nextChest = nextChest + 1
        end
    end

    -- We didn't find any gaps, so just take the last one.
    return self:LoadDrone(traits, 0, nextChest, nextSlot)
end

return StorageRowCache
