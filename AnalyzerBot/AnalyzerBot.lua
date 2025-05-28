-- This module implements a robot that pulls bees out of an input chest, analyzes
-- them using honey and the beekeeper upgrade, and places them in an output chest.

require("Shared.Shared")

---@class AnalyzerBot
---@field beekeeperLib any
---@field robotLib any
---@field maxBeeSlot integer
---@field honeySlot integer
local AnalyzerBot = {}

-- Returns a new AnalyzerBot object or nil if the object could not be created.
---@param componentLib Component
---@param robotLib any
---@return AnalyzerBot | nil
function AnalyzerBot:Create(componentLib, robotLib)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    if not TableContains(componentLib.list(), "beekeeper") then
        Print("Failed to find 'beekeeper' component.")
        return nil
    end

    obj.beekeeperLib = componentLib.beekeeper
    obj.robotLib = robotLib

    obj.honeySlot = robotLib.inventorySize()
    obj.maxBeeSlot = robotLib.inventorySize() - 1

    return obj
end

-- Runs the main robot loop.
function AnalyzerBot:Run()
    while true do
        self:importBees()

        while not self:analyzeBeesInInventory() do
            -- Refill honey when we run out.
            self:refillHoney()
        end

        self:exportBees()
    end
end

-- Pulls as many bees as possible from the input chest into the robot's inventory.
-- Assumes that the bot is currently facing the input chest.
function AnalyzerBot:importBees()
    local slot = 1
    local canTake = true
    while canTake and (slot <= self.maxBeeSlot) do
        if self.robotLib.count(slot) == 0 then
            self.robotLib.select(slot)
            canTake = self.robotLib.suck()
        end

        slot = slot + 1
    end
end

-- Exports as many bees as possible from the robot's inventory into the output chest.
-- Assumes that the bot is currently facing the input chest.
function AnalyzerBot:exportBees()
    self.robotLib.turnRight()

    for i = 1, self.maxBeeSlot do
        self.robotLib.select(i)
        self.robotLib.drop()
    end

    self.robotLib.turnLeft()
end

-- Uses honey drops in `honeySlot` to analyze all bees in the robot's inventory.
-- Returns true when all the bees are analyzed.
---@return boolean
function AnalyzerBot:analyzeBeesInInventory()
    for i = 1, self.maxBeeSlot do
        self.robotLib.select(i)
        local result, reason = self.beekeeperLib.analyze(self.honeySlot)

        if (not result) and (reason == "No honey!") then
            return false
        end
    end

    return true
end

-- Attempts to transfer honey drops from the honey chest into `honeySlot` until either `honeySlot` contains a full stack or the chest is empty.
-- Assumes that the bot is currently facing the input chest.
function AnalyzerBot:refillHoney()
    self.robotLib.turnLeft()

    self.robotLib.select(self.honeySlot)

    -- Take honey drops from the chest until we either have a full stack or taking items is no longer successful.
    local canTake = true
    local needed = self.robotLib.space(self.honeySlot)
    while canTake and (needed > 0) do
        canTake = self.robotLib.suck(needed)
        needed = self.robotLib.space(self.honeySlot)
    end

    self.robotLib.turnRight()
end

return AnalyzerBot
