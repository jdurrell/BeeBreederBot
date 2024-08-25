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
    CancelResponse = 5,
    SpeciesFoundRequest = 6,
    SpeciesFoundResponse = 7,
    BreedInfoRequest = 8,
    BreedInfoResponse = 9
}

function Sleep(time)
    -- os.sleep() only exists inside OpenComputers, so outside IntelliSense doesn't recognize it.
    ---@diagnostic disable-next-line: undefined-field
    os.sleep(time)
end