-- This program handles importing breeding data from the adapter on the BeeHouse
-- and translating it into a more usable form for querying the breeding graph.
-- TODO: Consider using numeric IDs instead of string names for indexing to reduce memory usage.

---@param graph SpeciesGraph
---@param species string
local function createNodeInGraph(graph, species)
    graph[species].speciesName = species
    graph[species].parentMutations = nil
    graph[species].childMutations = nil
end

---@return SpeciesGraph
function ImportBeeGraph(beehouseComponent)
    ---@type SpeciesGraph
    local graph = {}

    ---@type {allele1: string, allele2: string, result: string, chance: number, specialConditions: string[]}[]
    local breedingData = beehouseComponent.getBeeBreedingData()
    for i, mutation in pairs(breedingData) do
        if graph[mutation.allele1] == nil then
            createNodeInGraph(graph, mutation.allele1)
        end
        if graph[mutation.allele2] == nil then
            createNodeInGraph(graph, mutation.allele2)
        end
        if graph[mutation.result] == nil then
            createNodeInGraph(graph, mutation.result)
        end

        table.insert(graph[mutation.result].parentMutations, {mutation.allele1, mutation.allele2})
        table.insert(graph[mutation.allele1].childMutations[mutation.result], mutation.allele2)
        table.insert(graph[mutation.allele2].childMutations[mutation.result], mutation.allele1)
    end

    return graph
end