local Coroutine = require("coroutine")
local Luaunit = require("Test.luaunit")

local ApicultureTiles = require("Test.SimulatorModules.Component.ApicultureTiles")
local Component = require("Test.SimulatorModules.Component.Component")
local Event = require("Test.SimulatorModules.Event")
local Modem = require("Test.SimulatorModules.Component.Modem")
local Res = require("Test.Resources.TestData")
local Serialization = require("Test.SimulatorModules.Serialization")
local Term = require("Test.SimulatorModules.Term")
local Util = require("Test.Utilities.CommonUtilities")

local BeeServer = require("BeeServer.BeeServer")
local CommLayer = require("Shared.CommLayer")
local Logger = require("BeeServer.Logger")


---@param receiverExpected thread
---@param senderExpected thread
---@param portExpected integer
---@param codeExpected MessageCode
---@return any -- The payload of the message. Verifying this is caller-specific.
local function VerifyModemResponse(receiverExpected, senderExpected, portExpected, codeExpected)
    local event, receiverActual, senderActual, portActual, _, code, payload = Event.__pullNoYield("modem_message")
    Luaunit.assertNotIsNil(event)
    Luaunit.assertEquals(receiverActual, receiverExpected)
    Luaunit.assertEquals(senderActual, senderExpected)
    Luaunit.assertEquals(portActual, portExpected)
    Luaunit.assertEquals(code, codeExpected)

    return payload
end

local function VerifyNoModemResponse()
    local event = Event.__pullNoYield("modem_message")
    Luaunit.assertIsNil(event)
end

 ---@param thread thread
---@return ... Returns the response from the thread.
local function RunThreadAndVerifyRan(thread)
    local responses = table.pack(Coroutine.resume(thread))
    Luaunit.assertTrue(responses[1])
    Luaunit.assertEquals(Coroutine.status(thread), "suspended")
    return table.unpack(responses, 2)
end

---@param thread thread
---@param expectedResponse string
local function RunThreadAndVerifyResponse(thread, expectedResponse)
    local actualResponse = RunThreadAndVerifyRan(thread)
    Luaunit.assertEquals(actualResponse, expectedResponse)
end

---@param logfile string
---@param port integer
local function CreateServerInstance(logfile, port)
    local server = nil
    local thread = Coroutine.create(function ()
        server = BeeServer:Create(Component, Event, Serialization, Term, logfile, port)
        Coroutine.yield("startup success")
        server:RunServer()
    end)
    Event.__registerThread(thread)
    Term.__registerThread(thread)

    local response = RunThreadAndVerifyRan(thread)
    Luaunit.assertEquals(response, "startup success")
    return thread, server
end

-- Verifies that the state of the modem is correct directly after server start.
---@param port integer
---@param thread thread
local function VerifyModemStateAfterServerStart(port, thread)
    -- After starting the server normally, the modem should have only
    -- one port open (the port we gave it) and that port should have
    -- only one receiver (the thread we started the server on).
    local expected = {
        [port] = {
            [1] = thread
        }
    }
    Luaunit.assertEquals(Component.modem.__openPorts, expected)
end

-- Verifies that the state of the modem is correct directly after server shutdown.
---@param serverThread thread
local function VerifyModemStateAfterServerShutdown(serverThread)
    -- After shutting down normally, the modem should have been closed.
    -- Since the server object in the test is the only object accessing the
    -- modem in these tests, no port should have any receivers at this point.
    for _, receiverList in pairs(Component.modem.__openPorts) do
        Luaunit.assertNotTableContains(receiverList, serverThread)
    end
end

---@param logfile string
---@param port integer
---@return thread, BeeServer
local function StartServerAndVerifyStartup(logfile, port)
    -- Start the server and verify that it started correctly.
    local serverThread, server = CreateServerInstance(logfile, port)
    Luaunit.assertNotIsNil(server)
    Luaunit.assertEquals(Coroutine.status(serverThread), "suspended")
    local response = RunThreadAndVerifyRan(serverThread)
    Luaunit.assertEquals(response, "term_pull")
    VerifyModemStateAfterServerStart(port, serverThread)

    return serverThread, UnwrapNull(server)
