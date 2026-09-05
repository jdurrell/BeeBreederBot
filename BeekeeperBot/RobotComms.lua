-- This module encapsulates various common operations that involve the robot communicating with the server.
---@class RobotComms
---@field comm CommLayer
---@field serverAddr string
local RobotComms = {}

require("Shared.Shared")
local CommLayer = require("Shared.CommLayer")

---@param expectedCode MessageCode
---@param transactionId integer
---@param message any
---@param shouldHavePayload boolean
---@return boolean
local function validateExpectedMessage(expectedCode, transactionId, message, shouldHavePayload)
    if message == nil then
        Print("Got unexpected nil response when expecting response of type " .. tostring(expectedCode) .. ".")
        return false
    elseif message.code == CommLayer.MessageCode.CancelCommand then
        Print("Received cancellation request.")
        return false
    elseif message.code ~= expectedCode then
        Print("Got unexpected response of type " .. tostring(message.code) .. ". Expected response of type " .. tostring(expectedCode) .. ".")
        return false
    elseif message.transactionId ~= transactionId then
        Print("Got unexpected transaction id: " .. message.transactionId .. ". Expected transaction id: " .. transactionId)
        return false
    elseif shouldHavePayload and (message.payload == nil) then
        Print("Got unexpected nil payload in response of type " .. tostring(message.code) .. ".")
        return false
    end

    return true
end

---@return any
function RobotComms:GetCommandFromServer()
    while true do
        local request, serverAddr = self.comm:GetIncoming(nil, nil, nil)
        if request ~= nil then
            self.serverAddr = UnwrapNull(serverAddr)
            return request
        end
    end
end

---@param parent1 string,
---@param parent2 string,
---@param target string
---@return BreedInfoResponsePayload
function RobotComms:GetBreedInfoFromServer(parent1, parent2, target)
    local payload = {parent1=parent1, parent2=parent2, target=target}

    local responsePayload = nil
    while responsePayload == nil do
        local tid = self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.BreedInfoRequest, nil, payload)
        if tid ~= nil then
            local response, _ = self.comm:GetIncoming(5.0, CommLayer.MessageCode.BreedInfoResponse, self.serverAddr)
            if validateExpectedMessage(CommLayer.MessageCode.BreedInfoResponse, tid, response, true) then
                responsePayload = UnwrapNull(response).payload
            end
        end
    end

    return responsePayload
end

---@param trait string
---@param value TraitValue
---@param existingSpecies Set<string>
---@return TraitBreedPathResponsePayload | nil
function RobotComms:GetBreedPathForTraitFromServer(trait, value, existingSpecies)
    local payload = {trait=trait, value=value, existingSpecies=existingSpecies}

    local responsePayload = nil
    while responsePayload == nil do
        local tid = self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.TraitBreedPathRequest, nil, payload)
        if tid ~= nil then
            local response, _ = self.comm:GetIncoming(10, CommLayer.MessageCode.TraitBreedPathResponse, self.serverAddr)
            if validateExpectedMessage(CommLayer.MessageCode.TraitBreedPathResponse, tid, response, true) then
                ---@type TraitBreedPathResponsePayload
                local path = UnwrapNull(response).payload
                if #path == 0 then
                    -- An empty breed path is an error.
                    return nil
                end
                responsePayload = path
            end
        end
    end

    return responsePayload
end

---@param species string
---@return boolean | nil
function RobotComms:GetTraitInfoFromServer(species)
    local payload = {species=species}

    local responsePayload = nil
    while responsePayload == nil do
        local tid = self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.TraitInfoRequest, nil, payload)
        if tid ~= nil then
            local response, _ = self.comm:GetIncoming(5.0, CommLayer.MessageCode.TraitInfoResponse, self.serverAddr)
            if validateExpectedMessage(CommLayer.MessageCode.TraitInfoResponse, tid, response, true) then
                responsePayload = UnwrapNull(response).payload.dominant
            end
        end
    end

    return responsePayload
end

---@param errorMessage string
function RobotComms:ReportErrorToServer(errorMessage)
    local payload = {errorMessage=errorMessage}
    self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.PrintErrorRequest, nil, payload)
end

-- Waits for the user at the server to acknowledge that conditions associated with the given mutation have been met, if any.
---@param breedPathNode BreedPathNode
function RobotComms:WaitForConditionsAcknowledged(breedPathNode)
    local payload = {pathNode=breedPathNode}

    while true do
        local tid = self.comm:SendMessage(self.serverAddr, CommLayer.MessageCode.PromptConditionsRequest, nil, payload)
        if tid ~= nil then
            local response, _ = self.comm:GetIncoming(nil, CommLayer.MessageCode.PromptConditionsResponse, self.serverAddr)
            if validateExpectedMessage(CommLayer.MessageCode.PromptConditionsResponse, tid, response, false) then
                return
            end
        end
    end
end

---@return boolean
function RobotComms:PollForCancel()
    local response, _ self.comm:GetIncoming(0, CommLayer.MessageCode.CancelCommand, self.serverAddr)
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
---@param componentLib Component
---@param eventLib Event
---@param serializationLib Serialization
---@param serverAddr string
---@param port integer
---@return RobotComms | nil
function RobotComms:Create(componentLib, eventLib, serializationLib, serverAddr, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    local comm = CommLayer:Open(componentLib, eventLib, serializationLib, port)
    if comm == nil then
        Print("Failed to open CommLayer during RobotComms initialization.")
        return nil
    end
    obj.comm = comm

    obj.serverAddr = serverAddr

    return obj
end

return RobotComms
