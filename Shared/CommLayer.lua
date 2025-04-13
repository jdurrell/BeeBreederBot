-- This file contains code that dscribes the communication between the client (BeekeeperBot) and the server (BeeServer).

---@class CommLayer
---@field event Event
---@field modem Modem
---@field serial Serialization
---@field port integer
local CommLayer = {}

require("Shared.Shared")

---@enum MessageCode
CommLayer.MessageCode = {
    PingRequest = 0,
    PingResponse = 1,
    CancelCommand = 4,
    -- CancelResponse = 5,        -- Do we really need to send an ACK for this?
    SpeciesFoundRequest = 6,
    SpeciesFoundResponse = 7,  -- Basically just an ACK for SpeciesFoundRequest.
    BreedInfoRequest = 8,
    BreedInfoResponse = 9,
    LogStreamRequest = 10,
    LogStreamResponse = 11,
    LocationRequest = 12,
    LocationResponse = 13,
    TraitInfoRequest = 14,
    TraitInfoResponse = 15,
    BreedCommand = 16,
    ReplicateCommand = 17,
    PromptConditionsRequest = 18,
    PromptConditionsResponse = 19,
    PrintErrorRequest = 20,
    TraitBreedPathRequest = 21,
    TraitBreedPathResponse = 22,
    ImportDroneStacksCommand = 23,
    ImportPrincessesCommand = 24
}

CommLayer.DefaultComPort = 34000
CommLayer.ModemEventName = "modem_message"

---@param componentLib Component
---@param eventLib Event
---@param serializationLib Serialization
---@param port integer
---@return CommLayer | nil
function CommLayer:Open(componentLib, eventLib, serializationLib, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- Store away system libraries.
    -- These will need to be injected for testing.
    obj.event = eventLib
    obj.serial = serializationLib

    if not TableContains(componentLib.list(), "modem") then
        Print("Failed to find 'modem' component.")
        return nil
    end
    obj.modem = componentLib.modem

    -- Open port.
    local opened = componentLib.modem.open(port)
    if not opened then
        Print("Error: Failed to open communication port.")
        return nil
    end
    obj.port = port

    return obj
end

---@param addr string | nil
---@param messageCode MessageCode
---@param payload table | nil
function CommLayer:SendMessage(addr, messageCode, payload)
    local sent
    if addr == nil then
        sent = self.modem.broadcast(self.port, messageCode, self.serial.serialize(payload))
    else
        sent = self.modem.send(addr, self.port, messageCode, self.serial.serialize(payload))
    end

    if not sent then
        -- Report this exception in case it happens, but don't handle it because I'm still not sure what it truly indicates or how to handle it.
        Print("Error: Failed to send message code " .. tostring(messageCode) .. ".")
    end
end

-- Checks for an incoming message. Returns nil if no message was received before the timeout.
---@param timeout number | nil
---@param messageCode number | nil
---@param expectedAddr string | nil
---@return Message | nil, string | nil
function CommLayer:GetIncoming(timeout, messageCode, expectedAddr)
    local event, _, addr, _, _, code, payload = self.event.pull(timeout, CommLayer.ModemEventName, nil, nil, nil, nil, messageCode)
    if event == nil then
        return nil, nil
    end

    if (expectedAddr ~= nil) and (addr ~= expectedAddr) then
        Print("Got message from unrecognized source " .. addr .. ".")
        return nil, nil
    end

    return {code = code, payload = self:DeserializeMessage(payload)}, addr
end

---@param message string
---@return table
function CommLayer:DeserializeMessage(message)
    if message == nil then
-- Disable this because this condition is likely better checked by checking for `event` == nil.
---@diagnostic disable-next-line: return-type-mismatch
        return nil
    end

    return self.serial.unserialize(message)
end

function CommLayer:Close()
    self.modem.close(self.port)
end

return CommLayer
