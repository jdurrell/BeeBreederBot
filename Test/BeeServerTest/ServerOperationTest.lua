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
---@param transactionIdExpected integer?
---@return integer, any -- The payload of the message. Verifying this is caller-specific.
local function verifyModemResponse(receiverExpected, senderExpected, portExpected, codeExpected, transactionIdExpected)
    local event, receiverActual, senderActual, portActual, _, code, transactionIdActual, payload = Event.__pullNoYield("modem_message")
    Luaunit.assertNotIsNil(event)
    Luaunit.assertEquals(receiverActual, receiverExpected)
    Luaunit.assertEquals(senderActual, senderExpected)
    Luaunit.assertEquals(portActual, portExpected)
    Luaunit.assertEquals(code, codeExpected)
    if transactionIdExpected ~= nil then
        Luaunit.assertEquals(transactionIdActual, transactionIdExpected)
    end

    return transactionIdActual, payload
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

-- Verifies that the state of the modem is correct directly after server start.
---@param port integer
---@param thread thread
local function verifyModemStateAfterServerStart(port, thread)
    -- After starting the server normally, the server should have opened a port.
    Luaunit.assertNotIsNil(Component.modem.__openPorts[port])
    Luaunit.assertTableContains(Component.modem.__openPorts[port], thread)
end

---@param port integer
---@param command string
---@param args string[]
---@param values table<string, string>
---@return BeeServer, thread
local function makeServerCommand(port, command, args, values)
    local parentThread = Coroutine.running()
    local config = {port=port, botAddr=parentThread}
    local server

    local serverThread = Coroutine.create(function ()
        -- Server must be initialized inside the other coroutine so that the modem registration ties to its thread.
        server = BeeServer:Create(Component, Event, Serialization, Term, Thread, config)
        Luaunit.assertNotIsNil(server)
        verifyModemStateAfterServerStart(port, Coroutine.running())
        Coroutine.yield("server startup")

        -- Theoretically, this should yield on its own at some point.
        server:RunServer(command, args, values)
    end)

    local ran, response = Coroutine.resume(serverThread)
    Luaunit.assertIsTrue(ran)
    Luaunit.assertEquals(response, "server startup")

    return server, serverThread
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

---@param server BeeServer
---@param serverThread thread
---@param commandTid integer
local function stopServerAndVerifyShutdown(server, serverThread, commandTid)
    -- Finish the server's active transaction.
    local thisThread = Coroutine.running()
    Modem.__sendNoYield(serverThread, server.comm.port, CommLayer.MessageCode.CommandFinishRequest, commandTid, nil)
    runThreadAndVerifyResponse(serverThread, "modem_send")
    verifyModemResponse(thisThread, serverThread, server.comm.port, CommLayer.MessageCode.CommandFinishResponse)

    -- Verify that the server shuts down.
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

    function TestBeeServerStandalone:TestCommandFinishImmediately()
        local thisThread = Coroutine.running()

        local server, serverThread = makeServerCommand(CommLayer.DefaultComPort, "template", {}, {species = "forestry.speciesForest"})
        runThreadAndVerifyResponse(serverThread, "modem_send")
        local tid, _ = verifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.MakeTemplateCommand)
        runThreadAndVerifyResponse(serverThread, "event_pull")

        stopServerAndVerifyShutdown(server, serverThread, tid)
        Modem.close(CommLayer.DefaultComPort)
    end

    function TestBeeServerStandalone:TestPingDuringCommand()
        local thisThread = Coroutine.running()

        local server, serverThread = makeServerCommand(CommLayer.DefaultComPort, "template", {}, {species = "forestry.speciesForest"})
        runThreadAndVerifyResponse(serverThread, "modem_send")
        local tid, _ = verifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.MakeTemplateCommand)
        runThreadAndVerifyResponse(serverThread, "event_pull")

        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingRequest, 456789, {})
        runThreadAndVerifyResponse(serverThread, "modem_send")
        verifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingResponse, 456789)
        runThreadAndVerifyResponse(serverThread, "event_pull")

        stopServerAndVerifyShutdown(server, serverThread, tid)
        Modem.close(CommLayer.DefaultComPort)
    end

    function TestBeeServerStandalone:TestBreedInfo()
        -- TODO: Do we need to add species to this?
        local thisThread = Coroutine.running()
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local server, serverThread = makeServerCommand(CommLayer.DefaultComPort, "template", {}, {species = "forestry.speciesForest"})
        runThreadAndVerifyResponse(serverThread, "modem_send")
        local tid, _ = verifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.MakeTemplateCommand)
        runThreadAndVerifyResponse(serverThread, "event_pull")

        -- Pick a simple species that's easy to verify.
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoRequest, 456789, {
            parent1="forestry.speciesDiligent", parent2="forestry.speciesUnweary", target="forestry.speciesIndustrious"
        })
        runThreadAndVerifyResponse(serverThread, "modem_send")
        local _, response = verifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoResponse, 456789)
        Luaunit.assertEquals(response, {targetMutChance = 0.08, nonTargetMutChance = 0})
        runThreadAndVerifyResponse(serverThread, "event_pull")

        stopServerAndVerifyShutdown(server, serverThread, tid)
        Modem.close(CommLayer.DefaultComPort)
    end
