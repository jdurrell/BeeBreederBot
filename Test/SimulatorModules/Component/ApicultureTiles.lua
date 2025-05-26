-- This is a module that simulates the OpenComputers/Forestry apiary component.
-- For our purposes, this is only used for importing the Bee Graph, though the
-- actual component implements other functionality as well.
---@class ApicultureTile
local M = {}

require("Shared.Shared")

local mutations = {}  ---@type ForestryMutation[]
local species = {}    ---@type BeeSpecies[]

-- Testing-only function to initialize the apiculture data for different test cases.
-- This *must* be called before actually using this module in a test.
---@param mutationSet ForestryMutation[]
---@param speciesList BeeSpecies[] | nil
function M.__Initialize(mutationSet, speciesList)
    mutations = mutationSet

    -- Support an unspecified list of species to avoid having to create a lot more testing data.
    if speciesList == nil then
        species = {}
        local added = {}
        for _, v in ipairs(mutationSet) do
            if added[v.allele1] == nil then
                table.insert(species, {name = v.allele1, uid = v.allele1})
                added[v.allele1] = true
            end
            if added[v.allele2] == nil then
                table.insert(species, {name = v.allele2, uid = v.allele2})
                added[v.allele2] = true
            end
            if added[v.result] == nil then
                table.insert(species, {name = v.result, uid = v.result})
                added[v.result] = true
            end
        end
    else
        species = speciesList
    end
end

---@return BeeSpecies[]
function M.listAllSpecies()
    -- Hacky way of getting the relevant information without redoing all of TestData.
    -- TODO: This should have more official support from the mutation set.
    return Copy(species)
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
