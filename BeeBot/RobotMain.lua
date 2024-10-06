-- This program is the main executable for the breeder robot.
-- The breeder robot works "in the field" and uses information queried
-- from the bee-graph server to determine pairings of princesses and drones
-- and manipulate inventories to move the bees between breeding or storage.


---------------------
-- Global variables.

-- Load Dependencies.
Component = require("component")
Event = require("event")
Serial = require("serialization")
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
PARENT1_HOLD_SLOT = 3
PARENT2_HOLD_SLOT = 4

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
print("Opening port " .. COM_PORT .. " for communications.")
local listenPortOpened = Modem.open(COM_PORT)
if not listenPortOpened then
    print("Error: Failed to open communication port.")
    Shutdown()
end

math.randomseed(os.time())
ServerAddress = EstablishComms()
if ServerAddress == nil then
    print("Timed out while attempting to establish comms with server.")
    Shutdown()
end
ServerAddress = UnwrapNull(ServerAddress)
print("Received ping response from bee-graph server at " .. ServerAddress)

StorageInfo.chestArray = ReadSpeciesLogFromDisk(LOG_FILE)
if StorageInfo.chestArray == nil then
    print("Got nil when reading species Log.")
    Shutdown()
end
StorageInfo.chestArray = UnwrapNull(StorageInfo.chestArray)

local retval
retval = SyncLogWithServer(ServerAddress, StorageInfo.chestArray)
if retval ~= E_NOERROR then
    print("Got error while attempting to sync log with server.")
    Shutdown()
end

retval, BreedPath = GetBreedPathFromServer(ServerAddress)

---------------------
-- Main operation loop.
for i, v in ipairs(BreedPath) do
    -- Move parent 1 drones to the breeding chest.
    RetrieveDronesFromChest(StorageInfo.chestArray[v.parent1].loc, 32, PARENT1_HOLD_SLOT)

    -- Breed extras of parent 1 to replace the drones we took from the chest.
    while true do
        ::retryparent1::
        local breedInfoParent1
        retval, breedInfoParent1 = GetBreedInfoFromServer(ServerAddress, v.parent1)
        if retval == E_TIMEDOUT then
            print("Error: Lost communication with the server.")

            ServerAddress = EstablishComms()
            goto retryparent1
        elseif retval == E_CANCELLED then
            os.exit(E_CANCELLED, true)
        end

        if PollForCancel(ServerAddress) then
            os.exit(E_CANCELLED, true)
        end

        retval = PickUpBees(v.parent1, breedInfoParent1)
        if retval == E_NOERROR then
            WalkApiariesAndStartBreeding()
        elseif retval == E_GOTENOUGH_DRONES then
            -- If we have enough of the parent1 species now, then clean up and break out.
            -- But only take half of them back.
            local node = StoreSpecies(v.target, LOG_FILE, StorageInfo)
            break
        elseif retval == E_NOPRINCESS then
            -- Otherwise, just hang out for a little while.
            Sleep(5.0)
        else
            print("Got unknown return code from the princess-drone matcher.")
        end
    end

    -- Move parent 2 drones to the breeding chest.
    RetrieveDronesFromChest(StorageInfo.chestArray[v.parent2].loc, 32, PARENT2_HOLD_SLOT)
    -- Breed extras of parent 2 to replace the drones we took from the chest.
    while true do
        ::retryparent2::
        local breedInfoParent2
        retval, breedInfoParent2 = GetBreedInfoFromServer(ServerAddress, v.parent2)
        if retval == E_TIMEDOUT then
            print("Error: Lost communication with the server.")

            ServerAddress = EstablishComms()
            goto retryparent2
        elseif retval == E_CANCELLED then
            os.exit(E_CANCELLED, true)
        end

        if PollForCancel(ServerAddress) then
            os.exit(E_CANCELLED, true)
        end

        retval = PickUpBees(v.parent2, breedInfoParent2)
        if retval == E_NOERROR then
            WalkApiariesAndStartBreeding()
        elseif retval == E_GOTENOUGH_DRONES then
            -- If we have enough of the target species now, then clean up and break out.
            -- But only take half of them back.
            -- local node = StoreSpecies(v.target, LOG_FILE, StorageInfo)
            -- ReportSpeciesFinishedToServer(ServerAddress, node)
            break
        elseif retval == E_NOPRINCESS then
            -- Otherwise, just hang out for a little while.
            Sleep(5.0)
        else
            print("Got unknown return code from the princess-drone matcher.")
        end
    end



    -- Breed the target using the left-over drones from both parents and the princesses
    -- implied to be created by breeding the replacements for parent 2.
    while true do
        ::retrytarget::
        local breedInfoTarget
        retval, breedInfoTarget = GetBreedInfoFromServer(ServerAddress, v.target)
        if retval == E_TIMEDOUT then
            print("Error: Lost communication with the server.")

            ServerAddress = EstablishComms()
            goto retrytarget
        elseif retval == E_CANCELLED then
            os.exit(E_CANCELLED, true)
        end

        if PollForCancel(ServerAddress) then
            os.exit(E_CANCELLED, true)
        end

        retval = PickUpBees(v.target, breedInfoTarget)
        if retval == E_NOERROR then
            WalkApiariesAndStartBreeding()
        elseif retval == E_GOTENOUGH_DRONES then
            -- If we have enough of the target species now, then clean up and break out.
            local node = StoreSpecies(v.target, LOG_FILE, StorageInfo)
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
