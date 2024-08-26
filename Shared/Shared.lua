-- This file sets up constants that are used by both the robot and server.

-- Variables for communication between robot and server.
COM_PORT = 34000
SIGNAL_STRENGTH    = 16  -- TODO: Determine a good strength.
MODEM_EVENT_NAME = "modem_message"

---@enum MessageCodes
MessageCode = {
    PingRequest = 0,
    PingResponse = 1,
    PathRequest = 2,
    PathResponse = 3,
    CancelRequest = 4,
    -- CancelResponse = 5,        -- Do we really need to send an ACK for this?
    SpeciesFoundRequest = 6,
    -- SpeciesFoundResponse = 7,  -- Do we really need to send an ACK for this?
    BreedInfoRequest = 8,
    BreedInfoResponse = 9
}

function Sleep(time)
    -- os.sleep() only exists inside OpenComputers, so outside IntelliSense doesn't recognize it.
    ---@diagnostic disable-next-line: undefined-field
    os.sleep(time)
end

---@param filepath string
---@param species string
---@param location Point
function LogSpeciesFinishedToDisk(filepath, species, location)
    local logfile = io.open(filepath, "a")
    if logfile == nil then
        -- We can't really handle this error. Just print it out and move on.
        print("Failed to get logfile.")
        return
    end

    -- Technically, we could serialize a table and just store that, but a csv is easier to edit for a human if necessary.
    logfile:write(species .. "," .. tostring(location.x) .. "," .. tostring(location.y) .. "," .. tostring(os.time()), "\n")
    logfile:flush()
    logfile:close()
end