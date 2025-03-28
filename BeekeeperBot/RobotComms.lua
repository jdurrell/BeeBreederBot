-- This module encapsulates various common operations that involve the robot communicating with the server.
---@class RobotComms
---@field comm CommLayer
---@field serverAddr string
local RobotComms = {}

require("Shared.Shared")
local CommLayer = require("Shared.CommLayer")

---@param expectedCode MessageCode
---@param message any
---@param shouldHavePayload boolean
---@return boolean
function RobotComms:ValidateExpectedMessage(expectedCode, message, shouldHavePayload)
    if message == nil then
        Print("Got unexpected nil response when expecting response of type " .. tostring(expectedCode) .. ".")
        return false
    end

    if message.code == CommLayer.MessageCode.CancelCommand then
        Print("Received cancellation request.")
        return false
    end

    if message.code ~= expectedCode then
        Print("Got unexpected response of type " .. tostring(message.code) .. ". Expected response of type " .. tostring(expectedCode) .. ".")
        return false
    end

    if shouldHavePayload and (message.payload == nil) then
        Print("Got unexpected nil payload in response of type " .. tostring(message.code) .. ".")
        return false
    end

    return true
end

---@return string addr  The address of the server that responded to the ping.
function RobotComms:EstablishComms()
    Print("Establishing conection to server...")

    while true do
        local tid = math.floor(math.random(65535))
        local payload = {transactionId = tid}
        self.comm:SendMessage(nil, CommLayer.MessageCode.PingRequest, payload)

        while true do
            local response, addr = self.comm:GetIncoming(10, nil)  -- Explicitly don't filter for PingRequest to clean out old messages.
            if response == nil then
                -- If we didn't get a response, then we will need to re-send the request.
                break
            elseif (self:ValidateExpectedMessage(CommLayer.MessageCode.PingResponse, response, true) and
                (response.payload.transactionId == tid)
            ) then
                return UnwrapNull(addr)
            end

            -- If the response wasn't a PingResponse to our message, then it was some old message that we just happened to get.
            -- We should just continue (clean it out of the queue) and ignore it since it was intended for a previous request.
        end
    end
end

---@param parent1 string,
---@param parent2 string,
---@param target string
---@return BreedInfoResponsePayload | nil
function RobotComms:GetBreedInfoFromServer(parent1, parent2, target)
    ::restart::
    local payload = {parent1 = parent1, parent2 = parent2, target = target}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.BreedInfoRequest, payload)

    local response, _ = self.comm:GetIncoming(5.0, CommLayer.MessageCode.BreedInfoResponse)
    if response == nil then
        self.serverAddr = self:EstablishComms()
        goto restart
    end
    if not self:ValidateExpectedMessage(CommLayer.MessageCode.BreedInfoResponse, payload, true) then
        return nil
    end

    return UnwrapNull(response).payload
end

---@return any
function RobotComms:GetCommandFromServer()
    ::restart::
    local request, _ = self.comm:GetIncoming(60)
    if request == nil then
        self.serverAddr = self:EstablishComms()
        goto restart
    end

    return request
end

---@param species string
---@return LocationResponsePayload | nil
function RobotComms:GetStorageLocationFromServer(species)
    -- TODO: This concept probably shouldn't exist at all. Originally, it seemed simpler for the server to manage
    --       storage locations, but it is probably easier for the drone to jam drones and princesses wherever they
    --       fit in a chest row and just search for them by scanning.
    ::restart::
    local payload = {species = species}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.LocationRequest, payload)

    local response, _ = self.comm:GetIncoming(5.0, CommLayer.MessageCode.LocationResponse)
    if response == nil then
        self.serverAddr = self:EstablishComms()
        goto restart
    elseif not self:ValidateExpectedMessage(CommLayer.MessageCode.LocationResponse, response, true) then
        return nil
    end

    return UnwrapNull(response).payload
end

---@param species string
---@return boolean | nil
function RobotComms:GetTraitInfoFromServer(species)
    ::restart::
    local payload = {species = species}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.TraitInfoRequest, payload)

    local response, _ = self.comm:GetIncoming(5.0, CommLayer.MessageCode.TraitInfoResponse)
    if response == nil then
        self.serverAddr = self:EstablishComms()
        goto restart
    end
    if not self:ValidateExpectedMessage(CommLayer.MessageCode.TraitInfoResponse, response, true) then
        return nil
    end

    return UnwrapNull(response).payload.dominant
end

---@param errorMessage string
function RobotComms:ReportErrorToServer(errorMessage)
    local payload = {errorMessage = errorMessage}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.PrintErrorRequest, payload)
end

-- Reports to the server that this species has been fully bred, and returns the location where it should be stored.
---@param species string
---@return LocationResponsePayload | nil
function RobotComms:ReportNewSpeciesToServer(species)
    ::restart::
    -- Report the update to the server.
    local payload = {species = species}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.SpeciesFoundRequest, payload)

    local response, _ = self.comm:GetIncoming(5.0, CommLayer.MessageCode.LocationResponse)
    if response == nil then
        self.serverAddr = self:EstablishComms()
        goto restart
    end
    if not self:ValidateExpectedMessage(CommLayer.MessageCode.LocationResponse, response, true) then
        return nil
    end

    return UnwrapNull(response).payload
end

-- Waits for the user at the server to acknowledge that conditions associated with the given mutation have been met, if any.
---@param target string
---@param parent1 string
---@param parent2 string
---@param needsFoundation boolean
function RobotComms:WaitForConditionsAcknowledged(target, parent1, parent2, needsFoundation)
    ::restart::
    local payload = {target = target, parent1 = parent1, parent2 = parent2, promptFoundation = needsFoundation}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.PromptConditionsRequest, payload)

    local response, _ = self.comm:GetIncoming(600, CommLayer.MessageCode.PromptConditionsResponse)
    if response == nil then
        self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.PingRequest)
        self.serverAddr = self:EstablishComms()
        goto restart
    end
end

---@return boolean
function RobotComms:PollForCancel()
    local response, _ self.comm:GetIncoming(0, CommLayer.MessageCode.CancelCommand)
    if response == nil then
        return false
    end

    return true
end

-- Closes the communications to the server.
function RobotComms:Shutdown()
    -- TODO: Should we fire off a "shutting down" message to the server?

    if self.comm ~= nil then
        self.comm:Close()
    end
end

-- Creates a RobotComms object.
---@param eventLib Event | nil
---@param modemLib Modem | nil
---@param serializationLib Serialization | nil
---@param port integer
---@return RobotComms | nil
function RobotComms:Create(eventLib, modemLib, serializationLib, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    local comm = CommLayer:Open(eventLib, modemLib, serializationLib, port)
    if comm == nil then
        Print("Failed to open CommLayer during RobotComms initialization.")
        return nil
    end
    obj.comm = comm

    obj.serverAddr = obj:EstablishComms()

    return obj
end

return RobotComms
