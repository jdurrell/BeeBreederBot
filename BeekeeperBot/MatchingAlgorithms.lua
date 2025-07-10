-- This module contains algorithms for selecting the right drone to use with a given princess during the breeding process.
local M = {}
local MatchingMath = require("BeekeeperBot.MatchingMath")
local AnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

---@alias Matcher fun(princessStack: AnalyzedBeeStack, droneStackList: AnalyzedBeeStack[]): integer, number | nil
---@alias StackFinisher fun(princessStack: AnalyzedBeeStack | nil, droneStackList: AnalyzedBeeStack[] | nil): {princess: integer | nil, drones: integer | nil}
---@alias ScoreFunction fun(droneStack: AnalyzedBeeStack): number

-- Returns a matcher that prioritizes drones that are expected to produce the highest number of target alleles
-- with the given princess while also prioritizing traits that make the breeding faster namely high fertility, low lifespan,
-- cave-dwelling, and rain-tolerance. It will also prioritize traits that are generally beneficial, like production speed.
---@param numPrincesses integer
---@param mutationTrait string
---@param mutationValue any
---@param preferredTraits PartialAnalyzedBeeTraits
---@param cacheElement BreedInfoCacheElement
---@param traitInfo TraitInfoSpecies
---@return Matcher
function M.MutatedAlleleMatcher(numPrincesses, mutationTrait, mutationValue, preferredTraits, cacheElement, traitInfo)
    preferredTraits[mutationTrait] = mutationValue
    local princessCount = 0
    local comparisonPrincessIndividual  ---@type AnalyzedBeeIndividual

    -- Track the "best" of various traits to pivot to including them automatically.
    -- This optimizes the breeding speed.
    local maxFertilitySeen = ((preferredTraits.fertility ~= nil) and preferredTraits.fertility) or math.mininteger
    local minLifespanSeen = ((preferredTraits.lifespan ~= nil) and preferredTraits.lifespan) or math.maxinteger

    -- Allow a trait given by the caller to override whatever we think is "best".
    local lockFertility = (mutationTrait == "fertility") or (preferredTraits.fertility ~= nil)
    local lockLifespan = (mutationTrait == "lifespan") or (preferredTraits.lifespan ~= nil)
    local lockCaveDwelling = (mutationTrait == "caveDwelling") or (preferredTraits.caveDwelling ~= nil)
    local lockTolerantFlyer = (mutationTrait == "tolerantFlyer") or (preferredTraits.tolerantFlyer ~= nil)

    return function (princessStack, droneStackList)
        local princessBee = princessStack.individual
        if princessCount % numPrincesses == 0 then
            comparisonPrincessIndividual = princessStack.individual
        end
        princessCount = princessCount + 1

        return M.GenericHighestScore(
            droneStackList,
            function (droneStack)
                local droneBee = droneStack.individual

                local score = math.ceil(MatchingMath.CalculateExpectedNumberOfTargetAllelesPerOffspring(
                    princessStack.individual, droneStack.individual, mutationTrait, mutationValue, cacheElement, traitInfo
                ) * 1e3) * 1e6

                if score == 0 then
                    -- Don't choose a drone that has no chance of producing the desired mutation trait.
                    return 0
                end

                -- If the caller didn't specifically request one of these traits, then attempt to adjust the preferred traits for
                -- the ones that cause faster breeding.
                -- TODO: Although this is probably best in the general case, if the trait isn't actually sourced from the target species
                -- (i.e. it's from the princess or some intermittent drone), then it is much more possible for it to breed back out of the population.
                if (not lockFertility) and (math.max(droneBee.active.fertility, droneBee.inactive.fertility) > maxFertilitySeen) then
                    maxFertilitySeen = math.max(droneBee.active.fertility, droneBee.inactive.fertility)
                    preferredTraits.fertility = maxFertilitySeen
                end
                if (not lockLifespan) and math.min(droneBee.active.lifespan, droneBee.inactive.lifespan) then
                    minLifespanSeen = math.min(droneBee.active.lifespan, droneBee.inactive.lifespan)
                    preferredTraits.lifespan = minLifespanSeen
                end
                if (not lockCaveDwelling) and (droneBee.active.caveDwelling or droneBee.inactive.caveDwelling) then
                    preferredTraits.caveDwelling = true
                end
                if (not lockTolerantFlyer) and (droneBee.active.tolerantFlyer or droneBee.inactive.tolerantFlyer) then
                    preferredTraits.tolerantFlyer = true
                end

                local numTraitsAtLeastOneAllele = 0
                local numTraitsAtLeastTwoAlleles = 0
                local totalNumMatchingAlleles = 0
                for trait, value in pairs(preferredTraits) do
                    local numberMatchingAllelesOfTrait = (
                        AnalysisUtil.NumberOfMatchingAlleles(droneStack.individual, trait, value) +
                        AnalysisUtil.NumberOfMatchingAlleles(princessStack.individual, trait, value)
                    )

                    if numberMatchingAllelesOfTrait >= 1 then
                        numTraitsAtLeastOneAllele = numTraitsAtLeastOneAllele + 1
                    end
                    if numberMatchingAllelesOfTrait >= 2 then
                        numTraitsAtLeastTwoAlleles = numTraitsAtLeastTwoAlleles + 1
                    end
                    totalNumMatchingAlleles = totalNumMatchingAlleles + numberMatchingAllelesOfTrait
                end

                -- We want to try to ensure that we don't accidentally breed any target traits out of the population, so prioritize
                -- getting as many traits with a target allele as possible.
                score = score + (numTraitsAtLeastOneAllele * 1e12)
                score = score + (numTraitsAtLeastTwoAlleles * 1e10)

                -- Prioritize getting the maximum number of target alleles to eventually get pure-breds.
                score = score + totalNumMatchingAlleles * 1e4

                -- Pick the highest stack size becuase it's likely to be the closest to convergence,
                -- but only if all of its traits are pure-bred. A large stack with non-pure-bred traits
                -- will result in princess oscillation instead of convergence.
                local fullyPureBred = true
                for trait, value in pairs(droneStack.individual.active) do
                    if not AnalysisUtil.TraitIsEqual(droneStack.individual.inactive, trait, value) then
                        fullyPureBred = false
                        break
                    end
                end
                if fullyPureBred then
                    score = score + droneStack.size * 1e2
                end

                -- As a last tiebreaker, pick the drone that is most like the current princesses.
                local numMatchingTotal = 0
                for trait, value in pairs(comparisonPrincessIndividual.active) do
                    if AnalysisUtil.TraitIsEqual(comparisonPrincessIndividual.inactive, trait, value) then
                        numMatchingTotal = numMatchingTotal + AnalysisUtil.NumberOfMatchingAlleles(droneStack.individual, trait, value)
                    end
                end
                score = score + numMatchingTotal

                return score
            end,
            nil
        )
    end
end

-- Returns matcher that prioritizes drones that, when combined with the princess, give the greatest number of target alleles
-- in the two parents.
---@param targetTraits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@param numPrincesses integer
---@return Matcher
function M.ClosestMatchToTraitsMatcher(targetTraits, numPrincesses)
    local princessCount = 0
    local comparisonPrincessIndividual  ---@type AnalyzedBeeIndividual
    return function (princessStack, droneStackList)
        return M.GenericHighestScore(
            droneStackList,
            function (droneStack)
                local score = 0

                local numTraitsAtLeastOneAllele = 0
                local numTraitsAtLeastTwoAlleles = 0
                local totalNumMatchingAlleles = 0
                for trait, value in pairs(targetTraits) do
                    local numberMatchingAllelesOfTrait = (
                        AnalysisUtil.NumberOfMatchingAlleles(droneStack.individual, trait, value) +
                        AnalysisUtil.NumberOfMatchingAlleles(princessStack.individual, trait, value)
                    )

                    if numberMatchingAllelesOfTrait >= 1 then
                        numTraitsAtLeastOneAllele = numTraitsAtLeastOneAllele + 1
                    end
                    if numberMatchingAllelesOfTrait >= 2 then
                        numTraitsAtLeastTwoAlleles = numTraitsAtLeastTwoAlleles + 1
                    end
                    totalNumMatchingAlleles = totalNumMatchingAlleles + numberMatchingAllelesOfTrait
                end

                -- We want to try to ensure that we don't accidentally breed any target traits out of the population, so prioritize
                -- getting as many traits with a target allele as possible.
                score = score + (numTraitsAtLeastOneAllele << 22)
                score = score + (numTraitsAtLeastTwoAlleles << 18)

                -- Next, prioritize getting the maximum number of target alleles to eventually get pure-breds.
                score = score + (totalNumMatchingAlleles << 12)

                -- Pick the highest stack size becuase it's likely to be the closest to convergence,
                -- but only if all of its traits are pure-bred. A large stack with non-pure-bred traits
                -- will result in princess oscillation instead of convergence.
                if AnalysisUtil.AllTraitsPure(droneStack.individual) then
                    score = score + (droneStack.size << 5)
                end

                -- As a last tiebreaker, if no differences in target traits exist, then pick the drone that is most like the princess's pure-bred traits.
                -- This helps converge faster by eliminating variance in traits that we don't care about.
                -- With multiple princesses, we don't want the princesses to fracture into creating different stacks.
                if princessCount % numPrincesses == 0 then
                    comparisonPrincessIndividual = princessStack.individual
                end
                princessCount = princessCount + 1

                local numAllelesMatchingPureTraits = 0
                for trait, value in pairs(comparisonPrincessIndividual.active) do
                    if AnalysisUtil.TraitIsEqual(comparisonPrincessIndividual.inactive, trait, value) then
                        numAllelesMatchingPureTraits = numAllelesMatchingPureTraits + AnalysisUtil.NumberOfMatchingAlleles(droneStack.individual, trait, value)
                    end
                end
                score = score + numAllelesMatchingPureTraits

                return score
            end,
            nil
        )
    end
end

-- Generic function to wrap algorithms that calculate a score for each drone and pick the one with the highest score.
-- `scoreFunc` must only return values greater than or equal to 0.
---@param droneStackList AnalyzedBeeStack[]
---@param scoreFunc ScoreFunction
---@param maxPossibleScore number | nil
function M.GenericHighestScore(droneStackList, scoreFunc, maxPossibleScore)
    local maxDroneStack
    local maxScore = -1
    for _, droneStack in ipairs(droneStackList) do
        -- This doesn't really happen in production, but it helps avoid some nasty recomputation in the simulator.
        if droneStack.individual == nil then
            Print("Got a nil individual, which should never happen.")
            goto continue
        end

        local score = scoreFunc(droneStack)
        if score > maxScore then
            maxDroneStack = droneStack
            maxScore = score
            if maxScore == maxPossibleScore then
                Print(string.format("Terminating early for max score on slot %u.", droneStack.slotInChest))
                break
            end
        end

        ::continue::
    end

    if maxDroneStack == nil then
        return -1
    end

    return maxDroneStack.slotInChest, maxScore
end

-- Returns a stack finisher that returns the slot of the finished stack in ANALYZED_DRONE_CHEST if a full stack
-- of drones of the given species has been found. Otherwise, the stack finisher returns nil.
---@param target string
---@param minFertility integer
---@param stackSize integer
---@return StackFinisher
function M.DroneStackOfSpeciesPositiveFertilityFinisher(target, minFertility, stackSize)
    return function (princessStack, droneStackList)
        if droneStackList == nil then
            return {}
        end

        for _, droneStack in ipairs(droneStackList) do
            -- TODO: It is possible that drones will have a bunch of different traits and not stack up. We will need to decide whether we want to
            --       deal with this possibility or just force them to stack up. For now, it is simplest to force them to stack.
            if (
                (droneStack.individual ~= nil) and
                (droneStack.individual.active.fertility >= minFertility) and
                (droneStack.individual.inactive.fertility >= minFertility) and
                AnalysisUtil.IsPureBred(droneStack.individual, target) and
                (droneStack.size >= stackSize)
            ) then
                -- If we have a full stack of our target, then we are done.
                return {drones = droneStack.slotInChest}
            end
        end

        return {}
    end
end

-- Returns a stack finisher that returns the slot of the finished princess in ANALYZED_PRINCESS_CHEST and then slot of
-- the finished drones in ANALYZED_DRONE_CHEST if both the princess and a full stack of drones have all the target traits.
---@param targetTraits PartialAnalyzedBeeTraits | AnalyzedBeeTraits
---@param stackSize integer
---@return StackFinisher
function M.DroneStackAndPrincessOfTraitsFinisher(targetTraits, stackSize)
    return function (princessStack, droneStackList)
        if (princessStack == nil) or (droneStackList == nil) then
            return {}
        end

        local princessSlot = nil
        if AnalysisUtil.AllTraitsEqual(princessStack.individual, targetTraits) then
            princessSlot = princessStack.slotInChest
        else
            return {}
        end

        for _, stack in ipairs(droneStackList) do
            if (stack.individual ~= nil) and (stack.size >= stackSize) and AnalysisUtil.AllTraitsEqual(stack.individual, targetTraits) then
                return {princess = princessSlot, drones = stack.slotInChest}
            end
        end

        return {}
    end
end

return M
