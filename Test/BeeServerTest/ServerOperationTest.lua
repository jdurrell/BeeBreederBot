local Coroutine = require("coroutine")
local Luaunit = require("Test.luaunit")

local ApicultureTiles = require("Test.SimulatorModules.Component.ApicultureTiles")
local Component = require("Test.SimulatorModules.Component.Component")
local Event = require("Test.SimulatorModules.Event")
local Modem = require("Test.SimulatorModules.Component.Modem")
local Res = require("Test.Resources.TestData")
local Serialization = require("Test.SimulatorModules.Serialization")
local Term = require("Test.SimulatorModules.Term")
local Thread = require("Test.SimulatorModules.Thread")
local Util = require("Test.Utilities.CommonUtilities")

local BeeServer = require("BeeServer.BeeServer")
local CommLayer = require("Shared.CommLayer")


---@param receiverExpected thread
---@param senderExpected thread
---@param portExpected integer
---@param codeExpected MessageCode
---@return any -- The payload of the message. Verifying this is caller-specific.
local function verifyModemResponse(receiverExpected, senderExpected, portExpected, codeExpected)
    local event, receiverActual, senderActual, portActual, _, code, payload = Event.__pullNoYield("modem_message")
    Luaunit.assertNotIsNil(event)
    Luaunit.assertEquals(receiverActual, receiverExpected)
    Luaunit.assertEquals(senderActual, senderExpected)
    Luaunit.assertEquals(portActual, portExpected)
    Luaunit.assertEquals(code, codeExpected)

    return payload
end

local function verifyNoModemResponse()
    local event = Event.__pullNoYield("modem_message")
    Luaunit.assertIsNil(event)
end

 ---@param thread thread
---@return ... Returns the response from the thread.
local function runThreadAndVerifyRan(thread)
    local responses = table.pack(Coroutine.resume(thread))
    Luaunit.assertTrue(responses[1])
    Luaunit.assertEquals(Coroutine.status(thread), "suspended")
    return table.unpack(responses, 2)
end

---@param thread thread
---@param expectedResponse string
local function runThreadAndVerifyResponse(thread, expectedResponse)
    local actualResponse = runThreadAndVerifyRan(thread)
    Luaunit.assertEquals(actualResponse, expectedResponse)
end

---@param port integer
local function createServerInstance(port)
    local server = nil  ---@type BeeServer
    local parentThread = Coroutine.running()
    local thread = Coroutine.create(function ()
        local config = {port = port, botAddr = parentThread}
        server = BeeServer:Create(Component, Event, Serialization, Term, Thread, config)
        Luaunit.assertNotIsNil(server)
        Coroutine.yield("startup success")
        server:RunServer()
    end)
    Event.__registerThread(thread)
    Term.__registerThread(thread)

    runThreadAndVerifyResponse(thread, "startup success")
    Luaunit.assertNotIsNil(server)
    runThreadAndVerifyResponse(server.messagingThreadHandle.__thread, "event_pull")

    return thread, server
end

-- Verifies that the state of the modem is correct directly after server start.
---@param port integer
---@param thread thread
local function verifyModemStateAfterServerStart(port, thread)
    -- After starting the server normally, the server should have opened a port.
    Luaunit.assertNotIsNil(Component.modem.__openPorts[port])
    Luaunit.assertTableContains(Component.modem.__openPorts[port], thread)
end

-- Verifies that the state of the modem is correct directly after server shutdown.
---@param serverThread thread
local function verifyModemStateAfterServerShutdown(serverThread)
    -- After shutting down normally, the modem should have been closed.
    -- Since the server object in the test is the only object accessing the
    -- modem in these tests, no port should have any receivers at this point.
    for _, receiverList in pairs(Component.modem.__openPorts) do
        Luaunit.assertNotTableContains(receiverList, serverThread)
    end
end

---@param port integer
---@return thread, BeeServer
local function startServerAndVerifyStartup(port)
    -- Start the server and verify that it started correctly.
    local serverThread, server = createServerInstance(port)
    Luaunit.assertNotIsNil(server)
    Luaunit.assertEquals(Coroutine.status(serverThread), "suspended")
    local response = runThreadAndVerifyRan(serverThread)
    Luaunit.assertEquals(response, "term_pull")
    verifyModemStateAfterServerStart(port, serverThread)

    return serverThread, UnwrapNull(server)
