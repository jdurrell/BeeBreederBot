Coroutine = require("coroutine")
Luaunit = require("Test.luaunit")

Component = require("Test.SimulatorModules.Component.Component")
Event = require("Test.SimulatorModules.Event")
Res = require("Test.Resources.TestData")
Serialization = require("Test.SimulatorModules.Serialization")
Term = require("Test.SimulatorModules.Term")

BeeServer = require("BeeServer.BeeServer")
CommLayer = require("Shared.CommLayer")


SEED_LOG_DIR = "./Test/Resources/LogfileSeeds/"
OPERATIONAL_LOG_DIR = "./Test/out_data/"
DEFAULT_LOG_NAME = OPERATIONAL_LOG_DIR .. "BeeBreederBot.log"

---@param seedPath string | nil
---@param operationalPath string | nil
---@return string
function CreateServerLogfile(seedPath, operationalPath)
    local errMsg = nil

    -- Overwrite whatever file might have existed from a previous test.
    local newFilepath = (operationalPath ~= nil) and (OPERATIONAL_LOG_DIR .. DEFAULT_LOG_NAME) or DEFAULT_LOG_NAME
    local newFile, err = io.open(newFilepath, "w")
    if newFile == nil then
        errMsg = err
        goto cleanup
    end
    newFile = UnwrapNull(newFile)

    -- Lua's standard library doesn't have a way to copy a file,
    -- so we have to copy the seed to the target on our own.
    if seedPath ~= nil then
        local seedFilepath = SEED_LOG_DIR .. seedPath
        local seedFile, err2 = io.open(seedFilepath, "r")
        if seedFile == nil then
            errMsg = err2
            goto cleanup
        end
        seedFile = UnwrapNull(io.open(seedFilepath, "r"))
        for line in seedFile:lines("l") do
            newFile:write(line .. "\n")
        end
        seedFile:close()
    end

    ::cleanup::
    if newFile ~= nil then
        newFile:flush()
        newFile:close()
    end

    if errMsg ~= nil then
        Luaunit.fail(errMsg)
    end

    return newFilepath
end

---@param thread thread
---@return ... -- Returns the response from the thread.
function RunThreadAndVerifyRan(thread)
    local responses = table.pack(Coroutine.resume(thread))
    Luaunit.assertTrue(responses[1])
    Luaunit.assertEquals(Coroutine.status(thread), "suspended")
    return table.unpack(responses, 2)
end

---@param thread thread
---@param expectedResponse string
function RunThreadAndVerifyResponse(thread, expectedResponse)
    local actualResponse = RunThreadAndVerifyRan(thread)
    Luaunit.assertEquals(actualResponse, expectedResponse)
end

---@param logfile string
---@param port integer
function CreateServerInstance(logfile, port)
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
function VerifyModemStateAfterServerStart(port, thread)
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
function VerifyModemStateAfterServerShutdown()
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
function StartServerAndVerifyStartup(logfile, port)
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
function StopServerAndVerifyShutdown(serverThread)
    -- Now command the server to shut down and verify that it did so correctly.
    Term.__write(serverThread, "shutdown")
    local ran, response, exitCode = Coroutine.resume(serverThread)
    Luaunit.assertIsTrue(ran)
    Luaunit.assertEquals(response, "exit")
    Luaunit.assertEquals(exitCode, 0)
    VerifyModemStateAfterServerShutdown()
end

TestBeeServerStandalone = {}
    function TestBeeServerStandalone:Setup()
        Event.__Initialize()
        Component.modem.__Initialize()
        Component.tile_for_apiculture_0_name.__Initialize({})  -- Each test is responsible for setting this up themselves.
    end

    function TestBeeServerStandalone:TestLaunchAndShutdown()
        local logFilepath = CreateServerLogfile(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLaunchIdleShutdown()
        local logFilepath = CreateServerLogfile(nil, nil)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Let the server idle for a while, then shut it down.
        for i=1, 10 do
            RunThreadAndVerifyResponse(serverThread, "event_pull")
            RunThreadAndVerifyResponse(serverThread, "term_pull")
        end
        StopServerAndVerifyShutdown(serverThread)
    end

    function TestBeeServerStandalone:TestLaunchWithLogAndShutdown()
        local logFilepath = CreateServerLogfile("BasicLog.log", nil)
        Component.tile_for_apiculture_0_name.__Initialize(Res.BeeGraphMundaneIntoCommon)
        local serverThread, server = StartServerAndVerifyStartup(logFilepath, CommLayer.DefaultComPort)

        -- Verify that the server read the log correctly.
        Luaunit.assertItemsEquals(server.leafSpeciesList, {"Forest", "Meadows", "Tropical"})
        StopServerAndVerifyShutdown(serverThread)
    end
