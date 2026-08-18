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
    CancelCommand = 2,
    -- CancelResponse = 3,        -- Do we really need to send an ACK for this?
    BreedInfoRequest = 6,
    BreedInfoResponse = 7,
    TraitInfoRequest = 8,
    TraitInfoResponse = 9,
    PromptConditionsRequest = 10,
    PromptConditionsResponse = 11,
    PrintErrorRequest = 12,
    TraitBreedPathRequest = 13,
    TraitBreedPathResponse = 14,
    ImportDroneStacksCommand = 15,
    ImportPrincessesCommand = 16,
    MakeTemplateCommand = 17,
    CommandAcceptResponse = 18,
    CommandFinishRequest = 19,
    CommandFinishResponse = 20,
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
---@param transactionId integer | nil
---@param payload table | nil
---@return integer | nil
function CommLayer:SendMessage(addr, messageCode, transactionId, payload)
    if transactionId == nil then
        -- Generate a random uid.
        transactionId = math.random(2 ^ 53)
    end

    local sent
    if addr == nil then
        sent = self.modem.broadcast(self.port, messageCode, transactionId, self.serial.serialize(payload))
    else
        sent = self.modem.send(addr, self.port, messageCode, transactionId, self.serial.serialize(payload))
    end

    if not sent then
        -- Report this exception in case it happens, but don't handle it because I'm still not sure what it truly indicates or how to handle it.
        Print("Error: Failed to send message code " .. tostring(messageCode) .. ".")
        return nil
    end

    return transactionId
end

-- Checks for an incoming message. Returns nil if no message was received before the timeout.
---@param timeout number | nil
---@param messageCode number | nil
---@param expectedAddr string | nil
---@return Message | nil, string | nil
function CommLayer:GetIncoming(timeout, messageCode, expectedAddr)
    local event, _, addr, _, _, code, transactionId, payload = self.event.pull(timeout, CommLayer.ModemEventName, nil, nil, nil, nil, messageCode)
    if event == nil then
        return nil, nil
    end

    if (expectedAddr ~= nil) and (addr ~= expectedAddr) then
        Print("Got message from unrecognized source " .. addr .. ".")
        return nil, nil
    end

    return {code = code, transactionId = transactionId, payload = self:deserializeMessage(payload)}, addr
end

---@param message string
---@return table
function CommLayer:deserializeMessage(message)
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
