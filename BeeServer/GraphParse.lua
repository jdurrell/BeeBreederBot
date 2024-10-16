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

---@param graph SpeciesGraph
---@param result string
---@param allele1 string
---@param allele2 string
local function addMutationToGraph(graph, allele1, allele2, result)
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
    table.insert(graph[result].parentMutations, {allele1, allele2})
    table.insert(graph[allele1].childMutations[result], allele2)
    table.insert(graph[allele2].childMutations[result], allele1)
end

---@return SpeciesGraph
function ImportBeeGraph(beehouseComponent)
    ---@type SpeciesGraph
    local graph = {}

    ---@type {allele1: string, allele2: string, result: string, chance: number, specialConditions: string[]}[]
    local breedingData = beehouseComponent.getBeeBreedingData()
    for i, mutation in pairs(breedingData) do
        addMutationToGraph(graph, mutation.allele1, mutation.allele2, mutation.result)
    end

    return graph
end