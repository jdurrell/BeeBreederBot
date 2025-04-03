-- This file contains code that dscribes the communication between the client (BeekeeperBot) and the server (BeeServer).

---@class CommLayer
---@field event Event
---@field modem Modem
---@field serial Serialization
---@field port integer
local CommLayer = {}

---@enum MessageCode
CommLayer.MessageCode = {
    PingRequest = 0,
    PingResponse = 1,
    CancelCommand = 4,
    -- CancelResponse = 5,        -- Do we really need to send an ACK for this?
    SpeciesFoundRequest = 6,
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
    TraitBreedPathResponse = 22
}

CommLayer.DefaultComPort = 34000
CommLayer.ModemEventName = "modem_message"

---@param eventLib Event | nil
---@param modemLib Modem | nil
---@param serializationLib Serialization | nil
---@param port integer
---@return CommLayer | nil
function CommLayer:Open(eventLib, modemLib, serializationLib, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- Store away system libraries.
    -- These will need to be injected for testing.
    if eventLib == nil then
        Print("Error: Failed to find event library when opening CommLayer.")
        obj:Close()
        return nil
    end
    obj.event = eventLib

    if modemLib == nil then
        Print("Error: Failed to find modem library when opening CommLayer.")
        obj:Close()
        return nil
    end
    obj.modem = modemLib

    if serializationLib == nil then
        Print("Error: Failed to find serialization library when opening CommLayer.")
        obj:Close()
        return nil
    end
    obj.serial = serializationLib

    -- Open port.
    local opened = modemLib.open(port)
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
---@return Message | nil, string | nil
function CommLayer:GetIncoming(timeout, messageCode)
    local event, _, addr, _, _, code, payload = self.event.pull(timeout, CommLayer.ModemEventName, nil, nil, nil, nil, messageCode)
    if event == nil then
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