end

---@param server BeeServer
---@param serverThread thread
local function StopServerAndVerifyShutdown(server, serverThread)
    -- Now command the server to shut down and verify that it did so correctly.
    Term.__write(serverThread, "shutdown")
    if server.botAddr ~= nil then
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local thisThread = Coroutine.running()
        VerifyModemResponse(thisThread, serverThread, server.comm.port, CommLayer.MessageCode.CancelCommand)
    end
    local ran, response, exitCode = Coroutine.resume(serverThread)
    Luaunit.assertIsTrue(ran)
    Luaunit.assertEquals(response, "exit")
    Luaunit.assertEquals(exitCode, 0)
    VerifyModemStateAfterServerShutdown(serverThread)
end

TestBeeServerStandalone = {}
    function TestBeeServerStandalone:Setup()
        Event.__Initialize()
        Component.modem.__Initialize()
        Component.tile_for_apiculture_0_name.__Initialize({})  -- Each test is responsible for setting this up themselves.
    end

    function TestBeeServerStandalone:TestLaunchAndShutdown()
        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        StopServerAndVerifyShutdown(server, serverThread)
    end

    function TestBeeServerStandalone:TestLaunchIdleShutdown()
        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Let the server idle for a while, then shut it down.
        for i = 1, 10 do
            RunThreadAndVerifyResponse(serverThread, "event_pull")
            RunThreadAndVerifyResponse(serverThread, "term_pull")
        end
        StopServerAndVerifyShutdown(server, serverThread)
    end

    function TestBeeServerStandalone:TestLaunchWithLogAndShutdown()
        local logFilepath = Util.CreateLogfileSeed("BasicLog_uids.log", nil)
        Component.tile_for_apiculture_0_name.__Initialize(Res.BeeGraphMundaneIntoCommon)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Verify that the server read the log correctly.
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical"})
        StopServerAndVerifyShutdown(server, serverThread)
    end

    function TestBeeServerStandalone:TestLaunchWithEmptyLogAndShutdown()
        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        Component.tile_for_apiculture_0_name.__Initialize(Res.BeeGraphMundaneIntoCommon)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Verify that the server didn't fail on an empty log.
        Luaunit.assertItemsEquals(server.leafSpeciesList, {})
        StopServerAndVerifyShutdown(server, serverThread)
    end

    function TestBeeServerStandalone:TestPing()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)

        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "event_pull")

        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingRequest, {transactionId=456789})
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingResponse)
        Luaunit.assertEquals(response, {transactionId = 456789})

        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(server, serverThread)
        Modem.close(CommLayer.DefaultComPort)
    end

    function TestBeeServerStandalone:TestBreedInfo()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog_uids.log", nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoRequest, {parent1="forestry.speciesDiligent", parent2="forestry.speciesUnweary", target="forestry.speciesIndustrious"})  -- Pick a simple species that's easy to verify.
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoResponse)
        Luaunit.assertEquals(response, {targetMutChance = 0.08, nonTargetMutChance = 0})

        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(server, serverThread)
        Modem.close(CommLayer.DefaultComPort)
    end

    function TestBeeServerStandalone:TestSpeciesFoundNewSpecies()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog_uids.log", Util.DEFAULT_LOG_PATH)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.SpeciesFoundRequest, {species = "forestry.speciesIndustrious"})
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.SpeciesFoundResponse)

        Luaunit.assertItemsEquals(server.leafSpeciesList, {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical", "forestry.speciesIndustrious"})
        Luaunit.assertItemsEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical", "forestry.speciesIndustrious"})

        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(server, serverThread)
        Modem.close(CommLayer.DefaultComPort)
    end

    function TestBeeServerStandalone:TestSpeciesFoundExistingSpecies()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog_uids.log", Util.DEFAULT_LOG_PATH)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.SpeciesFoundRequest, {species="forestry.speciesForest"})
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.SpeciesFoundResponse)

        Luaunit.assertItemsEquals(server.leafSpeciesList, {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical"})
        Luaunit.assertItemsEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical"})

        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(server, serverThread)
        Modem.close(CommLayer.DefaultComPort)
    end
