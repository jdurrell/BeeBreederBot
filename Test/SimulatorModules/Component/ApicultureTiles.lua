-- This is a module that simulates the OpenComputers/Forestry apiary component.
-- For our purposes, this is only used for importing the Bee Graph, though the
-- actual component implements other functionality as well.
---@class ApicultureTile
local M = {}

---@type ForestryMutation[]
local mutations = {}

-- Testing-only function to initialize the apiculture data for different test cases.
-- This *must* be called before actually using this module in a test.
---@param mutationSet ForestryMutation[]
function M.__Initialize(mutationSet)
    mutations = mutationSet
end

---@return BeeSpecies[]
function M.listAllSpecies()
    -- Hacky way of getting the relevant information without redoing all of TestData.
    -- TODO: This should have more official support from the mutation set.
    local speciesSet = {}
    for _, mut in ipairs(mutations) do
        speciesSet[mut.allele1] = true
        speciesSet[mut.allele2] = true
        speciesSet[mut.result] = true
    end

    local speciesArray = {}
    for species, _ in pairs(speciesSet) do
        table.insert(speciesArray, {uid = species})
    end

    return speciesArray
end

---@param uid string
---@return ParentMutation[]
function M.getBeeParents(uid)
    -- Hacky way of getting the relevant information without redoing all of TestData.
    -- TODO: This should have more official support from the mutation set.
    local parentMutations = {}
    for _, mut in ipairs(mutations) do
        if mut.result == uid then
            table.insert(parentMutations, {allele1 = {uid = mut.allele1}, allele2 = {uid = mut.allele2}, chance = mut.chance, specialConditions = mut.specialConditions})
        end
    end

    return parentMutations
end

-- Imports the list of mutations from an apiculture tile.
---@return ForestryMutation[]
function M.getBeeBreedingData()
    return mutations
end

return M
