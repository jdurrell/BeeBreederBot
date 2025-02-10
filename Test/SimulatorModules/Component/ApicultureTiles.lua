-- This is a module that simulates the OpenComputers/Forestry apiary component.
-- For our purposes, this is only used for importing the Bee Graph, though the
-- actual component implements other functionality as well.
local M = {}

---@type ForestryMutation[]
local mutations = {}

-- Testing-only function to initialize the apiculture data for different test cases.
-- This *must* be called before actually using this module in a test.
---@param mutationSet ForestryMutation[]
function M.__Initialize(mutationSet)
    mutations = mutationSet
end

-- Imports the list of mutations from an apiculture tile.
---@return ForestryMutation[]
function M.getBeeBreedingData()
    return mutations
end

return M
