-- This program handles importing breeding data from the adapter on the BeeHouse
-- and translating it into a more usable form for querying the breeding graph.
-- TODO: Consider using numeric IDs instead of string names for indexing to reduce memory usage.

---@param graph SpeciesGraph
---@param species string
local function createNodeInGraph(graph, species)
    graph[species] = {
        speciesName = species,
        parentMutations = {},
        childMutations = {},
    }
end

local M = {}

---@param graph SpeciesGraph
---@param result string
---@param allele1 string
---@param allele2 string
---@param chance number
---@param specialConditions string[] | nil
function M.AddMutationToGraph(graph, allele1, allele2, result, chance, specialConditions)
    -- Do setup for graph nodes if they don't already exist.
    if graph[allele1] == nil then
        createNodeInGraph(graph, allele1)
    end
    if graph[allele2] == nil then
        createNodeInGraph(graph, allele2)
    end
    if graph[result] == nil then
        createNodeInGraph(graph, result)
    end

    -- Do setup for mutations of allele nodes if they don't already exist.
    if graph[allele1].childMutations[result] == nil then
        graph[allele1].childMutations[result] = {}
    end
    if graph[allele2].childMutations[result] == nil then
        graph[allele2].childMutations[result] = {}
    end

    -- Actually add the mutation to the graph.
    -- TODO: `chance` and `specialConditions` don't really need to be stored here since they can be looked up separately to save memory.
    table.insert(graph[result].parentMutations, {parents = {allele1, allele2}, chance = chance, specialConditions = specialConditions})
    table.insert(graph[allele1].childMutations[result], {parent = allele2, chance = chance, specialConditions = specialConditions})
    table.insert(graph[allele2].childMutations[result], {parent = allele1, chance = chance, specialConditions = specialConditions})
end

---@return SpeciesGraph
function M.ImportBeeGraph(beehouseComponent)
    ---@type SpeciesGraph
    local graph = {}

    for _, species in ipairs(beehouseComponent.listAllSpecies()) do
        for _, mutation in ipairs(beehouseComponent.getBeeParents(species.uid)) do
            -- OpenComputers/Forestry specify the chance in percentage, so divide by 100 to get the decimal probability.
            M.AddMutationToGraph(graph, mutation.allele1.uid, mutation.allele2.uid, species.uid, mutation.chance / 100.0, mutation.specialConditions)
        end
    end

    return graph
end

return M
