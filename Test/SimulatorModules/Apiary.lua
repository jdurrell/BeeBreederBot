-- This module simulates the breeding RNG of an apiary. It attempts to mimic the actual Forestry code as closely as possible.
-- NOTE: This is kept separate from the ApicultureTiles component library because this is intended for simulation of the *breeding*, not the robot's interaction.
-- TODO: Account for mutation conditions (although this isn't super necessary because our system generally ensures all conditions are met).
-- TODO: Account for escritoire research (although this isn't super necessary because you don't really need to do this).
-- TODO: Account for frame modifiers.
-- TODO: Account for ignoble stock.
-- TODO: Implement RNG for traits other than species.
---@class Apiary
---@field rawMutationInfo ForestryMutation[]
---@field traitInfo TraitInfo
local M = {}

require("Shared.Shared")
local Util = require("Test.Utilities")

-- Shuffles the given list in place.
---@generic T
---@param list T[]
local function Shuffle(list)
    for i = 1, #list do
        local randIdx = math.random(#list)
        local temp = list[i]
        list[i] = list[randIdx]
        list[randIdx] = temp;
    end
end

---@param rawMutationInfo ForestryMutation[]
---@param traitInfo TraitInfo
---@return Apiary
function M:Create(rawMutationInfo, traitInfo)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.rawMutationInfo = rawMutationInfo
    obj.traitInfo = traitInfo

    return obj
end

-- Generates all descendants of the given parents.
---@param queen AnalyzedBeeIndividual
---@param drone AnalyzedBeeIndividual
---@return AnalyzedBeeIndividual princess, AnalyzedBeeIndividual[] drones
function M:GenerateDescendants(queen, drone)

    local princess = self:CreateOffspring(queen, drone, {}, {})
    local drones = {}
    for i = 1, princess.active.fertility do
        table.insert(drones, self:CreateOffspring(queen, drone, {}, {}))
    end

    return princess, drones
end

-- Generates a single descendant from the given parents.
---@param queen AnalyzedBeeIndividual
---@param drone AnalyzedBeeIndividual
---@param frames string[]
---@param conditions string[]
---@return AnalyzedBeeIndividual child
function M:CreateOffspring(queen, drone, frames, conditions)
    local parent1 = Copy(queen)
    local parent2 = Copy(drone)

    local mutated1 = self:MutateSpecies(queen.__genome, drone.__genome)
    local mutated2 = self:MutateSpecies(drone.__genome, queen.__genome)

    if mutated1 ~= nil then
        parent1.__genome = mutated1
    end
    if mutated2 ~= nil then
        parent2.__genome = mutated2
    end

    local childGenome = self:InheritChromosomes(parent1.__genome, parent2.__genome)

    return Util.CreateBee(childGenome, self.traitInfo)
end

-- Determines which chromosomes from the two parents will be inherited by the child based on a Punnet Square calculation.
---@param parent1 ForestryGenome
---@param parent2 ForestryGenome
---@return ForestryGenome
function M:InheritChromosomes(parent1, parent2)
    local genome = {}
    for gene, _ in pairs(parent1) do
        local choice1, choice2

        -- Choose which chromosome to inherit from parent1.
        if math.random() < 0.5 then
            choice1 = parent1[gene].primary
        else
            choice1 = parent1[gene].secondary
        end

        -- Choose which chromosome to inherit from parent2.
        if math.random() < 0.5 then
            choice2 = parent2[gene].primary
        else
            choice2 = parent2[gene].secondary
        end

        -- Choose the order of the inherited chromosomes.
        if math.random() < 0.5 then
            genome[gene] = {primary = choice1, secondary = choice2}
        else
            genome[gene] = {primary = choice2, secondary = choice1}
        end
    end

    return genome
end

---@param parent1 ForestryGenome
---@param parent2 ForestryGenome
---@return ForestryGenome | nil
function M:MutateSpecies(parent1, parent2)

    -- Choose between mutating on A-D or B-C.
    local allele1, allele2
    if math.random() > 0.5 then
        allele1 = parent1.species.primary.name
        allele2 = parent2.species.secondary.name
    else
        allele1 = parent1.species.secondary.name
        allele2 = parent2.species.primary.name
    end

    -- Collect the possible mutations from these two parents.
    ---@type {result: string, chance: number}[]
    local possibleMutations = {}
    for _, v in ipairs(self.rawMutationInfo) do
        if ((v.allele1 == allele1) and (v.allele2 == allele2)) or ((v.allele1 == allele2) and (v.allele2 == allele1)) then
            table.insert(possibleMutations, {result = v.result, chance = v.chance})
        end
    end

    -- Try the mutations in a random order.
    Shuffle(possibleMutations)
    for _, mut in ipairs(possibleMutations) do
        if (math.random() * 100) < mut.chance then
            -- TODO: Assign default values for the species other than just the species allele itself.
            return Util.CreateGenome(mut.result, mut.result)
        end
    end

    return nil
end

return M
