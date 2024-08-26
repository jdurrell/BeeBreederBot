---@return string | nil addr The address of the server that responded to the ping.
function PingServerForStartup()

end

---@return string addr  The address of the server that responded to the ping.
function EstablishComms()
    while true do
        local transactionId = math.floor(math.random(65535))
        local payload = {transactionId = transactionId}
        local sent = Modem.broadcast(COM_PORT, MessageCode.PingRequest, payload)
        if not sent then
            print("Error sending PingRequest.")
        end

        while true do
            local event, _, addr, _, _, code, tid = Event.pull(10, MODEM_EVENT_NAME)
            if (event ~= nil) and (code == MessageCode.PingResponse) and (transactionId == tid) then
                return addr
            end
            -- If the response wasn't a PingResponse to our message, then it was some old message that we just happened to get.
            -- We should just continue (clean it out of the queue) and ignore it since it was intended for a previous instance of this program.
            -- If we timed out, then just continue.
        end
    end
end

---@param addr string
---@return integer, string[]
function GetBreedPathFromServer(addr)
    local sent = Modem.send(addr, COM_PORT, MessageCode.PathRequest)
    if not sent then
        print("Failed to send PathRequest.")
        return E_SENDFAILED, {}
    end

    local event, _, _, _, _, code, data = Event.pull(10, MODEM_EVENT_NAME)
    if event == nil then
        -- Timed out.
        return E_TIMEDOUT, {}
    end

    if code == MessageCode.CancelRequest then
        return E_CANCELLED, {}
    elseif code ~= MessageCode.PathResponse then
        print("Error: Got unexpected code from the server during BreedPath query: " .. tostring(code))
    end

    if data == nil then
        -- We have no other target to breed.
        return E_NOTARGET, {}
    end

    -- TODO: Check if it's possible for breedInfo to be more than the 8kB message limit.
    --       If so, then we will need to sequence these responses to build the full table before returning it.
    return E_NOERROR, data.breedInfo
end

---@param addr string
---@param target string
---@return integer, table<string, table<string, number>>
function GetBreedInfoFromServer(addr, target)
    local payload = {target = target}
    local sent = Modem.send(addr, COM_PORT, MessageCode.BreedInfoRequest, payload)
    if not sent then
        print("Failed to send BreedInfoRequest.")
        return E_SENDFAILED, {}
    end

    local event, _, _, _, _, code, data = Event.pull(10, MODEM_EVENT_NAME)
    if event == nil then
        -- Timed out.
        return E_TIMEDOUT, {}
    end

    if code == MessageCode.CancelRequest then
        return E_CANCELLED, {}
    elseif code ~= MessageCode.BreedInfoResponse then
        return E_CANCELLED, {}
    end

    return E_NOERROR, data.breedInfo
end

---@param addr string
---@param species string
---@param location Point
function ReportSpeciesFinishedToServer(addr, species, location)
    -- Report the update to the server.
    local payload = {species = species, location = location}
    local sent = Modem.send(addr, COM_PORT, MessageCode.SpeciesFoundRequest, payload)
    if not sent then
        print("Failed to send SpeciesFoundRequest.")
    end

    -- TODO: Do we need an ACK for this?
end

---@param addr string
---@return boolean
function PollForCancel(addr)
    local event, _, _, _, _, code = Event.pull(0, MODEM_EVENT_NAME)
    local cancelled = (event ~= nil) and (code == MessageCode.CancelRequest)

    -- TOOD: Do we need to ACK this?

    return cancelled
end
