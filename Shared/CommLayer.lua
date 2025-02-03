-- This file contains code that dscribes the communication between the client (BeeBot) and the server (BeeServer).

---@class CommLayer
---@field modem any
---@field serial any
---@field port integer
local CommLayer = {}

---@enum MessageCode
CommLayer.MessageCode = {
    PingRequest = 0,
    PingResponse = 1,
    PathRequest = 2,
    PathResponse = 3,
    CancelRequest = 4,
    -- CancelResponse = 5,        -- Do we really need to send an ACK for this?
    SpeciesFoundRequest = 6,
    -- SpeciesFoundResponse = 7,  -- Do we really need to send an ACK for this?
    BreedInfoRequest = 8,
    BreedInfoResponse = 9,
    LogStreamRequest = 10,
    LogStreamResponse = 11
}

CommLayer.DefaultComPort = 34000
CommLayer.ModemEventName = "modem_message"

---@param modemLib any
---@param serializationLib any
---@param port integer
---@return CommLayer
function CommLayer:Open(modemLib, serializationLib, port)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    -- Store away system libraries.
    -- These will need to be injected for testing.
    obj.modem = modemLib
    obj.serial = serializationLib

    -- Open port.
    local opened = Modem.open(port)
    if not opened then
        Print("Error: Failed to open communication port.")
        Shutdown()
    end
    obj.port = port

    return obj
end

---@param addr string | nil
---@param messageCode MessageCode
---@param payload table | nil
function CommLayer:SendMessage(addr, messageCode, payload)
    local message = {code=messageCode, payload=payload}

    local sent
    if addr == nil then
        sent = self.modem.broadcast(self.port, self.serial.serialize(message))
    else
        sent = self.modem.send(addr, self.port, self.serial.serialize(message))
    end

    if not sent then
        -- Report this exception in case it happens, but don't handle it because I'm still not sure what it truly indicates or how to handle it.
        Print("Error: Failed to send message code " .. tostring(messageCode) .. ".")
    end
end

---@param message string
---@return Message
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
