-- Caches relevant information for drones in the storage row.
---@class StorageRowCache
---@field ic any inventory controller library
---@field robot any robot library
---@field sides any sides library
---@field cache {traits: AnalyzedBeeTraits, stackSize: integer, slot: integer, chestNumber: integer}[]
local StorageRowCache = {}

---@return StorageRowCache
function StorageRowCache:Create()
    return {};
end

-- Clear the cache.
function StorageRowCache:Clear()
    self.cache = {}
end

---@return boolean
function StorageRowCache:IsEmpty()
    return #(self.cache) == 0
end

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
