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

ServerAddress = nil
E_NOERROR          = 0
E_TIMEDOUT         = -1
E_CANCELLED        = -2
E_SENDFAILED       = -3  -- We'll throw this error for send failures, but I don't see how this could happen or how to deal with it. Running out of power, maybe?
E_NOPRINCESS       = -4
E_GOTENOUGH_DRONES = 1
E_NOTARGET         = 2

-- Slots for holding items in the robot.
PRINCESS_SLOT = 1
DRONE_SLOT    = 2
NUM_INTERNAL_SLOTS = 16

-- Info for chests for analyzed bees at the start of the apiary row.
ANALYZED_PRINCESS_CHEST = Sides.left
ANALYZED_DRONE_CHEST    = Sides.right
BASIC_CHEST_INVENTORY_SLOTS = 27

-- Info for chests in the storage row.
StorageInfo = {
    nextChest = {
        x = 0,
        y = 0
    },
    chestArray = {}
}


---@param species string
function LogSpeciesFinishedToDisk(species)
    local logfile = io.open("species.log", "w")
    if logfile == nil then
        -- We can't really handle this error. Just print it out and move on.
        print("Failed to get logfile species.log.")
        return
    end

    logfile:write(species + "\n")
    logfile:flush()
    logfile:close()
end

---@return string | nil address The address of the server that responded to the ping.
function PingServerForStartup()
    local transactionId = math.floor(math.random(65535))
    local payload = {transactionId = transactionId}
    local sent = Modem.broadcast(COM_PORT, MessageCode.PingRequest, payload)
    if not sent then
        return nil
    end
    while true do
        local event, _, addr, _, _, code, tid = Event.pull(10, "modem_message")
        if event == nil then
            -- We timed out.
            return nil
        elseif (code == MessageCode.PingResponse) and (transactionId == tid) then
            return addr
        end
        -- If the response wasn't a PingResponse to our message, then it was some old message that we just happened to get.
        -- We should just continue (clean it out of the queue) and ignore it since it was intended for a previous instance of this program.
    end
end

function WaitUntilCommsReEstablished()
    local retval = nil
    while retval ~= E_NOERROR do
        retval = PingServerForStartup()
    end
end

---@return integer, string, table<string, table<string>>
function GetTargetFromServer()
    local sent = Modem.send(ServerAddress, COM_PORT, MessageCode.TargetRequest)
    if not sent then
        return E_SENDFAILED, "", {}
    end

    local event, _, _, _, _, code, payload = Event.pull(10, "modem_message")
    if event == nil then
        -- Timed out.
        return E_TIMEDOUT, "", {}
    end

    if code ~= MessageCode.TargetResponse then
        -- This only ever happens if the server tells the robot to cancel.
        return E_CANCELLED, "", {}
    end

    if payload == nil then
        -- We have no other target to breed.
        return E_NOTARGET, "", {}
    end

    -- TODO: Check if it's possible for breedInfo to be more than the 8kB message limit.
    --       If so, then we will need to sequence these responses to build the full table before returning it.
    return E_NOERROR, payload.target, payload.breedInfo
end

---@param species string
---@return integer
function ReportSpeciesFinishedToServer(species)
    -- Write to our own local logfile in case the server is down and we need to sync later.
    LogSpeciesFinishedToDisk(species)

    -- Report the update to the server.
    local sent = Modem.send(ServerAddress, COM_PORT, MessageCode.SpeciesFoundRequest, species)
    if not sent then
        return E_SENDFAILED
    end

    local event, _, _, _, _, code = Event.pull(10, "modem_message")
    if event == nil then
        return E_TIMEDOUT
    elseif code == MessageCode.CancelRequest then
        return E_CANCELLED
    end

    return E_NOERROR
end

---@return boolean
function PollForCancel()
    local event, _, _, _, _, code = Event.pull(0, "modem_message")
    local cancelled = (event ~= nil) and (code == MessageCode.CancelRequest)

    if cancelled then
        local sent = Modem.send(ServerAddress, COM_PORT, MessageCode.CancelResponse)
        if not sent then
            -- Not really anything we can do here, I think.
            print("Failed to send Cancel response.")
            return true
        end
    end

    return cancelled
end


---------------------
-- Initial Setup.
local listenPortOpened = Modem.open(COM_PORT)
if not listenPortOpened then
    print("Error: Failed to open communication port.")
    os.exit(1, true)
end

math.randomseed(os.time())
while ServerAddress == nil do
    print("Querying server address...")
    ServerAddress = PingServerForStartup()
end
print("Received ping response from bee-graph server at " .. ServerAddress)

-- TODO: Load our current state of bees bred here.


---------------------
-- Main operation loop.
while true do
    local retval, target, breedInfo = GetTargetFromServer()
    if retval == E_TIMEDOUT then
        print("Error: Lost communication with the server.")

        WaitUntilCommsReEstablished()
        goto continue
    elseif (retval == E_CANCELLED) or (retval == E_NOTARGET) then
        -- Not really anything to do here except sit around and periodically query for another target.
        Sleep(10.0)
        goto continue
    end

    while true do
        if PollForCancel() then
            break
        end

        retval = PickUpBees(target, breedInfo)
        if retval == E_NOERROR then
            WalkApiariesAndStartBreeding()
        elseif retval == E_GOTENOUGH_DRONES then
            -- If we have enough of the target species now, then clean up, break out, and ask the server for the next species.
            StoreSpecies(target, StorageInfo)
            ReportSpeciesFinishedToServer(target)
            break
        else
            -- Otherwise, just hang out for a little while.
            Sleep(5.0)
        end
    end

    ::continue::
end