end

---@param server BeeServer
---@param serverThread thread
local function stopServerAndVerifyShutdown(server, serverThread)
    -- Now command the server to shut down and verify that it did so correctly.
    Term.__write(serverThread, "shutdown")
    if server.botAddr ~= nil then
        runThreadAndVerifyResponse(serverThread, "modem_send")
        local thisThread = Coroutine.running()
        verifyModemResponse(thisThread, serverThread, server.comm.port, CommLayer.MessageCode.CancelCommand)
    end
    local ran, response, exitCode = Coroutine.resume(serverThread)
    Luaunit.assertIsTrue(ran)
    Luaunit.assertEquals(response, "exit")
    Luaunit.assertEquals(exitCode, 0)
    verifyModemStateAfterServerShutdown(serverThread)
end

TestBeeServerStandalone = {}
    function TestBeeServerStandalone:Setup()
        Event.__Initialize()
        Component.modem.__Initialize()
        Component.tile_for_apiculture_0_name.__Initialize({})  -- Each test is responsible for setting this up themselves.

        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success, "Test setup failed.")
    end

    function TestBeeServerStandalone:TestLaunchAndShutdown()
        local serverThread, server = startServerAndVerifyStartup(CommLayer.DefaultComPort)
        stopServerAndVerifyShutdown(server, serverThread)
    end

    function TestBeeServerStandalone:TestLaunchIdleShutdown()
        local serverThread, server = startServerAndVerifyStartup(CommLayer.DefaultComPort)

        -- Let the server idle for a while, then shut it down.
        for i = 1, 10 do
            runThreadAndVerifyResponse(serverThread, "term_pull")
        end
        for i = 1, 10 do
            runThreadAndVerifyResponse(server.messagingThreadHandle.__thread, "event_pull")
        end
        for i = 1, 10 do
            runThreadAndVerifyResponse(serverThread, "term_pull")
            runThreadAndVerifyResponse(server.messagingThreadHandle.__thread, "event_pull")
        end
        stopServerAndVerifyShutdown(server, serverThread)
    end

    function TestBeeServerStandalone:TestPing()
        local thisThread = Coroutine.running()

        local serverThread, server = startServerAndVerifyStartup(CommLayer.DefaultComPort)
        local serverMessagingThread = server.messagingThreadHandle.__thread
        runThreadAndVerifyResponse(serverThread, "term_pull")

        Modem.__sendNoYield(serverMessagingThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingRequest, {transactionId = 456789})
        runThreadAndVerifyResponse(serverMessagingThread, "modem_send")
        local response = verifyModemResponse(thisThread, serverMessagingThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingResponse)
        Luaunit.assertEquals(response, {transactionId = 456789})

        runThreadAndVerifyResponse(serverThread, "term_pull")
        stopServerAndVerifyShutdown(server, serverThread)
        Modem.close(CommLayer.DefaultComPort)
    end

    function TestBeeServerStandalone:TestBreedInfo()
        -- TODO: Do we need to add species to this?
        local thisThread = Coroutine.running()
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local serverThread, server = startServerAndVerifyStartup(CommLayer.DefaultComPort)
        local serverMessagingThread = server.messagingThreadHandle.__thread

        runThreadAndVerifyResponse(serverThread, "term_pull")
        Modem.__sendNoYield(serverMessagingThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoRequest, {parent1="forestry.speciesDiligent", parent2="forestry.speciesUnweary", target="forestry.speciesIndustrious"})  -- Pick a simple species that's easy to verify.
        runThreadAndVerifyResponse(server.messagingThreadHandle.__thread, "modem_send")
        local response = verifyModemResponse(thisThread, serverMessagingThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoResponse)
        Luaunit.assertEquals(response, {targetMutChance = 0.08, nonTargetMutChance = 0})

        runThreadAndVerifyResponse(serverMessagingThread, "event_pull")
        runThreadAndVerifyResponse(serverThread, "term_pull")
        stopServerAndVerifyShutdown(server, serverThread)
        Modem.close(CommLayer.DefaultComPort)
    end
