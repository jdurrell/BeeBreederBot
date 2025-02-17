-- This module encapsulates various common operations that involve the robot communicating with the server.

require("Shared.Shared")

---@class RobotComms
---@field comm CommLayer
---@field serverAddr string
local RobotComms = {}

---@param expectedCode MessageCode
---@param response any
---@param shouldHavePayload boolean
---@return boolean
function RobotComms:ValidateExpectedResponse(expectedCode, response, shouldHavePayload)
    if response == nil then
        Print("Got unexpected nil response when expecting response of type " .. tostring(expectedCode) .. ".")
        return false
    end

    if response.code == CommLayer.MessageCode.CancelRequest then
        Print("Received cancellation request.")
        return false
    end

    if response.code ~= expectedCode then
        Print("Got unexpected response of type " .. tostring(response.code) .. ". Expected response of type " .. tostring(expectedCode) .. ".")
        return false
    end

    if shouldHavePayload and (response.payload == nil) then
        Print("Got unexpected nil payload in response of type " .. tostring(response.code) .. ".")
        return false
    end

    return true
end

---@return string addr  The address of the server that responded to the ping.
function RobotComms:EstablishComms()
    Print("Establishing conection to server...")

    local tid = math.floor(math.random(65535))
    local payload = {transactionId=tid}
    self.comm:SendMessage(nil, CommLayer.MessageCode.PingRequest, payload)

    while true do
        local response, addr = self.comm:GetIncoming(nil)
        if self:ValidateExpectedResponse(CommLayer.MessageCode.PingResponse, response, true) then
            response = UnwrapNull(response)
            if response.payload.transactionId == tid then
                return UnwrapNull(addr)
            else
                Print("Got unexpected ping response with transaction id " .. tostring(response.payload.transactionId) .. ".")
            end
        end

        -- If the response wasn't a PingResponse to our message, then it was some old message that we just happened to get.
        -- We should just continue (clean it out of the queue) and ignore it since it was intended for a previous instance of this program.
    end
end

---@return BreedPathNode[] | nil
function RobotComms:GetBreedPathFromServer()
    ::restart::
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.PathRequest, nil)

    local response, _ = self.comm:GetIncoming(5.0)
    if response == nil then
        self:EstablishComms()
        goto restart
    elseif not self:ValidateExpectedResponse(CommLayer.MessageCode.PathResponse, response, true) then
        return nil
    end

    return UnwrapNull(response).payload
end

---@param species string
---@return Point | nil
function RobotComms:GetStorageLocationFromServer(species)
    ::restart::
    local payload = {species=species}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.LocationRequest, payload)

    local response, _ = self.comm:GetIncoming(5.0)
    if response == nil then
        self:EstablishComms()
        goto restart
    elseif not self:ValidateExpectedResponse(CommLayer.MessageCode.LocationResponse, response, true) then
        return nil
    end

    return UnwrapNull(response).payload.loc
end

---@param target string
---@return table<string, table<string, number>> | nil
function RobotComms:GetBreedInfoFromServer(target)
    ::restart::
    local payload = {target=target}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.BreedInfoRequest, payload)

    local response, _ = self.comm:GetIncoming(5.0)
    if response == nil then
        self:EstablishComms()
        goto restart
    end
    if not self:ValidateExpectedResponse(CommLayer.MessageCode.BreedInfoResponse, payload, true) then
        return nil
    end

    return UnwrapNull(response).payload
end

---@param node StorageNode
function RobotComms:ReportSpeciesFinishedToServer(node)
    -- Report the update to the server.
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.SpeciesFoundRequest, node)

    -- TODO: Do we need an ACK for this?
end

-- TODO: Find a replacement for this concept. Using this function is probably architecturally unsound since it could cause us to drop another message.
---@return boolean
function RobotComms:PollForCancel()
    local response, _ self.comm:GetIncoming(0)
    if response == nil then
        return false
    end

    return response.code == CommLayer.MessageCode.CancelRequest
end

---@param chestArray table<string, StorageNode>
function RobotComms:SendLogToServer(chestArray)
    for species, storageNode in pairs(chestArray) do
        local payload = {species=species, node=storageNode}
        self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.SpeciesFoundRequest, payload)

        -- Give the server time to actually process instead of just blowing up its buffer.
        Sleep(0.2)
    end
end

-- Fetches the server's entire log.
---@return StorageInfo | nil
function RobotComms:RetrieveLogFromServer()
    ::restart::
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.LogStreamRequest, nil)

    local serverLog = {}
    while true do
        local response, _ = self.comm:GetIncoming(5.0)
        if response == nil then
            self:EstablishComms()
            goto restart
        elseif not self:ValidateExpectedResponse(CommLayer.MessageCode.LogStreamResponse, response, true) then
            return nil
        end

        if response.payload == {} then
            -- This is the last message, so we are done.
            break
        end

        ---@type LogStreamResponsePayload
        local data = response.payload
        serverLog[data.species] = data.node
    end

    return serverLog
end

-- Closes the communications to the server.
function RobotComms:Shutdown()
    -- TODO: Should we fire off a "shutting down" message to the server?

    if self.comm ~= nil then
        self.comm:Close()
    end
end

-- Creates a RobotComms object.
---@param modemLib any
---@param serializationLib any
---@param port integer
---@return RobotComms | nil
function RobotComms:Create(modemLib, serializationLib, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    local comm = CommLayer:Open(modemLib, serializationLib, port)
    if comm == nil then
        Print("Failed to open CommLayer during RobotComms initialization.")
        return nil
    end
    obj.comm = comm

    obj.serverAddr = obj:EstablishComms()

    return obj
end

return RobotComms
