Coroutine = require("coroutine")
Luaunit = require("Test.luaunit")

ApicultureTiles = require("Test.SimulatorModules.Component.ApicultureTiles")
Component = require("Test.SimulatorModules.Component.Component")
Event = require("Test.SimulatorModules.Event")
Modem = require("Test.SimulatorModules.Component.Modem")
Res = require("Test.Resources.TestData")
Serialization = require("Test.SimulatorModules.Serialization")
Term = require("Test.SimulatorModules.Term")
Util = require("Test.Utilities")

BeeServer = require("BeeServer.BeeServer")
CommLayer = require("Shared.CommLayer")


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
        for i = 1,10 do
            RunThreadAndVerifyResponse(serverThread, "event_pull")
            RunThreadAndVerifyResponse(serverThread, "term_pull")
        end
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLaunchWithLogAndShutdown()
        local logFilepath = Util.CreateLogfileSeed("BasicLog.log", nil)
        Component.tile_for_apiculture_0_name.__Initialize(Res.BeeGraphMundaneIntoCommon)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Verify that the server read the log correctly.
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"Forest", "Meadows", "Tropical"})
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

    function TestBeeServerStandalone:TestPath()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog.log", nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        Term.__write(serverThread, "breed Cultivated")

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        Util.AssertPathIsValidInGraph(server.beeGraph, server.breedPath, "Cultivated")
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {code=CommLayer.MessageCode.PathRequest})
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local response = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.PathResponse)
        Luaunit.assertNotIsNil(response)
        Util.AssertPathIsValidInGraph(server.beeGraph, response, "Cultivated")

        Modem.close(CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestBreedInfo()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog.log", nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {code=CommLayer.MessageCode.BreedInfoRequest, payload={parent1="Diligent", parent2="Unweary", target="Industrious"}})  -- Pick a simple species that's easy to verify.
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

        local logFilepath = Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        local industriousNode = {loc={x=6, y=9}, timestamp=345678}
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {
            code=CommLayer.MessageCode.SpeciesFoundRequest, payload={species="Industrious", node=industriousNode}
        })
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        VerifyNoModemResponse()

        local expectedFoundSpecies = {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Industrious"]=industriousNode
        }
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"Forest", "Meadows", "Tropical", "Industrious"})
        Luaunit.assertEquals(server.foundSpecies, expectedFoundSpecies)
        Luaunit.assertEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), expectedFoundSpecies)
        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)

        Modem.close(CommLayer.DefaultComPort)
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestSpeciesFoundTimestamps()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        -- Send new event and verify that it gets logged.
        RunThreadAndVerifyResponse(serverThread, "event_pull")
        local industriousNodeMiddleTimestamp = {loc={x=6, y=9}, timestamp=222222}
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {
            code=CommLayer.MessageCode.SpeciesFoundRequest, payload={species="Industrious", node=industriousNodeMiddleTimestamp}
        })
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        VerifyNoModemResponse()

        local expectedFoundSpecies = {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Industrious"]=industriousNodeMiddleTimestamp
        }
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"Forest", "Meadows", "Tropical", "Industrious"})
        Luaunit.assertEquals(server.foundSpecies, expectedFoundSpecies)
        Luaunit.assertEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), expectedFoundSpecies)
        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)

        -- Send version with an earlier timestamp and assert that it doesn't get logged.
        RunThreadAndVerifyResponse(serverThread, "event_pull")
        local industriousNodeLowTimestamp = {loc={x=2, y=7}, timestamp=111111}
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {
            code=CommLayer.MessageCode.SpeciesFoundRequest, payload={species="Industrious", node=industriousNodeLowTimestamp}
        })
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        VerifyNoModemResponse()

        expectedFoundSpecies = {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Industrious"]=industriousNodeMiddleTimestamp
        }
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"Forest", "Meadows", "Tropical", "Industrious"})
        Luaunit.assertEquals(server.foundSpecies, expectedFoundSpecies)
        Luaunit.assertEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), expectedFoundSpecies)
        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)

        -- Send version with a later timestamp and assert that it does get logged.
        RunThreadAndVerifyResponse(serverThread, "event_pull")
        local industriousNodeHighTimestamp = {loc={x=3, y=1}, timestamp=333333}
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {
            code=CommLayer.MessageCode.SpeciesFoundRequest, payload={species="Industrious", node=industriousNodeHighTimestamp}
        })
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        VerifyNoModemResponse()

        expectedFoundSpecies = {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Industrious"]=industriousNodeHighTimestamp
        }
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"Forest", "Meadows", "Tropical", "Industrious"})
        Luaunit.assertEquals(server.foundSpecies, expectedFoundSpecies)
        Luaunit.assertEquals(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH), expectedFoundSpecies)
        Util.VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)

        Modem.close(CommLayer.DefaultComPort)
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLogStream()
        local thisThread = Coroutine.running()
        Event.__registerThread(thisThread)
        ApicultureTiles.__Initialize(Res.BeeGraphActual.RawMutationInfo)

        local logFilepath = Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        local success = Modem.open(CommLayer.DefaultComPort)
        Luaunit.assertIsTrue(success)

        RunThreadAndVerifyResponse(serverThread, "event_pull")
        Modem.__sendNoYield(serverThread, CommLayer.DefaultComPort, {code=CommLayer.MessageCode.LogStreamRequest})
        local expectedResults = {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        }
        local results = {}
        for i = 1,3 do
            RunThreadAndVerifyResponse(serverThread, "modem_send")
            local payload = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.LogStreamResponse)
            Luaunit.assertNotIsNil(payload)
            Luaunit.assertNotIsNil(payload.species)
            Luaunit.assertNotIsNil(payload.node)
            results[payload.species] = payload.node
        end
        RunThreadAndVerifyResponse(serverThread, "modem_send")
        local payload = VerifyModemResponse(thisThread, serverThread, CommLayer.DefaultComPort, CommLayer.MessageCode.LogStreamResponse)
        Luaunit.assertEquals(payload, {})
        Luaunit.assertEquals(results, expectedResults)

        Modem.close(CommLayer.DefaultComPort)
        RunThreadAndVerifyResponse(serverThread, "term_pull")
        StopServerAndVerifyShutdown(serverThread)
    end
