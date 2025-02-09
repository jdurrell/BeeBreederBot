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
function M.AddMutationToGraph(graph, allele1, allele2, result, chance)
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
    table.insert(graph[result].parentMutations, {parents={allele1, allele2}, chance=chance})
    table.insert(graph[allele1].childMutations[result], {parent=allele2, chance=chance})
    table.insert(graph[allele2].childMutations[result], {parent=allele1, chance=chance})
end

---@return SpeciesGraph
function M.ImportBeeGraph(beehouseComponent)
    ---@type SpeciesGraph
    local graph = {}

    ---@type {allele1: string, allele2: string, result: string, chance: number, specialConditions: string[]}[]
    local breedingData = beehouseComponent.getBeeBreedingData()
    for i, mutation in ipairs(breedingData) do
        -- OpenComputers/Forestry specify the chance in percentage, so divide by 100 to get the decimal probability.
        M.AddMutationToGraph(graph, mutation.allele1, mutation.allele2, mutation.result, mutation.chance / 100.0)
    end

    return graph
end

return M