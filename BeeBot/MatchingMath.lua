-- This module contains helper functions for doing calculations related to princess-drone matching.
local M = {}

-- Calculates the chance that an arbitrary offspring produced by the given princess and drone will be a pure-bred of the target species.
---@param target string
---@param princess AnalyzedBeeIndividual
---@param drone AnalyzedBeeIndividual
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfo
---@param mathFunc fun(A: string, B: string, C: string, D: string): number
---@return number
function M.SpeciesPrimarySecondaryInferenceWrapper(target, princess, drone, cacheElement, traitInfo, mathFunc)
    -- The "active" and "inactive" alleles that we can see are not necessarily equal to the "primary" and "secondary" alleles in Forestry's
    -- internal representation of the genome. If the secondary allele is dominant, and the primary allele is recessive, then the active trait
    -- will reflect the secondary allele, and the inactive trait will reflect the primary allele. Otherwise, Forestry defers to the primary
    -- allele.
    -- Because we can read Forestry's code, we know which alleles are dominant vs. recessive (information contained in `traitInfo`).
    -- If the bee has one dominant and one recessive allele, then we do not know which one is the primary or secondary because either ordering
    -- would result in the same active/inactive phenotype. In this case, the dominant is the active trait, and the recessive is inactive.
    -- However, if both are active or both are recessive, then Forestry defaults to using the primary allele as the active one and the
    -- secondary allele for the inactive one.
    local princessPossibilities = {}
    table.insert(princessPossibilities, {primary = princess.active.species.uid, secondary = princess.inactive.species.uid})
    if traitInfo["species"][princess.active.species.uid] and not traitInfo["species"][princess.inactive.species.uid] then
        table.insert(princessPossibilities, {primary = princess.inactive.species.uid, secondary = princess.active.species.uid})
    end

    -- And do the same for the given drone.
    local dronePossibilities = {}
    table.insert(dronePossibilities, {primary = drone.active.species.uid, secondary = drone.inactive.species.uid})
    if traitInfo["species"][drone.active.species.uid] and not traitInfo["species"][drone.inactive.species.uid] then
        table.insert(dronePossibilities, {primary = drone.inactive.species.uid, secondary = drone.active.species.uid})
    end

    -- Compute the outcome weighted by probability.
    local probabilitySum = 0.0
    for _, v in ipairs(princessPossibilities) do
        for _, v2 in ipairs(dronePossibilities) do
            probabilitySum = probabilitySum + ((1 / (#princessPossibilities * #dronePossibilities)) * mathFunc(v.primary, v.secondary, v2.primary, v2.secondary))
        end
    end

    return probabilitySum
end

-- Calculates the chance that an arbitrary offspring produced by a princess and drone with the given species alleles will be a pure-bred of the target species.
---@param target string
---@param princessPrimary string
---@param princessSecondary string
---@param dronePrimary string
---@param droneSecondary string
---@param cacheElement BreedInfoCacheElement
---@return number
function M.CalculateChanceArbitraryOffspringIsPureBredTarget(target, princessPrimary, princessSecondary, dronePrimary, droneSecondary, cacheElement)
    -- Mutations can only happen between a primary species of one bee and the secondary of the other.
    -- Simply checking the item name (primary species) is insufficient because mutation isn't chosen between primaries.
    local A = princessPrimary
    local B = princessSecondary
    local C = dronePrimary
    local D = droneSecondary

    -- Forestry will attempt to do a mutation twice. If the first succeeds, then parent1 will be replaced by the default genome of the resulting
    -- mutation before the Punnet Square. If the second succeeds, then parent2 will be replaced. Each mutation attempt will randomly try for a
    -- mutation between either (1) the first parent's primary gene (A) and the second parent's secondary gene (D), or (2) the first parent's
    -- secondary gene (B) and the second parent's primary gene (C). Put simpler, each mutation attempt has a 50% chance to try using A+D and a
    -- 50% chance to try using B+C. These are disjoint, so the chance of a mutation event ocurring is equal to the sum of the probabilities of
    -- each choice from AD vs. BC (50% for each) times the chance of the given mutation occurring from that choice of parent alleles.
    -- There is an additional layer here that, for each mutation, Forestry iterates through the (shuffled) list of possible mutations from the
    -- two parent species and tries for a mutation in that order. This complicates the math When a given set of parents can result in multiple
    -- mutations. However, the server has already calculated for us (stored in `breedChanceAD` and `breedChanceBC`) the probability that this
    -- set of parents mutates into the target species and the probability that this set of parents mutates into a non-target species. Therefore,
    -- we don't need to worry about that layer here.
    local breedChanceAD = cacheElement[A][D]
    local breedChanceBC = cacheElement[B][C]

    -- Each mutation attempt can result in three disjoint events: (1) the mutation fails, (2) the mutation results in the target, (3) the
    -- mutation results in a species other than the target.
    local probMutIsTarget = (0.5 * breedChanceAD.targetMutChance) + (0.5 * breedChanceBC.targetMutChance)
    local probMutIsNonTarget = (0.5 * breedChanceAD.nonTargetMutChance) + (0.5 * breedChanceBC.nonTargetMutChance)
    local probNoMut = 1.0 - (probMutIsTarget + probMutIsNonTarget)  -- Probability of no mutation is the complement of the probability of mutation.

    -- Since there are two independent mutation attempts, we have 9 distinct possibilities before we get to the Punnet Squares: one for each
    -- combination of outcomes from the two attempts. Punnet Squares select a combination of chromosomes by randomly picking one from each parent.
    -- Since there are two chromosomes from each parent, each Punnet Square has 4 possible sets of alleles. This would appear to give us 36
    -- total disjoint events.
    -- However, if a mutation occurs, *both* chromosomes from that parent are replaced with the mutated species, which guarantees that particular
    -- allele to be picked from that parent by the Punnet Square. This results in some repeated outcomes after the Punnet Square based on the
    -- prior events:
    --  * In 4 out of 9 mutation outcomes, both parents have mutated. In these scenarios, there is only one possible Punnet Square outcome.
    --  * In another 4 out of 9 mutation outcomes, just one parent has mutated. In these scenarios, there are two possible Punnet Square outcomes.
    --  * If neither parent mutates, then the resulting Punnet Square has four outcomes.
    -- Thus, there are (4*1) + (4*2) + (1*4) = 16 distinct Punnet Square outcomes to consider.
    -- Additionally, in the 5 out of 9 scenarios where either parent has mutated into a non-target species, the Punnet Square must result in an
    -- offspring with at least one non-target chromosome, which eliminates any chance of getting a pure-bred drone. Thus, we ignore the 7
    -- corresponding Punnet Square outcomes.
    -- Therefore, to calculate the chance of getting a pure-bred drone, we only need to consider 9 final Punnet Square outcomes:
    --  * When neither parent has been replaced:
    --    (1) A + C
    --    (2) A + D
    --    (3) B + C
    --    (4) B + D
    --  * When only parent1 has been replaced:
    --    (5) target + C
    --    (6) target + D
    --  * When only parent2 has been replaced:
    --    (7) A + target
    --    (8) B + target
    --  * When both parents have been replaced:
    --    (9) target + target
    -- The outcomes listed above are disjoint. Therefore, we can obtain the possibility of this particular drone being pure-bred of the target
    -- species by adding up the probability of each of the outcomes which result in a pure-bred drone of our target species (based on the
    -- input alleles for A, B, C, and D).
    -- Additionally, the randomness at each stage of this process is independent from previous stages, so the probability of a given outcome
    -- is simply the product of the probability of each of the events that are required for it to occur.
    local probPureBredTarget = 0.0

    if A == target then
        if C == target then
            -- A + C (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        if D == target then
            -- A + D (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        -- A + target (requires parent1 to not mutate and parent2 to mutate into the target, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probNoMut * probMutIsTarget * 0.5)
    end
    if B == target then
        if C == target then
            -- B + C (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        if D == target then
            -- B + D (requires no mutations and has 1 valid Punnet Square outcome).
            probPureBredTarget = probPureBredTarget + (probNoMut * probNoMut * 0.25)
        end

        -- B + target (requires parent1 to not mutate and parent2 to mutate into the target, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probNoMut * probMutIsTarget * 0.5)
    end

    if C == target then
        -- target + C (requires parent1 to mutate into the target and parent2 to not mutate, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probMutIsTarget * probNoMut * 0.5)

        -- Don't check A or B because we already did the A + C and B + C cases above.
    end
    if D == target then
        -- target + D (requires parent1 to mutate into the target and parent2 to not mutate, and has 2 valid Punnet Square outcomes)
        probPureBredTarget = probPureBredTarget + (probMutIsTarget * probNoMut * 0.5)

        -- Don't check A or B because we already did the A + D and B + D cases above.
    end

    -- target + target (all 4 Punnet Square outcomes are valid).
    probPureBredTarget = probPureBredTarget + (probMutIsTarget * probMutIsTarget * 1.0)

    return probPureBredTarget
end

-- Calculates the chance that the given princess and drone have of producing at least one pure-bred drone of the target species.
---@param target string
---@param princess AnalyzedBeeIndividual
---@param drone AnalyzedBeeIndividual
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfo
---@return number
function M.CalculateChanceAtLeastOneOffspringIsPureBredTarget(target, princess, drone, cacheElement, traitInfo)
    return M.SpeciesPrimarySecondaryInferenceWrapper(target, princess, drone, cacheElement, traitInfo, function (A, B, C, D)
        local probPureBredTarget = M.CalculateChanceArbitraryOffspringIsPureBredTarget(target, A, B, C, D, cacheElement)

        -- The probability of succeeding on at least one offspring drone is equal to the probability of *not* failing on every offspring.
        -- The chance of getting subsequent drones as pure-bred is not independent from the trait combinations, so we push that calculation
        -- down into the trait combination layer.
        return 1.0 - ((1.0 - probPureBredTarget) ^ princess.active.fertility)
    end)
end

---@param target string
---@param princess AnalyzedBeeIndividual
---@param drone AnalyzedBeeIndividual
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfo
---@return number
function M.CalculateExpectedNumberOfTargetAllelesPerOffspring(target, princess, drone, cacheElement, traitInfo)
    return M.SpeciesPrimarySecondaryInferenceWrapper(target, princess, drone, cacheElement, traitInfo, function(A, B, C, D)
        -- Handle possibility of mutation failing, producing a target, or producing a non-target.
        local breedChanceAD = cacheElement[A][D]
        local breedChanceBC = cacheElement[B][C]

        local probMutIsTarget = (0.5 * breedChanceAD.targetMutChance) + (0.5 * breedChanceBC.targetMutChance)
        local probMutIsNonTarget = (0.5 * breedChanceAD.nonTargetMutChance) + (0.5 * breedChanceBC.nonTargetMutChance)
        local probNoMut = 1.0 - (probMutIsTarget + probMutIsNonTarget)

        -- From two independent mutation attempts, we would appear to get 4 * 9 = 36 disjoint Punnet Square outcomes.
        -- However, if a mutation occurs, *both* chromosomes from that parent are replaced with the mutation, so that allele must be picked
        -- from that parent by the Punnet Square.
        --  * In 4 out of 9 mutation outcomes, both parents have mutated. In these scenarios, there is only one possible Punnet Square outcome.
        --  * In another 4 out of 9 mutation outcomes, just one parent has mutated. In these scenarios, there are two possible Punnet Square outcomes.
        --  * If neither parent mutates, then the resulting Punnet Square has four outcomes.
        -- Thus, we have (4*1) + (4*2) + (1*4) = 16 distinct Punnet Square outcomes to consider.
        -- Additionally, in the scenario where both parents have mutated into a non-target, there is zero chance of getting any target allele.
        -- Therefore, to calculate the chance of getting a pure-bred drone, we only need to consider 15 final Punnet Square outcomes:
        --  * When neither parent has been replaced:
        --    (1) A + C
        --    (2) A + D
        --    (3) B + C
        --    (4) B + D
        --  * When only parent1 has been replaced by the target:
        --    (5) target + C
        --    (6) target + D
        --  * When only parent2 has been replaced by the target:
        --    (7) A + target
        --    (8) B + target
        --  * When both parents have been replaced by the target:
        --    (9) target + target
        --  * When only parent1 has been replaced by a non-target:
        --    (10) non-target + C
        --    (11) non-target + D
        --  * When only parent2 has been replaced by a non-target:
        --    (12) A + non-target
        --    (13) B + non-target
        --  * When parent1 has been replaced by the target, and parent2 has been replaced by a non-target:
        --    (14) target + non-target
        --  * When parent1 has been replaced by a non-target, and parent2 has been replaced by the target:
        --    (15) non-target + target

        -- The outcomes listed above are disjoint. Therefore, we can obtain the expected number of pure-bred alleles by adding up the expected
        -- number of pure-bred alleles in each case multiplied by the probability of each case occurring.
        -- Randomness at each stage is independent, so the probability of an outcome is the product of the probabilities of the required events.
        local expectedPureBredAlleles = 0.0
        local numA = ((A == target) and 1) or 0
        local numB = ((B == target) and 1) or 0
        local numC = ((C == target) and 1) or 0
        local numD = ((D == target) and 1) or 0

        -- A + C (requires no mutations and has 1 valid Punnet Square outcome).
        expectedPureBredAlleles = expectedPureBredAlleles + ((numA + numC) * (probNoMut * probNoMut * 0.25))

        -- A + D (requires no mutations and has 1 valid Punnet Square outcome).
        expectedPureBredAlleles = expectedPureBredAlleles + ((numA + numD) * (probNoMut * probNoMut * 0.25))

        -- B + C (requires no mutations and has 1 valid Punnet Square outcome).
        expectedPureBredAlleles = expectedPureBredAlleles + ((numB + numC) * (probNoMut * probNoMut * 0.25))

        -- B + D (requires no mutations and has 1 valid Punnet Square outcome).
        expectedPureBredAlleles = expectedPureBredAlleles + ((numB + numD) * (probNoMut * probNoMut * 0.25))

        -- target + C (requires parent1 to mutate into the target and parent2 to not mutate, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + ((1 + numC) * (probMutIsTarget * probNoMut * 0.5))

        -- target + D (requires parent1 to mutate into the target and parent2 to not mutate, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + ((1 + numD) * (probMutIsTarget * probNoMut * 0.5))

        -- A + target (requires parent1 to not mutate and parent2 to mutate into the target, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + ((numA + 1) * (probNoMut * probMutIsTarget * 0.5))

        -- B + target (requires parent1 to not mutate and parent2 to mutate into the target, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + ((numB + 1) * (probNoMut * probMutIsTarget * 0.5))

        -- target + target (requires both parents to mutate into the target, and has 4 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (2 * (probMutIsTarget * probMutIsTarget * 1))

        -- non-target + C (requires parent1 to mutate into a non-target and parent2 to not mutate, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (numC * (probMutIsNonTarget * probNoMut * 0.5))

        -- non-target + D (requires parent1 to mutate into a non-target and parent2 to not mutate, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (numD * (probMutIsNonTarget * probNoMut * 0.5))

        -- A + non-target (requires parent1 to not mutate and parent2 to mutate into a non-target, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (numA * (probNoMut * probMutIsNonTarget * 0.5))

        -- B + non-target (requires parent1 to not mutate and parent2 to mutate into a non-target, and has 2 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (numB * (probNoMut * probMutIsNonTarget * 0.5))

        -- target + non-target (requires parent1 to mutate into the target and parent2 to mutate into a non-target, and has 4 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (1 * (probMutIsTarget * probMutIsNonTarget * 1))

        -- non-target + target (requires parent1 to mutate into a non-target and parent2 to mutate into the target, and has 4 valid Punnet Square outcomes).
        expectedPureBredAlleles = expectedPureBredAlleles + (1 * (probMutIsTarget * probMutIsNonTarget * 1))

        return expectedPureBredAlleles
    end)
end

return M
