-- This module contains various utilities that are re-used by multiple test suites.

local M = {}

M.SEED_LOG_DIR = "./Test/Resources/LogfileSeeds/"
M.OPERATIONAL_LOG_DIR = "./Test/out_data/"
M.DEFAULT_LOG_PATH = M.OPERATIONAL_LOG_DIR .. "BeeBreederBot.log"

---@param seedPath string | nil
---@param operationalPath string | nil
---@return string
function M.CreateLogfileSeed(seedPath, operationalPath)
    local errMsg = nil

    -- Overwrite whatever file might have existed from a previous test.
    local newFilepath = ((operationalPath ~= nil) and operationalPath) or M.DEFAULT_LOG_PATH
    local newFile, err = io.open(newFilepath, "w")
    if newFile == nil then
        errMsg = err
        goto cleanup
    end
    newFile = UnwrapNull(newFile)

    -- Lua's standard library doesn't have a way to copy a file,
    -- so we have to copy the seed to the target on our own.
    if seedPath ~= nil then
        local seedFilepath = M.SEED_LOG_DIR .. seedPath
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

---@param graph SpeciesGraph
---@param path BreedPathNode[] | nil
---@param target string
function M.AssertPathIsValidInGraph(graph, path, target)
    local speciesInPath = {}

    Luaunit.assertNotIsNil(path)
    path = UnwrapNull(path)

    for _, pathNode in ipairs(path) do
        local graphNode = graph[pathNode.target]
        Luaunit.assertNotIsNil(graphNode)

        if pathNode.parent1 == nil then
            -- It doesn't make sense to have a single parent.
            Luaunit.assertIsNil(pathNode.parent2)

            -- If there are no parents, then assert that this is a leaf node.
            Luaunit.assertIsTrue(#graphNode.parentMutations == 0)
        else
            -- TODO: Is there any case of a species mutation that can arise from breeding with itself?
            Luaunit.assertIsTrue(pathNode.parent1 ~= pathNode.parent2)
            Luaunit.assertNotIsNil(pathNode.parent2)

            -- Assert that the parents listed in the node are also in the graph.
            local parentMutation = nil
            for _, mut in ipairs(graphNode.parentMutations) do
                if ArrayContains(mut.parents, pathNode.parent1) and ArrayContains(mut.parents, pathNode.parent2) then
                    parentMutation = mut
                    break;
                end
            end
            Luaunit.assertNotIsNil(parentMutation)

            -- Assert that both of the parents appeared before this in the path.
            Luaunit.assertIsTrue(ArrayContains(speciesInPath, pathNode.parent1))
            Luaunit.assertIsTrue(ArrayContains(speciesInPath, pathNode.parent2))
        end

        table.insert(speciesInPath, pathNode.target)
    end

    -- Assert that the path actually ends at the target.
    Luaunit.assertIsTrue(speciesInPath[#speciesInPath] == target)
    Luaunit.assertIsTrue(speciesInPath[#speciesInPath] == path[#path].target)
end

---@param actualTable any
---@param expectedFormat any
function M.AssertTableHasKeys(actualTable, expectedFormat)
    Luaunit.assertNotIsNil(actualTable)
    Luaunit.assertNotIsNil(expectedFormat)

    -- Assert that all keys in the expected format are present in the actual table.
    for k, v in pairs(expectedFormat) do
        Luaunit.assertNotIsNil(actualTable[k])
        if type(v) == "table" then
            M.AssertTableKeys(actualTable[k], v)
        end
    end
end

---@param filepath string
function M.VerifyLogIsValidLog(filepath)
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

return M
