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
local function VerifyModemStateAfterServerShutdown()
    -- After shutting down normally, the modem should have been closed.
    -- Since the server object in the test is the only object accessing the
    -- modem in these tests, no port should have any receivers at this point.
    for _, receiverList in pairs(Component.modem.__openPorts) do
        Luaunit.assertEquals(receiverList, {})
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

---@param serverThread thread
local function StopServerAndVerifyShutdown(serverThread)
    -- Now command the server to shut down and verify that it did so correctly.
    Term.__write(serverThread, "shutdown")
    local ran, response, exitCode = Coroutine.resume(serverThread)
    Luaunit.assertIsTrue(ran)
    Luaunit.assertEquals(response, "exit")
    Luaunit.assertEquals(exitCode, 0)
    VerifyModemStateAfterServerShutdown()
end

---@param receiverExpected thread
---@param senderExpected thread
---@param portExpected integer
---@param codeExpected MessageCode
---@return any -- The payload of the message. Verifying this is caller-specific.
local function VerifyModemResponse(receiverExpected, senderExpected, portExpected, codeExpected)
    local event, receiverActual, senderActual, portActual, _, message = Event.__pullNoYield("modem_message")
    Luaunit.assertNotIsNil(event)
    Luaunit.assertEquals(receiverActual, receiverExpected)
    Luaunit.assertEquals(senderActual, senderExpected)
    Luaunit.assertEquals(portActual, portExpected)
    Luaunit.assertNotIsNil(message)
    Luaunit.assertEquals(message.code, codeExpected)

    return message.payload
end

local function VerifyNoModemResponse()
    local event = Event.__pullNoYield("modem_message")
    Luaunit.assertIsNil(event)
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
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLaunchIdleShutdown()
        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Let the server idle for a while, then shut it down.
        for i = 1, 10 do
            RunThreadAndVerifyResponse(serverThread, "event_pull")
            RunThreadAndVerifyResponse(serverThread, "term_pull")
        end
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLaunchWithLogAndShutdown()
        local logFilepath = Util.CreateLogfileSeed("BasicLog_uids.log", nil)
        Component.tile_for_apiculture_0_name.__Initialize(Res.BeeGraphMundaneIntoCommon)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Verify that the server read the log correctly.
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical"})
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLaunchWithEmptyLogAndShutdown()
        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        Component.tile_for_apiculture_0_name.__Initialize(Res.BeeGraphMundaneIntoCommon)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Verify that the server didn't fail on an empty log.
        Luaunit.assertItemsEquals(server.leafSpeciesList, {})
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestPing()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)

        local logFilepath = Util.CreateLogfileSeed(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "event_pull")

        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {code=CommLayer.MessageCode.PingRequest, payload={transactionId=456789}})
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PingResponse)
        Luaunit.assertEquals(response, {transactionId=456789})

        Modem.close(CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(serverThread)
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
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {code=CommLayer.MessageCode.BreedInfoRequest, payload={parent1="forestry.speciesDiligent", parent2="forestry.speciesUnweary", target="forestry.speciesIndustrious"}})  -- Pick a simple species that's easy to verify.
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.BreedInfoResponse)
        Luaunit.assertEquals(response, {targetMutChance=0.08, nonTargetMutChance=0})

        Modem.close(CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(serverThread)
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
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {
            code=CommLayer.MessageCode.SpeciesFoundRequest, payload={species="forestry.speciesIndustrious"}
        })
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.LocationResponse)
        Luaunit.assertEquals(response, {loc={x=1, y=2, z=0}})

        Luaunit.assertItemsEquals(server.leafSpeciesList, {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical", "forestry.speciesIndustrious"})
        local expectedFoundSpecies = {
            ["forestry.speciesForest"]={loc={x=0, y=0, z=0}, timestamp=123456},
            ["forestry.speciesMeadows"]={loc={x=0, y=1, z=0}, timestamp=123456},
            ["forestry.speciesTropical"]={loc={x=0, y=2, z=0}, timestamp=123456},
            ["forestry.speciesIndustrious"]={loc={x=1, y=2, z=0}}
        }
        Util.AssertAllKnowableFields(server.foundSpecies, expectedFoundSpecies)
        Util.AssertAllKnowableFields(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), expectedFoundSpecies)
        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)

        Modem.close(CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(serverThread)
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
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {
            code=CommLayer.MessageCode.SpeciesFoundRequest, payload={species="forestry.speciesForest"}
        })
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.LocationResponse)
        Luaunit.assertEquals(response, {loc={x=0, y=0, z=0}})

        Luaunit.assertItemsEquals(server.leafSpeciesList, {"forestry.speciesForest", "forestry.speciesMeadows", "forestry.speciesTropical"})
        local expectedFoundSpecies = {
            ["forestry.speciesForest"]={loc={x=0, y=0, z=0}, timestamp=123456},
            ["forestry.speciesMeadows"]={loc={x=0, y=1, z=0}, timestamp=123456},
            ["forestry.speciesTropical"]={loc={x=0, y=2, z=0}, timestamp=123456},
        }
        Luaunit.assertEquals(server.foundSpecies, expectedFoundSpecies)
        Luaunit.assertEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), expectedFoundSpecies)
        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)

        Modem.close(CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(serverThread)
    end
