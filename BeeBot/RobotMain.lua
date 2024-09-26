-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.


---------------------
-- Global variables.

-- Load Dependencies.
Component = require("component")
Event = require("event")
Sides = require("sides")
Robot = Component.robot
BK = Component.beekeeper
IC = Component.inventory_controller
Modem = Component.modem
dofile("/home/BeeBreederBot/Shared.lua")
dofile("/home/BeeBreederBot/BreederOperation.lua")
dofile("/home/BeeBreederBot/RobotComms.lua")

ServerAddress = nil
E_NOERROR          = 0
E_TIMEDOUT         = -1
E_CANCELLED        = -2
E_SENDFAILED       = -3  -- We'll throw this error for send failures, but I don't see how this could happen or how to deal with it. Running out of power, maybe?
E_NOPRINCESS       = -4
E_GOTENOUGH_DRONES = 1
E_NOTARGET         = 2

-- Order of species to breed.
BreedPath = {}

-- Slots for holding items in the robot.
PRINCESS_SLOT = 1
DRONE_SLOT    = 2
NUM_INTERNAL_SLOTS = 16

-- Info for chests for analyzed bees at the start of the apiary row.
ANALYZED_PRINCESS_CHEST = Sides.left
ANALYZED_DRONE_CHEST    = Sides.right
BASIC_CHEST_INVENTORY_SLOTS = 27

-- Info for chests in the storage row.
LOG_FILE = "/home/BeeBreederBot/DroneLocations.log"
StorageInfo = {
    nextChest = {
        x = 0,
        y = 0
    },
    chestArray = {}
}


---------------------
-- Initial Setup.
local listenPortOpened = Modem.open(COM_PORT)
if not listenPortOpened then
    print("Error: Failed to open communication port.")
    os.exit(1, true)
end

math.randomseed(os.time())
ServerAddress = EstablishComms()
print("Received ping response from bee-graph server at " .. ServerAddress)

FoundSpecies = ReadSpeciesLogFromDisk(LOG_FILE)
if FoundSpecies == nil then
    print("Got nil when reading species Log.")
    os.exit(0)
end

local retval
retval = SyncLogWithServer(ServerAddress, FoundSpecies)
if retval ~= E_NOERROR then
    print("Got error while attempting to sync log with server.")
    os.exit(0)
end

retval, BreedPath = GetBreedPathFromServer(ServerAddress)

---------------------
-- Main operation loop.
for i, v in ipairs(BreedPath) do
    ::retry::
    local breedInfo
    retval, breedInfo = GetBreedInfoFromServer(ServerAddress, v)
    if retval == E_TIMEDOUT then
        print("Error: Lost communication with the server.")

        ServerAddress = EstablishComms()
        goto retry
    elseif retval == E_CANCELLED then
        os.exit(E_CANCELLED, true)
    end

    -- Breed the target.
    while true do
        if PollForCancel(ServerAddress) then
            os.exit(E_CANCELLED, true)
        end

        retval = PickUpBees(v, breedInfo)
        if retval == E_NOERROR then
            WalkApiariesAndStartBreeding()
        elseif retval == E_GOTENOUGH_DRONES then
            -- If we have enough of the target species now, then clean up and break out.
            local node = StoreSpecies(v, LOG_FILE, StorageInfo)
            ReportSpeciesFinishedToServer(ServerAddress, node)
            break
        elseif retval == E_NOPRINCESS then
            -- Otherwise, just hang out for a little while.
            Sleep(5.0)
        else
            print("Got unknown return code from the princess-drone matcher.")
        end
    end
end
