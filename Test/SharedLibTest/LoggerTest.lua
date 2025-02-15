Luaunit = require("Test.luaunit")
Util = require("Test.Utilities")

Logger = require("Shared.Logger")

---@param filepath string
local function VerifyLogIsValidLog(filepath)
    local logfile, msg = io.open(filepath, "r")
    if logfile == nil then
        Luaunit.fail(msg)
        return
    end

    local speciesInLog = {}
    local count = 0
    for line in logfile:lines("l") do
        local lineString = tostring(count) .. ": " .. line

        count = count + 1
        local fields = {}
        for field in string.gmatch(line, "[%w]+") do  -- TODO: Handle species with spaces in their name.
            local stringfield = string.gsub(field, ",", "")
            table.insert(fields, stringfield)
        end

        -- We should get 4 fields from each line.
        Luaunit.assertEquals(#fields, 4, lineString)

        -- Coordinates should be integers (shouldn't contain non-numeric characters).
        Luaunit.assertNotIsNil(fields[2]:find("^[%d]"), lineString)
        Luaunit.assertNotIsNil(fields[3]:find("^[%d]"), lineString)

        -- Assuming we have read the log in at some point and didn't write a 0 timestamp directly,
        -- then any 0 timestamp should have been converted.
        Luaunit.assertNotEquals(speciesInLog[fields[4]], 0, lineString)

        -- We should only see each species once.
        Luaunit.assertIsNil(speciesInLog[fields[1]], lineString)
        speciesInLog[fields[1]] = true
    end
    logfile:close()
end

TestLogger = {}
    function TestLogger:TestNoLog()
        os.remove(Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {})

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Forest", {x=0, y=0}, 123)
        Luaunit.assertIsTrue(success)

        result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {["Forest"]={loc={x=0, y=0}, timestamp=123}})

        VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestReadExistingLog()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestReadZeroTimestamp()
        Util.CreateLogfileSeed("LogfileWithZeroTimestamps.log", Util.DEFAULT_LOG_PATH)

        local result = UnwrapNull(Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH))
        Luaunit.assertNotIsNil(result)

        local zeroTimestampResult = result["Marshy"]
        Luaunit.assertEquals(zeroTimestampResult.loc, {x=0, y=4})
        Luaunit.assertNotEquals(zeroTimestampResult.timestamp, 0)

        result["Marshy"] = nil
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        local result2 = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result2, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Marshy"]=zeroTimestampResult
        })

        VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestOverwriteExisting()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        local newMeadows = {loc={x=1, y=5}, timestamp=999999}
        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Meadows", newMeadows.loc, newMeadows.timestamp)
        Luaunit.assertIsTrue(success)
        result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]=newMeadows,
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456}
        })

        VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end

    function TestLogger:TestNewEntry()
        Util.CreateLogfileSeed("BasicLog.log", Util.DEFAULT_LOG_PATH)
        local newEntryMarshy = {loc={x=1, y=5}, timestamp=987654}

        local success = Logger.LogSpeciesToDisk(Util.DEFAULT_LOG_PATH, "Marshy", newEntryMarshy.loc, newEntryMarshy.timestamp)
        Luaunit.assertIsTrue(success)

        local result = Logger.ReadSpeciesLogFromDisk(Util.DEFAULT_LOG_PATH)
        Luaunit.assertEquals(result, {
            ["Forest"]={loc={x=0, y=0}, timestamp=123456},
            ["Meadows"]={loc={x=0, y=1}, timestamp=123456},
            ["Tropical"]={loc={x=0, y=2}, timestamp=123456},
            ["Marshy"]=newEntryMarshy
        })

        VerifyLogIsValidLog(Util.DEFAULT_LOG_PATH)
    end
