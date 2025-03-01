-- This module contains various utilities that are re-used by multiple test suites.

local MutationMath = require("BeeServer.MutationMath")

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
        for field in string.gmatch(line, "[^,]+") do  -- TODO: Handle species with spaces in their name.
            local stringfield = string.gsub(field, ",", "")
            table.insert(fields, stringfield)
        end

        -- We should get 4 fields from each line.
        Luaunit.assertEquals(#fields, 4, lineString)

        -- Coordinates should be integers (shouldn't contain non-numeric characters).
        Luaunit.assertIsNil(fields[2]:find("[^%d]"), lineString)
        Luaunit.assertIsNil(fields[3]:find("[^%d]"), lineString)
        Luaunit.assertNotIsNil(fields[2]:find("[%d]"), lineString)
        Luaunit.assertNotIsNil(fields[3]:find("[%d]"), lineString)

        -- Assuming we have read the log in at some point and didn't write a 0 timestamp directly,
        -- then any 0 timestamp should have been converted.
        Luaunit.assertNotEquals(speciesInLog[fields[4]], 0, lineString)

        -- We should only see each species once.
        Luaunit.assertIsNil(speciesInLog[fields[1]], lineString)
        speciesInLog[fields[1]] = true
    end
    logfile:close()
end

-- Returns a breeding information cache element preloaded with all possible combinations for the given target.
---@param target string
---@param graph SpeciesGraph
---@return BreedInfoCacheElement
function M.BreedCacheTargetLoad(target, graph)
    local cache = {}

    for spec, _ in pairs(graph) do
        cache[spec] = (cache[spec] == nil and {}) or cache[spec]
        for spec2, _ in pairs(graph) do
            cache[spec2] = (cache[spec2] == nil and {}) or cache[spec2]

            if cache[spec][spec2] == nil then
                Luaunit.assertIsNil(cache[spec2][spec], "Test-internal error.")

                local targetMutChance, nonTargetMutChance = MutationMath.CalculateBreedInfo(spec, spec2, target, graph)
                cache[spec][spec2] = {targetMutChance = targetMutChance, nonTargetMutChance = nonTargetMutChance}
                cache[spec2][spec] = {targetMutChance = targetMutChance, nonTargetMutChance = nonTargetMutChance}
            end
        end
    end

    return cache
end

---@param graph SpeciesGraph
function M.BreedCachePreloadAll(graph)
    local cache = {}

    for target, _ in pairs(graph) do
        cache[target] = M.BreedCacheTargetLoad(target, graph)
    end

    return cache
end

-- TODO: Add more fields when we end up needing them.
---@param species1 string
---@param species2 string
---@param fertility integer | nil
function M.CreateGenome(species1, species2, fertility)
    local fertilityToUse = ((fertility == nil) and 1) or fertility

    return {
        species = {primary = {uid = species1}, secondary = {uid = species2}},
        fertility = {primary = fertilityToUse, secondary = fertilityToUse}
    }
end

---@param genome ForestryGenome
---@param traitInfo TraitInfo | nil
---@return AnalyzedBeeIndividual
function M.CreateBee(genome, traitInfo)
    -- Convert primary/secondary genome representation to active/inactive traits based on dominant and recessive behavior.
    local active = {}
    local inactive = {}
    for gene, alleles in pairs(genome) do
        -- For species, traitInfo is indexed by the species name instead of the entire trait table.
        -- TODO: Figure out how to deal with this in a less hacky way.
        local lookupPrimary = ((gene == "species") and alleles.primary.name) or alleles.primary
        local lookupSecondary = ((gene == "species") and alleles.secondary.name) or alleles.secondary

        if (traitInfo ~= nil) and (traitInfo[gene] ~= nil) and (not traitInfo[gene][lookupPrimary]) and traitInfo[gene][lookupSecondary] then
            -- If the primary allele is recessive, and the secondary is dominant, the the secondary shows up as active, and the primary shows up as inactive.
            active[gene] = alleles.secondary
            inactive[gene] = alleles.primary
        else
            -- In all other cases, Forestry prioritizes the primary allele.
            active[gene] = alleles.primary
            inactive[gene] = alleles.secondary
        end
    end

    return {
        active = active,
        inactive = inactive,
        __genome = genome
    }
end

---@return boolean
function M.IsVerboseMode()
    for _, argument in ipairs(arg) do
        if (argument == "-v") or (argument == "--verbose") then
            return true
        end
    end

    return false
end

---@param str string
function M.VerbosePrint(str)
    if M.IsVerboseMode() then
        print(str)
    end
end

return M
