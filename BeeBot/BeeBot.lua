-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.

-- Import BeeBreederBot libraries.
require("Shared.Shared")
local BreederOperation = require("BeeBot.BreederOperation")
local RobotComms = require("BeeBot.RobotComms")
local Logger = require("Shared.Logger")

---@class BeeBot
---@field beekeeper any
---@field component any
---@field event any
---@field inventoryController any
---@field modem any
---@field robot any
---@field serial any
---@field sides any
---@field breeder BreedOperator
---@field robotComms RobotComms
local BeeBot = {}

E_NOERROR          = 0
E_NOPRINCESS       = -4
E_GOTENOUGH_DRONES = 1
E_NOTARGET         = 2

---@param code integer
function BeeBot:Shutdown(code)
    if self.robotComms ~= nil then
        self.robotComms:Shutdown()
    end

    ExitProgram(code)
end

-- Creates a BeeBot and does initial setup.
-- Requires system libraries as an input.
---@param componentLib any
---@param eventLib any
---@param serialLib any
---@param port integer
---@return BeeBot
function BeeBot:Create(componentLib, eventLib, serialLib, sidesLib, logFilepath, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- This is used for transaction IDs when pinging the server.
    math.randomseed(os.time())

    -- Store away system libraries.
    -- Do this in the constructor instead of statically so that we can inject our
    -- own system libraries for testing.
    obj.event = eventLib
    obj.sides = sidesLib

    if componentLib.beekeeper == nil then
        Print("Couldn't find 'beekeeper' in the component library.")
        obj:Shutdown(1)
    end
    obj.beekepeer = componentLib.beekeeper

    if componentLib.inventory_controller == nil then
        Print("Couldn't find 'inventory_controller' in the component library.")
        obj:Shutdown(1)
    end
    obj.inventory_controller = componentLib.inventory_controller

    if componentLib.robot == nil then
        Print("Couldn't find 'robot' in the component library.")
        obj:Shutdown(1)
    end
    obj.robot = componentLib.robot

    if componentLib.modem == nil then
        Print("Couldn't find 'modem' in the component library.")
        obj:Shutdown(1)
    end

    local robotComms = RobotComms:Create(componentLib.modem, serialLib, port)
    if robotComms == nil then
        Print("Failed to initialize RobotComms during BeeBot initialization.")
        obj:Shutdown(1)
    end
    obj.robotComms = UnwrapNull(robotComms)

    local breeder = BreederOperation:Create(componentLib.beekeeper, componentLib.inventory_controller, sidesLib, obj.robotComms)
    if breeder == nil then
        Print("Failed to initialize breeding operator.")
        obj:Shutdown(1)
    end
    obj.breeder = breeder

    return obj
end

-- Runs the main BeeBot operation loop.
function BeeBot:RunRobot()
    while true do
        -- Poll the server until it has a path to breed for us.
        -- TODO: It might be better for the server to actively command this.
        local breedPath = {}
        while breedPath == {} do
            local path = self.robotComms:GetBreedPathFromServer()
            if path == nil then
                Print("Unexpected error when retrieving breed path from server.")
                self:Shutdown(1)
            end
            breedPath = UnwrapNull(path)
        end

        -- Breed the commanded species based on the given path.
        for _, v in ipairs(breedPath) do
            if v.parent1 ~= nil then
                self.breeder:ReplicateSpecies(v.parent1)
            end

            if v.parent2 ~= nil then
                self.breeder:ReplicateSpecies(v.parent2)
            end

            self.breeder:BreedSpecies(v.target, v.parent1, v.parent2)
        end
    end
end

return BeeBot
