---@return string | nil addr  The address of the server that responded to the ping.
function EstablishComms()
    Print("Establishing conection to server...")

    local tid = math.floor(math.random(65535))
    local payload = {transactionId=tid}
    SendMessage(nil, MessageCode.PingRequest, payload)

    while true do
        local event, _, addr, _, _, response = Event.pull(10, MODEM_EVENT_NAME)
        ---@type Message
        response = UnserializeMessage(response)
        if event == nil then
            return nil
        elseif response.code == MessageCode.PingResponse then
            ---@type PingResponsePayload
            local data = response.payload
            if (response.code == MessageCode.PingResponse) and (data.transactionId == tid) then
                return addr
            end
        end

        -- If the response wasn't a PingResponse to our message, then it was some old message that we just happened to get.
        -- We should just continue (clean it out of the queue) and ignore it since it was intended for a previous instance of this program.
        -- If we timed out, then just continue.
    end
end

---@param addr string
---@return integer, BreedPathNode[]
function GetBreedPathFromServer(addr)
    SendMessage(addr, MessageCode.PathRequest, nil)

    local event, _, _, _, _, response = Event.pull(10, MODEM_EVENT_NAME)
    if event == nil then
        -- Timed out.
        return E_TIMEDOUT, {}
    end
    UnserializeMessage(response)

    if response.code == MessageCode.CancelRequest then
        return E_CANCELLED, {}
    elseif response.code ~= MessageCode.PathResponse then
        Print("Error: Got unexpected code from the server during BreedPath query: " .. tostring(response.code))
    end

    ---@type PathResponsePayload
    local data = response.payload

    -- TODO: Check if it's possible for breedInfo to be more than the 8kB message limit.
    --       If so, then we will need to sequence these responses to build the full table before returning it.
    return E_NOERROR, data.breedInfo
end

---@param addr string
---@param target string
---@return integer, table<string, table<string, number>>
function GetBreedInfoFromServer(addr, target)
    local payload = {target=target}
    SendMessage(addr, MessageCode.BreedInfoRequest, payload)

    local event, _, _, _, _, response = Event.pull(10, MODEM_EVENT_NAME)
    if event == nil then
        -- Timed out.
        return E_TIMEDOUT, {}
    end
    response = UnserializeMessage(response)

    if response.code == MessageCode.CancelRequest then
        return E_CANCELLED, {}
    elseif response.code ~= MessageCode.BreedInfoResponse then
        return E_CANCELLED, {}
    end

    ---@type BreedInfoResponsePayload
    local breedInfo = response.payload
    return E_NOERROR, breedInfo
end

---@param addr string
---@param node StorageNode
function ReportSpeciesFinishedToServer(addr, node)
    -- Report the update to the server.
    SendMessage(addr, MessageCode.SpeciesFoundRequest, node)

    -- TODO: Do we need an ACK for this?
end

---@param addr string
---@return boolean
function PollForCancel(addr)
    local event, _, _, _, _, response = Event.pull(0, MODEM_EVENT_NAME)
    if event ~= nil then
        response = UnserializeMessage(response)
        return response.code == MessageCode.CancelRequest
    end

    return false
end

---@param addr string
---@param foundSpecies table<string, StorageNode> in/out parameter
---@return integer
function SyncLogWithServer(addr, foundSpecies)
    -- Stream our log to the server.
    for species, storageNode in pairs(foundSpecies) do
        local payload = {species=species, node=storageNode}
        SendMessage(addr, MessageCode.SpeciesFoundRequest, payload)

        -- Give the server time to actually process instead of just blowing up its buffer.
        Sleep(0.2)
    end

    -- Now request the server's log and update our local state.
    SendMessage(addr, MessageCode.LogStreamRequest, nil)

    while true do
        local event, _, _, _, _, response = Event.pull(2.0, MODEM_EVENT_NAME)
        if event == nil then
            return E_TIMEDOUT
        end
        response = UnserializeMessage(response)

        if response == nil then
            -- End of the stream.
            break
        elseif response.code == MessageCode.CancelRequest then
            return E_CANCELLED
        elseif response.code ~= MessageCode.LogStreamResponse then
            Print("Unrecognized message code while attempting to process logs.")
            return E_CANCELLED
        end

        ---@type LogStreamResponsePayload
        local data = response.payload
        if (foundSpecies[data.species] == nil) or (foundSpecies[data.species].timestamp < data.node.timestamp) then
            foundSpecies[data.species] = data.node
            LogSpeciesToDisk(LOG_FILE, data.species, data.node.loc, data.node.timestamp)
        end
    end

    return E_NOERROR
end
