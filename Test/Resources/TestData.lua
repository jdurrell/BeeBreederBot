-- This file contains data for running tests.
-- NOTE: The data here is not necessarily reflective of actual genetics in any version of Forestry.
-- TODO: Collect each set of test resources into a standardized class. Also, memoize the computations.

-- TODO: Don't use this library to generate the graph since we want to be able to test it independently (even though it's mostly a simple library).
GraphParse = require("BeeServer.GraphParse")

local Res = {
    MathMargin = 0.0000001,
    MundaneBees = {"Forest", "Marshy", "Meadows", "Modest", "Tropical", "Wintry"}
}

    ---@param rawMutationInfo ForestryMutation[]
    ---@return SpeciesGraph
    function Res.GetGraphFromRawMutationInfo(rawMutationInfo)
        local graph = {}

        for _, mut in ipairs(rawMutationInfo) do
            GraphParse.AddMutationToGraph(graph, mut.allele1, mut.allele2, mut.result, mut.chance / 100.0)
        end

        return graph
    end

    ---@param graph SpeciesGraph
    ---@return TraitInfo
    function Res.TraitInfoAllRecessive(graph)
        local traitInfo = {species = {}}
        for spec, _ in pairs(graph) do
            traitInfo.species[spec] = false
        end

        return traitInfo
    end

    -- A graph made up of only mundane bees that breed into Common with 15% chance each.
    Res.BeeGraphMundaneIntoCommon = {
        MutationChanceIndividual = 0.15
    }

        ---@return TraitInfo
        function Res.BeeGraphMundaneIntoCommon.GetSpeciesTraitInfo()
            return Res.TraitInfoAllRecessive(Res.BeeGraphMundaneIntoCommon.GetGraph())
        end

        ---@return ForestryMutation[]
        function Res.BeeGraphMundaneIntoCommon.GetRawMutationInfo()
            local mutations = {}
            for i=1, #Res.MundaneBees do
                for j=(i+1), #Res.MundaneBees do
                    table.insert(mutations, {allele1=Res.MundaneBees[i], allele2=Res.MundaneBees[j], result="Common", chance=Res.BeeGraphMundaneIntoCommon.MutationChanceIndividual * 100})
                end
            end

            return mutations
        end

        ---@return SpeciesGraph
        function Res.BeeGraphMundaneIntoCommon.GetGraph()
            return Res.GetGraphFromRawMutationInfo(Res.BeeGraphMundaneIntoCommon.GetRawMutationInfo())
        end

    -- A graph made up of only mundane bees that breed into Common, then can breed with Common to create Cultivated.
    Res.BeeGraphMundaneIntoCommonIntoCultivated = {}
        ---@return TraitInfo
        function Res.BeeGraphMundaneIntoCommonIntoCultivated.GetSpeciesTraitInfo()
            return Res.TraitInfoAllRecessive(Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph())
        end

        ---@return ForestryMutation[]
        function Res.BeeGraphMundaneIntoCommonIntoCultivated.GetRawMutationInfo()
            local mutations = Res.BeeGraphMundaneIntoCommon.GetRawMutationInfo()
            for _, bee in ipairs(Res.MundaneBees) do
                table.insert(mutations, {allele1=bee, allele2="Common", result="Cultivated", chance=12.0})
            end

            return mutations
        end

        ---@return SpeciesGraph
        function Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
            return Res.GetGraphFromRawMutationInfo(Res.BeeGraphMundaneIntoCommonIntoCultivated.GetRawMutationInfo())
        end

    Res.BeeGraphSimpleDuplicateMutations = {
        ExpectedBreedInfo = {
            Result1={["Root1-Root2"]={targetMutChance=0.3068333, nonTargetMutChance=0.5491667}},
            Result2={["Root1-Root2"]={targetMutChance=0.1058333, nonTargetMutChance=0.7501667}},
            Result3={["Root1-Root2"]={targetMutChance=0.3925, nonTargetMutChance=0.4635}},
            Result4={["Root1-Root2"]={targetMutChance=0.0508333, nonTargetMutChance=0.8051667}}
        },
        RawMutationInfo = {
            {allele1="Root1", allele2="Root2", result="Result1", chance=50.0},
            {allele1="Root1", allele2="Root2", result="Result2", chance=20.0},
            {allele1="Root1", allele2="Root2", result="Result3", chance=60.0},
            {allele1="Root1", allele2="Root2", result="Result4", chance=10.0}
        }
    }
        ---@return TraitInfo
        function Res.BeeGraphSimpleDuplicateMutations.GetSpeciesTraitInfo()
            return Res.TraitInfoAllRecessive(Res.BeeGraphSimpleDuplicateMutations.GetGraph())
        end

        ---@return ForestryMutation[]
        function Res.BeeGraphSimpleDuplicateMutations.GetRawMutationInfo()
            return Res.BeeGraphSimpleDuplicateMutations.RawMutationInfo
        end

        ---@return SpeciesGraph    
        function Res.BeeGraphSimpleDuplicateMutations.GetGraph()
            return Res.GetGraphFromRawMutationInfo(Res.BeeGraphSimpleDuplicateMutations.GetRawMutationInfo())
        end

    Res.BeeGraphSimpleDominance = {
        RawMutationInfo = {
            {allele1="Recessive1", allele2="Recessive2", result="RecessiveResult", chance=15.0},
            {allele1="Recessive1", allele2="Dominant1", result="RecessiveResult", chance=18.0},
            {allele1="Recessive2", allele2="Recessive3", result="DominantResult", chance=20.0},
            {allele1="Recessive1", allele2="Dominant1", result="DominantResult", chance=12.0},
            {allele1="Dominant2", allele2="Dominant3", result="DominantResult", chance=10.0}
        },
        TraitInfo = {species = {
            ["Recessive1"] = false,
            ["Recessive2"] = false,
            ["Recessive3"] = false,
            ["Dominant1"] = true,
            ["Dominant2"] = true,
            ["Dominant3"] = true,
            ["RecessiveResult"] = false,
            ["DominantResult"] = true
        }}
    }
        ---@return TraitInfo
        function Res.BeeGraphSimpleDominance.GetSpeciesTraitInfo()
            return Res.BeeGraphSimpleDominance.TraitInfo
        end

        ---@return ForestryMutation[]
        function Res.BeeGraphSimpleDominance.GetRawMutationInfo()
            return Res.BeeGraphSimpleDominance.RawMutationInfo
        end

        ---@return SpeciesGraph
        function Res.BeeGraphSimpleDominance.GetGraph()
            return Res.GetGraphFromRawMutationInfo(Res.BeeGraphSimpleDominance.GetRawMutationInfo())
        end

    Res.BeeGraphSimpleDominanceDuplicateMutations = {
        TraitInfo = {species = {
            ["Root1"] = false,
            ["Root2"] = true,
            ["Result1"] = false,
            ["Result2"] = true,
            ["Result3"] = false,
            ["Result4"] = true
        }}
    }
        ---@return TraitInfo
        function Res.BeeGraphSimpleDominanceDuplicateMutations.GetSpeciesTraitInfo()
            return Res.BeeGraphSimpleDominanceDuplicateMutations.TraitInfo
        end

        ---@return ForestryMutation[]
        function Res.BeeGraphSimpleDominanceDuplicateMutations.GetRawMutationInfo()
            return Res.BeeGraphSimpleDuplicateMutations.GetRawMutationInfo()
        end

        ---@return SpeciesGraph
        function Res.BeeGraphSimpleDominanceDuplicateMutations.GetGraph()
            return Res.BeeGraphSimpleDuplicateMutations.GetGraph()
        end

    -- The actual mutation list exported from OpenComputers/Forestry in GTNH 2.6.1.
    Res.BeeGraphActual = {
        RawMutationInfo = {
            {allele1="Modest", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Industrious", allele2="Cultivated", result="Aluminum", chance=10.0},
            {allele1="Hermitic", allele2="Lapis", result="Certus", chance=10.0},
            {allele1="Botanic", allele2="Earthen", result="Blossom", chance=12.0},
            {allele1="Ender", allele2="Stainless Steel", result="End Dust", chance=8.0},
            {allele1="Arcane", allele2="Supernatural", result="Ethereal", chance=7.0},
            {allele1="Modest", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Excited", allele2="Energetic", result="Ecstatic", chance=8.0},
            {allele1="Nuclear", allele2="Yellorium", result="Cyanite", chance=5.0},
            {allele1="Aware", allele2="Spirit", result="Soul", chance=7.0},
            {allele1="Space", allele2="Iron", result="Meteoric Iron", chance=9.0},
            {allele1="Botanic", allele2="Blossom", result="Floral", chance=8.0},
            {allele1="Yellow", allele2="Red", result="Orange", chance=10.0},
            {allele1="Silver", allele2="Iron", result="Astral Silver", chance=3.0},
            {allele1="Tropical", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Oil", allele2="Infinity Catalyst", result="Kevlar", chance=4.0},
            {allele1="Mystical", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Infernal", allele2="Hateful", result="Spiteful", chance=7.0},
            {allele1="Imperial", allele2="Abandoned", result="Draconic", chance=6.0},
            {allele1="Common", allele2="Skulking", result="Beefy", chance=12.0},
            {allele1="Callisto", allele2="Absolute", result="Callisto Ice", chance=7.0},
            {allele1="Diligent", allele2="Excited", result="Energetic", chance=8.0},
            {allele1="Beefy", allele2="Sheepish", result="Neighsayer", chance=12.0},
            {allele1="Common", allele2="Rocky", result="Cultivated", chance=12.0},
            {allele1="Forest", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Forest", allele2="Lapis", result="Emerald", chance=5.0},
            {allele1="Unweary", allele2="Tolerant", result="Robust", chance=10.0},
            {allele1="Attuned", allele2="Vis", result="Rejuvenating", chance=8.0},
            {allele1="Heroic", allele2="Manganese", result="Tungsten", chance=5.0},
            {allele1="Unstable", allele2="Galvanized", result="Nuclear", chance=5.0},
            {allele1="Shadow Metal", allele2="Wither", result="Essentia", chance=5.0},
            {allele1="Meadows", allele2="Diligent", result="Rural", chance=12.0},
            {allele1="Farmerly", allele2="Water", result="Bovine", chance=10.0},
            {allele1="Diamond", allele2="Ruby", result="Red Garnet", chance=4.0},
            {allele1="Pluto", allele2="Naquadah", result="Haume", chance=3.5},
            {allele1="Unusual", allele2="Mutable", result="Transmuting", chance=9.0},
            {allele1="Barnarda", allele2="Americium", result="BarnardaC", chance=1.5},
            {allele1="Titanium", allele2="Ruby", result="Chrome", chance=5.0},
            {allele1="Industrious", allele2="Wintry", result="Icy", chance=12.0},
            {allele1="Boggy", allele2="Miry", result="Fungal", chance=8.0},
            {allele1="Tropical", allele2="Skulking", result="Spidery", chance=10.0},
            {allele1="Firestone", allele2="Arcaneshards", result="Fireessence", chance=4.0},
            {allele1="Silicon", allele2="Skystone", result="Certus", chance=13.0},
            {allele1="Infernal", allele2="Eldritch", result="Hateful", chance=9.0},
            {allele1="Blue", allele2="Pink", result="Magenta", chance=10.0},
            {allele1="Meadows", allele2="Valiant", result="Saffron", chance=5.0},
            {allele1="Wintry", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Centauri", allele2="Infinity Catalyst", result="aCentauri", chance=3.0},
            {allele1="Skulking", allele2="Mysterious", result="Big Bad", chance=7.0},
            {allele1="Common", allele2="Wintry", result="Cultivated", chance=12.0},
            {allele1="Monastic", allele2="Arcane", result="Pupil", chance=10.0},
            {allele1="Unstable", allele2="Corroded", result="Nuclear", chance=5.0},
            {allele1="Diligent", allele2="Water", result="Ocean", chance=10.0},
            {allele1="Agrarian", allele2="Batty", result="Sandwich", chance=10.0},
            {allele1="Imperial", allele2="Plumbum", result="Auric", chance=8.0},
            {allele1="Marshy", allele2="Noble", result="Miry", chance=15.0},
            {allele1="Batty", allele2="Ethereal", result="Ghastly", chance=9.0},
            {allele1="Blue", allele2="Green", result="Cyan", chance=10.0},
            {allele1="Jupiter", allele2="Volcanic", result="Io", chance=15.0},
            {allele1="Certus", allele2="Lapis", result="Sapphire", chance=5.0},
            {allele1="Mystical", allele2="Mutable", result="Invisible", chance=15.0},
            {allele1="Meadows", allele2="Desolate", result="Decaying", chance=15.0},
            {allele1="Plutonium", allele2="Iridium", result="Naquadah", chance=3.0},
            {allele1="Natural", allele2="Bleached", result="Lime", chance=5.0},
            {allele1="Plutonium", allele2="Iridium", result="Naquadria", chance=0.80000001192093},
            {allele1="Porcine", allele2="Skulking", result="Sheepish", chance=13.0},
            {allele1="Valiant", allele2="Water", result="Prussian", chance=5.0},
            {allele1="Supernatural", allele2="Windy", result="Air", chance=15.0},
            {allele1="Eldritch", allele2="Charmed", result="Enchanted", chance=8.0},
            {allele1="Ferrous", allele2="Flux", result="Void", chance=5.0},
            {allele1="Cyanite", allele2="Yellorium", result="Blutonium", chance=5.0},
            {allele1="Rural", allele2="Unweary", result="Farmerly", chance=10.0},
            {allele1="Primeval", allele2="Growing", result="Fossilised", chance=8.0},
            {allele1="Cultivated", allele2="Celebratory", result="Chad", chance=5.0},
            {allele1="Unusual", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Furious", allele2="Excited", result="Glowering", chance=5.0},
            {allele1="Sorcerous", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Diligent", allele2="Unweary", result="Industrious", chance=8.0},
            {allele1="Wintry", allele2="Diligent", result="Frigid", chance=10.0},
            {allele1="Unusual", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Ethereal", allele2="Oblivion", result="Nameless", chance=10.0},
            {allele1="Ur Ghast", allele2="Salis Mundus", result="Snowqueen", chance=4.0},
            {allele1="Ardite", allele2="Cobalt", result="Manyullyn", chance=9.0},
            {allele1="Earthen", allele2="Windy", result="Skystone", chance=20.0},
            {allele1="MakeMake", allele2="Thorium", result="Barnarda", chance=1.5},
            {allele1="Monastic", allele2="Vindictive", result="Vengeful", chance=8.0},
            {allele1="Wintry", allele2="Water", result="Common", chance=15.0},
            {allele1="Imperial", allele2="Infernal", result="Cobalt", chance=11.0},
            {allele1="Miry", allele2="Water", result="Damp", chance=10.0},
            {allele1="Sorcerous", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Wintry", allele2="Diligent", result="White", chance=10.0},
            {allele1="Hermitic", allele2="Ender", result="Spectral", chance=4.0},
            {allele1="Sinister", allele2="Modest", result="Fiendish", chance=40.0},
            {allele1="Sinister", allele2="Embittered", result="Fiendish", chance=40.0},
            {allele1="Ash", allele2="Peat", result="Sulfur", chance=15.0},
            {allele1="Thaumic Shards", allele2="End Dust", result="Arcaneshards", chance=5.0},
            {allele1="Ethereal", allele2="Ghastly", result="Wispy", chance=9.0},
            {allele1="Distilled", allele2="Oily", result="Refined", chance=8.0},
            {allele1="Attuned", allele2="Marshy", result="Common", chance=15.0},
            {allele1="MakeMake", allele2="Haume", result="TCeti", chance=2.5},
            {allele1="Sinister", allele2="Cultivated", result="Fiendish", chance=40.0},
            {allele1="Energetic Alloy", allele2="Phantasmal", result="Vibrant Alloy", chance=6.0},
            {allele1="Diamond", allele2="Unstable", result="Caelestis", chance=10.0},
            {allele1="Marshy", allele2="Water", result="Common", chance=15.0},
            {allele1="Unusual", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Pluto", allele2="Naquadria", result="MakeMake", chance=3.5},
            {allele1="MakeMake", allele2="Desh", result="Centauri", chance=3.0},
            {allele1="Ectoplasma", allele2="Arcaneshards", result="Dragon Essence", chance=4.0},
            {allele1="Wintry", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Sinister", allele2="Tropical", result="Malicious", chance=10.0},
            {allele1="Hydra", allele2="Thaumium Dust", result="Ur Ghast", chance=5.0},
            {allele1="Marshy", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Oblivion", allele2="Nameless", result="Abandoned", chance=8.0},
            {allele1="Cultivated", allele2="Modest", result="Sinister", chance=60.0},
            {allele1="Wintry", allele2="Resilient", result="Corroded", chance=5.0},
            {allele1="Eldritch", allele2="Forest", result="Rooted", chance=15.0},
            {allele1="Certus", allele2="Coal", result="Diamond", chance=3.0},
            {allele1="Iron", allele2="Tin", result="Zinc", chance=13.0},
            {allele1="Industrious", allele2="Demonic", result="Redstone", chance=10.0},
            {allele1="Explosive", allele2="Diamond", result="Bedrockium", chance=2.0},
            {allele1="Industrious", allele2="Heroic", result="Space", chance=10.0},
            {allele1="Jupiter", allele2="Mithril", result="Venus", chance=12.5},
            {allele1="Jupiter", allele2="Titanium", result="Ganymed", chance=15.0},
            {allele1="Krypton", allele2="Snowqueen", result="Xenon", chance=2.0},
            {allele1="Unusual", allele2="Forest", result="Common", chance=15.0},
            {allele1="Lutetium", allele2="Chrome", result="Americium", chance=1.25},
            {allele1="Malicious", allele2="Viscous", result="Corrosive", chance=10.0},
            {allele1="Ender", allele2="Thaumium Dust", result="Endium", chance=8.0},
            {allele1="Mystical", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Boggy", allele2="Fungal", result="Fungal", chance=8.0},
            {allele1="Uranium", allele2="Emerald", result="Plutonium", chance=3.0},
            {allele1="Unusual", allele2="Meadows", result="Common", chance=15.0},
            {allele1="Forest", allele2="Resilient", result="Lustered", chance=5.0},
            {allele1="Forest", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Ebony", allele2="Bleached", result="Slate", chance=5.0},
            {allele1="Marshy", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Ordered", allele2="Thaumium Dust", result="Thauminite", chance=8.0},
            {allele1="Earthen", allele2="Earthen", result="Solum", chance=8.0},
            {allele1="Ender", allele2="Zinc", result="Stardust", chance=8.0},
            {allele1="Withering", allele2="Draconic", result="Wither", chance=1.0},
            {allele1="Earth", allele2="Fire", result="Order", chance=15.0},
            {allele1="Redstone Alloy", allele2="Demonic", result="Energetic Alloy", chance=9.0},
            {allele1="Common", allele2="Modest", result="Cultivated", chance=12.0},
            {allele1="Attuned", allele2="Aware", result="Spirit", chance=8.0},
            {allele1="Redstone Alloy", allele2="Iron", result="Conductive Iron", chance=8.0},
            {allele1="Blue", allele2="Yellow", result="Green", chance=10.0},
            {allele1="Rural", allele2="Sweetened", result="Sugary", chance=15.0},
            {allele1="Dragon Essence", allele2="Neutronium", result="Dragon Blood", chance=2.0},
            {allele1="Industrious", allele2="Thriving", result="Blooming", chance=8.0},
            {allele1="Majestic", allele2="Galvanized", result="Shining", chance=2.0},
            {allele1="Glittering", allele2="Shining", result="Valuable", chance=2.0},
            {allele1="Vega", allele2="Naquadria", result="VegaB", chance=2.0},
            {allele1="Imperial", allele2="Resilient", result="Lapis", chance=5.0},
            {allele1="Slate", allele2="Bleached", result="Ashen", chance=5.0},
            {allele1="Austere", allele2="Auric", result="Diamandi", chance=7.0},
            {allele1="Poultry", allele2="Spidery", result="Catty", chance=15.0},
            {allele1="Mars", allele2="Desh", result="Jupiter", chance=15.0},
            {allele1="Shadowed", allele2="Darkened", result="Abyssal", chance=8.0},
            {allele1="Sorcerous", allele2="Cultivated", result="Eldritch", chance=12.0},
            {allele1="Sweetened", allele2="Growing", result="Ripening", chance=5.0},
            {allele1="Common", allele2="Embittered", result="Cultivated", chance=12.0},
            {allele1="Thaumium Dust", allele2="Silver", result="Quicksilver", chance=10.0},
            {allele1="Attuned", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Industrious", allele2="Infernal", result="Ardite", chance=9.0},
            {allele1="Electrical Steel", allele2="Demonic", result="Dark Steel", chance=7.0},
            {allele1="Cultivated", allele2="Lapis", result="Diamond", chance=5.0},
            {allele1="Tropical", allele2="Water", result="Common", chance=15.0},
            {allele1="Redstone", allele2="Ruby", result="Firestone", chance=4.0},
            {allele1="Monastic", allele2="Secluded", result="Hermitic", chance=8.0},
            {allele1="Austere", allele2="Desolate", result="Hazardous", chance=5.0},
            {allele1="Majestic", allele2="Leaden", result="Shining", chance=2.0},
            {allele1="Corrosive", allele2="Caustic", result="Acidic", chance=4.0},
            {allele1="White", allele2="Diligent", result="Black", chance=10.0},
            {allele1="Fiendish", allele2="Embittered", result="Furious", chance=30.0},
            {allele1="Unstable", allele2="Tarnished", result="Nuclear", chance=5.0},
            {allele1="Marshy", allele2="Valiant", result="Sepia", chance=5.0},
            {allele1="Forest", allele2="Valiant", result="Maroon", chance=5.0},
            {allele1="Emerald", allele2="Red Garnet", result="Yellow Garnet", chance=3.0},
            {allele1="Mars", allele2="Titanium", result="Desh", chance=9.0},
            {allele1="Sweetened", allele2="Thriving", result="Fruity", chance=5.0},
            {allele1="Modest", allele2="Sinister", result="Frugal", chance=16.0},
            {allele1="Thaumium Dust", allele2="Thaumic Shards", result="Tainted", chance=7.0},
            {allele1="Modest", allele2="Water", result="Common", chance=15.0},
            {allele1="Lich", allele2="Ignis", result="Hydra", chance=6.0},
            {allele1="Callisto", allele2="Lead", result="Ledox", chance=7.0},
            {allele1="Demonic", allele2="Spiteful", result="Withering", chance=6.0},
            {allele1="Tropical", allele2="Resilient", result="Galvanized", chance=5.0},
            {allele1="Rural", allele2="Primeval", result="Fossilised", chance=8.0},
            {allele1="Lead", allele2="Tin", result="Silver", chance=10.0},
            {allele1="Cultivated", allele2="Eldritch", result="Charmed", chance=10.0},
            {allele1="Forest", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Clay", allele2="Diligent", result="Tin", chance=13.0},
            {allele1="Meadows", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Viscous", allele2="Glutinous", result="Sticky", chance=8.0},
            {allele1="Oxygen", allele2="Hydrogen", result="Nitrogen", chance=15.0},
            {allele1="Saturn", allele2="Nickel", result="Titan", chance=12.5},
            {allele1="Diligent", allele2="Water", result="River", chance=10.0},
            {allele1="Maroon", allele2="Bleached", result="Lavender", chance=5.0},
            {allele1="Transmuting", allele2="Empowering", result="Flux", chance=11.0},
            {allele1="Forest", allele2="Water", result="Common", chance=15.0},
            {allele1="Firey", allele2="Firey", result="Ignis", chance=8.0},
            {allele1="Valiant", allele2="Cultivated", result="Excited", chance=10.0},
            {allele1="Helium", allele2="Dragon Essence", result="Oxygen", chance=15.0},
            {allele1="Modest", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Modest", allele2="Resilient", result="Leaden", chance=5.0},
            {allele1="Apatite", allele2="Ash", result="Phosphorus", chance=12.0},
            {allele1="Wintry", allele2="Resilient", result="Galvanized", chance=5.0},
            {allele1="Sinister", allele2="Rocky", result="Shadowed", chance=10.0},
            {allele1="Attuned", allele2="Modest", result="Common", chance=15.0},
            {allele1="Ash", allele2="Apatite", result="Fertilizer", chance=8.0},
            {allele1="Arcane", allele2="Pupil", result="Scholarly", chance=8.0},
            {allele1="Steadfast", allele2="Valiant", result="Heroic", chance=6.0},
            {allele1="Prehistoric", allele2="Resilient", result="Unstable", chance=5.0},
            {allele1="Cultivated", allele2="Tropical", result="Sinister", chance=60.0},
            {allele1="Fertilizer", allele2="Ash", result="Tea", chance=10.0},
            {allele1="Forest", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Watery", allele2="End Dust", result="Helium", chance=10.0},
            {allele1="Redstone", allele2="Lapis", result="Fluix", chance=7.0},
            {allele1="Watery", allele2="Watery", result="Aqua", chance=8.0},
            {allele1="Austere", allele2="Tropical", result="Exotic", chance=12.0},
            {allele1="Ender", allele2="End Dust", result="Ectoplasma", chance=5.0},
            {allele1="Windy", allele2="Somnolent", result="Dreaming", chance=8.0},
            {allele1="Rocky", allele2="Water", result="Common", chance=15.0},
            {allele1="Icy", allele2="Wintry", result="Glacial", chance=8.0},
            {allele1="Skulking", allele2="Pupil", result="Brainy", chance=9.0},
            {allele1="Exotic", allele2="Viscous", result="Glutinous", chance=8.0},
            {allele1="Exotic", allele2="Water", result="Viscous", chance=10.0},
            {allele1="Sorcerous", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Valiant", allele2="Rocky", result="Ebony", chance=5.0},
            {allele1="Attuned", allele2="Water", result="Common", chance=15.0},
            {allele1="Tungsten", allele2="Platinum", result="Iridium", chance=5.0},
            {allele1="Water", allele2="Fire", result="Earth", chance=15.0},
            {allele1="Windy", allele2="Windy", result="Aer", chance=8.0},
            {allele1="White", allele2="Red", result="Pink", chance=10.0},
            {allele1="Exotic", allele2="Tropical", result="Edenic", chance=8.0},
            {allele1="Thorium", allele2="Decaying", result="Lutetium", chance=1.0},
            {allele1="Unusual", allele2="Mutable", result="Crumbling", chance=9.0},
            {allele1="Industrious", allele2="Peat", result="Coal", chance=9.0},
            {allele1="Unstable", allele2="Lustered", result="Nuclear", chance=5.0},
            {allele1="Supernatural", allele2="Naga", result="Lich", chance=7.0},
            {allele1="Ethereal", allele2="Infernal", result="Vis", chance=9.0},
            {allele1="Redstone", allele2="Diamond", result="Ruby", chance=5.0},
            {allele1="Black", allele2="White", result="Gray", chance=10.0},
            {allele1="Transmuting", allele2="Rejuvenating", result="Pure", chance=8.0},
            {allele1="Argon", allele2="Hydra", result="Neon", chance=6.0},
            {allele1="Oxygen", allele2="Watery", result="Hydrogen", chance=15.0},
            {allele1="Neon", allele2="Ur Ghast", result="Krypton", chance=4.0},
            {allele1="Noble", allele2="Cultivated", result="Majestic", chance=8.0},
            {allele1="Redstone", allele2="Red Alloy", result="Redstone Alloy", chance=8.0},
            {allele1="Certus", allele2="Ender", result="Olivine", chance=5.0},
            {allele1="Salt", allele2="Aluminium", result="Lithium", chance=5.0},
            {allele1="Maroon", allele2="Prussian", result="Indigo", chance=5.0},
            {allele1="Uranus", allele2="Oriharukon", result="Neptune", chance=7.0},
            {allele1="Fiendish", allele2="Corrosive", result="Caustic", chance=8.0},
            {allele1="Attuned", allele2="Cultivated", result="Eldritch", chance=12.0},
            {allele1="Austere", allele2="Argentum", result="Esmeraldi", chance=6.0},
            {allele1="Lead", allele2="Osmium", result="Indium", chance=1.0},
            {allele1="Pupil", allele2="Scholarly", result="Savant", chance=6.0},
            {allele1="Ethereal", allele2="Arcane", result="Ordered", chance=8.0},
            {allele1="Certus", allele2="Skystone", result="Fluix", chance=17.0},
            {allele1="Spectral", allele2="Spatial", result="Quantum", chance=5.0},
            {allele1="Sinister", allele2="Tropical", result="Fiendish", chance=40.0},
            {allele1="Farmerly", allele2="Industrious", result="Agrarian", chance=6.0},
            {allele1="Meadows", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Space", allele2="Clay", result="Moon", chance=25.0},
            {allele1="Agrarian", allele2="Exotic", result="Scummy", chance=2.0},
            {allele1="Imperial", allele2="Timely", result="Lordly", chance=8.0},
            {allele1="Boggy", allele2="Damp", result="Sodden", chance=8.0},
            {allele1="Tropical", allele2="Diligent", result="Brown", chance=10.0},
            {allele1="Lapis", allele2="Energy", result="Lapotron", chance=6.0},
            {allele1="Tropical", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Prussian", allele2="Bleached", result="Azure", chance=5.0},
            {allele1="Meadows", allele2="Resilient", result="Leaden", chance=5.0},
            {allele1="Mystical", allele2="Water", result="Common", chance=15.0},
            {allele1="Zinc", allele2="Silver", result="Arsenic", chance=10.0},
            {allele1="Majestic", allele2="Tarnished", result="Shining", chance=2.0},
            {allele1="Attuned", allele2="Meadows", result="Common", chance=15.0},
            {allele1="Big Bad", allele2="Vis", result="Ravening", chance=20.0},
            {allele1="Sorcerous", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Unusual", allele2="Common", result="Cultivated", chance=12.0},
            {allele1="Io", allele2="Platinum", result="Mithril", chance=7.0},
            {allele1="Modest", allele2="Frugal", result="Austere", chance=8.0},
            {allele1="Jupiter", allele2="Frigid", result="Callisto", chance=15.0},
            {allele1="Thaumium Dust", allele2="Stickyresin", result="Amber", chance=10.0},
            {allele1="Rooted", allele2="Watery", result="Somnolent", chance=16.0},
            {allele1="Ectoplasma", allele2="Stardust", result="Silverfish", chance=5.0},
            {allele1="Saturn", allele2="Trinium", result="Uranus", chance=10.0},
            {allele1="Sorcerous", allele2="Meadows", result="Common", chance=15.0},
            {allele1="Rural", allele2="Clay", result="Peat", chance=10.0},
            {allele1="Sinister", allele2="Fiendish", result="Demonic", chance=25.0},
            {allele1="Arid", allele2="Barren", result="Desolate", chance=10.0},
            {allele1="Mystical", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Jupiter", allele2="Ledox", result="Saturn", chance=12.5},
            {allele1="Thaumium Dust", allele2="Aqua", result="Thaumic Shards", chance=10.0},
            {allele1="Unusual", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Eldritch", allele2="Imperial", result="Naga", chance=8.0},
            {allele1="Supernatural", allele2="Air", result="Fire", chance=15.0},
            {allele1="Helium", allele2="Lich", result="Argon", chance=8.0},
            {allele1="Pluto", allele2="Plutonium", result="Black Plutonium", chance=2.0},
            {allele1="Noble", allele2="Majestic", result="Imperial", chance=8.0},
            {allele1="Redstone", allele2="Coolant", result="Cryotheum", chance=4.0},
            {allele1="Meadows", allele2="Frugal", result="Arid", chance=10.0},
            {allele1="Mars", allele2="Meteoric Iron", result="Ceres", chance=20.0},
            {allele1="Unusual", allele2="Water", result="Common", chance=15.0},
            {allele1="Neptune", allele2="Plutonium", result="Pluto", chance=5.0},
            {allele1="Mystical", allele2="Forest", result="Common", chance=15.0},
            {allele1="Tropical", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Supernatural", allele2="Ethereal", result="Windy", chance=14.0},
            {allele1="Unweary", allele2="Growing", result="Thriving", chance=10.0},
            {allele1="Jupiter", allele2="Tungsten", result="Mercury", chance=12.5},
            {allele1="Tropical", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Mystical", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Olivine", allele2="Diamond", result="Emerald", chance=4.0},
            {allele1="Coal", allele2="Copper", result="Lead", chance=13.0},
            {allele1="Red", allele2="Blue", result="Purple", chance=10.0},
            {allele1="Common", allele2="Skulking", result="Porcine", chance=12.0},
            {allele1="Forest", allele2="Modest", result="Common", chance=15.0},
            {allele1="Modest", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Sinister", allele2="Common", result="Tricky", chance=10.0},
            {allele1="Rejuvenating", allele2="Empowering", result="Nexus", chance=10.0},
            {allele1="Silver", allele2="Osmium", result="Indium", chance=1.0},
            {allele1="TCeti", allele2="TCetiE", result="Seaweed", chance=2.5},
            {allele1="Industrious", allele2="Forest", result="Stannum", chance=12.0},
            {allele1="Redstone", allele2="Energy", result="Pyrotheum", chance=4.0},
            {allele1="Forest", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Noble", allele2="Monastic", result="Mystical", chance=5.0},
            {allele1="Marshy", allele2="Resilient", result="Lustered", chance=5.0},
            {allele1="Uranus", allele2="Tin", result="Miranda", chance=10.0},
            {allele1="Imperial", allele2="Ethereal", result="Timely", chance=8.0},
            {allele1="Icy", allele2="Glacial", result="Coolant", chance=10.0},
            {allele1="Mystical", allele2="Common", result="Cultivated", chance=12.0},
            {allele1="Demonic", allele2="Volcanic", result="Energy", chance=10.0},
            {allele1="Chrome", allele2="Steel", result="Stainless Steel", chance=9.0},
            {allele1="Chaotic", allele2="Void", result="Shadow Metal", chance=6.0},
            {allele1="Lead", allele2="Copper", result="Gold", chance=13.0},
            {allele1="Modest", allele2="Fiendish", result="Frugal", chance=10.0},
            {allele1="Titanium", allele2="Aluminium", result="Manganese", chance=5.0},
            {allele1="White", allele2="Green", result="Lime", chance=10.0},
            {allele1="Ocean", allele2="Frigid", result="Absolute", chance=10.0},
            {allele1="Supernatural", allele2="Ethereal", result="Earthen", chance=14.0},
            {allele1="Unusual", allele2="Cultivated", result="Eldritch", chance=12.0},
            {allele1="Common", allele2="Industrious", result="Ferrous", chance=12.0},
            {allele1="Tropical", allele2="Resilient", result="Tarnished", chance=5.0},
            {allele1="Esoteric", allele2="Mysterious", result="Arcane", chance=8.0},
            {allele1="Shadowed", allele2="Rocky", result="Darkened", chance=8.0},
            {allele1="Firestone", allele2="Coal", result="Explosive", chance=4.0},
            {allele1="Water", allele2="Lapis", result="Sapphire", chance=5.0},
            {allele1="Farmerly", allele2="Tropical", result="Caffeinated", chance=10.0},
            {allele1="Spectral", allele2="Ender", result="Phantasmal", chance=2.0},
            {allele1="Naquadah", allele2="Thaumic Shards", result="D-O-B", chance=2.0},
            {allele1="Lead", allele2="Oberon", result="Oriharukon", chance=5.0},
            {allele1="Ebony", allele2="Ocean", result="Stained", chance=8.0},
            {allele1="Embittered", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Sorcerous", allele2="Forest", result="Common", chance=15.0},
            {allele1="Natural", allele2="Prussian", result="Turquoise", chance=5.0},
            {allele1="Modest", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Eldritch", allele2="Esoteric", result="Mysterious", chance=8.0},
            {allele1="Moon", allele2="Iron", result="Mars", chance=20.0},
            {allele1="Monastic", allele2="Demonic", result="Vindictive", chance=4.0},
            {allele1="Distilled", allele2="Resinous", result="Elastic", chance=8.0},
            {allele1="Io", allele2="Mithril", result="Mytryl", chance=6.0},
            {allele1="Sorcerous", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Majestic", allele2="Clay", result="Copper", chance=13.0},
            {allele1="Saturn", allele2="Chrome", result="Enceladus", chance=12.5},
            {allele1="Tungsten", allele2="Platinum", result="Osmium", chance=5.0},
            {allele1="Wintry", allele2="Valiant", result="Bleached", chance=5.0},
            {allele1="Cultivated", allele2="Embittered", result="Sinister", chance=60.0},
            {allele1="Watery", allele2="Catty", result="Walrus", chance=22.5},
            {allele1="Majestic", allele2="Lustered", result="Glittering", chance=2.0},
            {allele1="Industrious", allele2="Meadows", result="Cuprum", chance=12.0},
            {allele1="Forest", allele2="Meadows", result="Common", chance=15.0},
            {allele1="Common", allele2="Arid", result="Barren", chance=10.0},
            {allele1="Attuned", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Diligent", allele2="Rocky", result="Tolerant", chance=12.0},
            {allele1="Marshy", allele2="Miry", result="Boggy", chance=9.0},
            {allele1="Indigo", allele2="Lavender", result="Fuchsia", chance=5.0},
            {allele1="Frugal", allele2="Nuclear", result="Yellorium", chance=5.0},
            {allele1="Infinity Catalyst", allele2="Cosmic Neutronium", result="Infinity", chance=0.10000000149012},
            {allele1="Forest", allele2="Diligent", result="Growing", chance=10.0},
            {allele1="Skulking", allele2="Windy", result="Batty", chance=9.0},
            {allele1="Fire", allele2="Air", result="Water", chance=15.0},
            {allele1="Tin", allele2="Copper", result="Iron", chance=13.0},
            {allele1="Platinum", allele2="Phantasmal", result="Enderium", chance=3.0},
            {allele1="Meadows", allele2="Wintry", result="Common", chance=15.0},
            {allele1="Attuned", allele2="Tropical", result="Common", chance=15.0},
            {allele1="Demonic", allele2="Vindictive", result="Vengeful", chance=8.0},
            {allele1="Gray", allele2="White", result="Light Gray", chance=10.0},
            {allele1="Industrious", allele2="Diligent", result="Clay", chance=10.0},
            {allele1="Chaos", allele2="Fire", result="Nethershard", chance=15.0},
            {allele1="Secluded", allele2="Ender", result="Abnormal", chance=5.0},
            {allele1="Peat", allele2="Silicon", result="Mica", chance=15.0},
            {allele1="Tropical", allele2="Valiant", result="Natural", chance=5.0},
            {allele1="D-O-B", allele2="Cosmic Neutronium", result="Infinity Catalyst", chance=0.30000001192093},
            {allele1="Farmerly", allele2="Meadows", result="Fermented", chance=10.0},
            {allele1="Mystical", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Charmed", allele2="Enchanted", result="Supernatural", chance=8.0},
            {allele1="Mars", allele2="Moon", result="Phobos", chance=20.0},
            {allele1="Coal", allele2="Clay", result="Ash", chance=10.0},
            {allele1="Supernatural", allele2="Ethereal", result="Firey", chance=14.0},
            {allele1="Diamond", allele2="Chrome", result="Platinum", chance=5.0},
            {allele1="Uranus", allele2="Iridium", result="Oberon", chance=10.0},
            {allele1="TCeti", allele2="Aqua", result="TCetiE", chance=2.5},
            {allele1="Marshy", allele2="Barren", result="Decomposing", chance=15.0},
            {allele1="Rural", allele2="Cuprum", result="Apatine", chance=12.0},
            {allele1="Iron", allele2="Coal", result="Steel", chance=10.0},
            {allele1="Vis", allele2="Rejuvenating", result="Empowering", chance=6.0},
            {allele1="Coal", allele2="Stickyresin", result="Oil", chance=4.0},
            {allele1="Majestic", allele2="Corroded", result="Glittering", chance=2.0},
            {allele1="Attuned", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Modest", allele2="Eldritch", result="Skulking", chance=12.0},
            {allele1="Austere", allele2="Excited", result="Celebratory", chance=5.0},
            {allele1="Unusual", allele2="Eldritch", result="Mutable", chance=12.0},
            {allele1="Tropical", allele2="Malicious", result="Infectious", chance=8.0},
            {allele1="Naquadria", allele2="Americium", result="Neutronium", chance=1.0},
            {allele1="Skystone", allele2="Ferrous", result="Silicon", chance=17.0},
            {allele1="Unstable", allele2="Leaden", result="Nuclear", chance=5.0},
            {allele1="Secluded", allele2="Ancient", result="Primeval", chance=8.0},
            {allele1="Demonic", allele2="Imperial", result="Lapis", chance=10.0},
            {allele1="Red Alloy", allele2="Ender", result="Pulsating Iron", chance=9.0},
            {allele1="Neutronium", allele2="BarnardaF", result="Cosmic Neutronium", chance=0.69999998807907},
            {allele1="Ocean", allele2="Primeval", result="Oily", chance=8.0},
            {allele1="Enceladus", allele2="Iridium", result="Trinium", chance=4.0},
            {allele1="Unusual", allele2="Modest", result="Common", chance=15.0},
            {allele1="Malicious", allele2="Infectious", result="Virulent", chance=8.0},
            {allele1="Forest", allele2="Frugal", result="Arid", chance=10.0},
            {allele1="Common", allele2="Skulking", result="Poultry", chance=12.0},
            {allele1="Imperial", allele2="Modest", result="Argentum", chance=8.0},
            {allele1="Common", allele2="Cultivated", result="Noble", chance=10.0},
            {allele1="Monastic", allele2="Austere", result="Secluded", chance=12.0},
            {allele1="Coal", allele2="Uranium", result="Thorium", chance=3.0},
            {allele1="Supernatural", allele2="Ethereal", result="Watery", chance=14.0},
            {allele1="Miry", allele2="Primeval", result="Resinous", chance=8.0},
            {allele1="Clay", allele2="Aluminium", result="Salt", chance=5.0},
            {allele1="Forest", allele2="Diligent", result="Blue", chance=10.0},
            {allele1="Vengeful", allele2="Vindictive", result="Avenging", chance=4.0},
            {allele1="Ignis", allele2="Edenic", result="Thaumium Dust", chance=10.0},
            {allele1="Enceladus", allele2="Emerald", result="Mysterious Crystal", chance=3.0},
            {allele1="Wintry", allele2="Forest", result="Merry", chance=10.0},
            {allele1="Avenging", allele2="Platinum", result="Uranium", chance=3.0},
            {allele1="Steel", allele2="Gold", result="Force", chance=10.0},
            {allele1="Sorcerous", allele2="Common", result="Cultivated", chance=12.0},
            {allele1="Imperial", allele2="Prehistoric", result="Relic", chance=8.0},
            {allele1="Ghastly", allele2="Hateful", result="Smouldering", chance=7.0},
            {allele1="Industrious", allele2="Robust", result="Resilient", chance=6.0},
            {allele1="Jupiter", allele2="Iron", result="Europa", chance=15.0},
            {allele1="Unusual", allele2="Wintry", result="Common", chance=15.0},
            {allele1="MakeMake", allele2="Naquadah", result="Vega", chance=2.0},
            {allele1="Modest", allele2="Lapis", result="Ruby", chance=5.0},
            {allele1="Marshy", allele2="Cultivated", result="Derpious", chance=10.0},
            {allele1="Meadows", allele2="Rocky", result="Common", chance=15.0},
            {allele1="Marshy", allele2="Clay", result="Slimeball", chance=7.0},
            {allele1="Meadows", allele2="Marshy", result="Common", chance=15.0},
            {allele1="Common", allele2="Tropical", result="Cultivated", chance=12.0},
            {allele1="Wintry", allele2="Embittered", result="Common", chance=15.0},
            {allele1="Meadows", allele2="Modest", result="Common", chance=15.0},
            {allele1="Venus", allele2="Osmium", result="Quantium", chance=6.0},
            {allele1="Neptune", allele2="Copper", result="Proteus", chance=7.0},
            {allele1="Demonic", allele2="Furious", result="Volcanic", chance=20.0},
            {allele1="Slimeball", allele2="Peat", result="Stickyresin", chance=15.0},
            {allele1="Lead", allele2="Silver", result="Cryolite", chance=9.0},
            {allele1="Diligent", allele2="Cultivated", result="Unweary", chance=8.0},
            {allele1="Common", allele2="Cultivated", result="Diligent", chance=10.0},
            {allele1="Embittered", allele2="Water", result="Common", chance=15.0},
            {allele1="Gold", allele2="Haume", result="Infused Gold", chance=5.0},
            {allele1="Mars", allele2="Space", result="Deimos", chance=20.0},
            {allele1="Valiant", allele2="Diligent", result="Sweetened", chance=15.0},
            {allele1="Unstable", allele2="Rusty", result="Nuclear", chance=5.0},
            {allele1="Barnarda", allele2="Unstable", result="BarnardaE", chance=1.5},
            {allele1="Frugal", allele2="Primeval", result="Oily", chance=8.0},
            {allele1="Forest", allele2="Barren", result="Gnawing", chance=15.0},
            {allele1="Modest", allele2="Resilient", result="Corroded", chance=5.0},
            {allele1="Tipsy", allele2="Exotic", result="Scummy", chance=10.0},
            {allele1="Sorcerous", allele2="Water", result="Common", chance=15.0},
            {allele1="Ordered", allele2="Chaotic", result="Essentia", chance=8.0},
            {allele1="Hermitic", allele2="Abnormal", result="Spatial", chance=5.0},
            {allele1="Forest", allele2="Desolate", result="Skeletal", chance=15.0},
            {allele1="Ethereal", allele2="Supernatural", result="Chaotic", chance=8.0},
            {allele1="Farmerly", allele2="Meadows", result="Farmed", chance=10.0},
            {allele1="Neptune", allele2="Gold", result="Triton", chance=7.0},
            {allele1="Ash", allele2="Coal", result="Apatite", chance=10.0},
            {allele1="Majestic", allele2="Rusty", result="Glittering", chance=2.0},
            {allele1="Cultivated", allele2="Eldritch", result="Esoteric", chance=10.0},
            {allele1="Forest", allele2="Resilient", result="Rusty", chance=5.0},
            {allele1="Ethereal", allele2="Aware", result="Spirit", chance=8.0},
            {allele1="Steel", allele2="Demonic", result="Electrical Steel", chance=9.0},
            {allele1="White", allele2="Blue", result="Light Blue", chance=10.0},
            {allele1="Primeval", allele2="Ancient", result="Prehistoric", chance=8.0},
            {allele1="Ethereal", allele2="Attuned", result="Aware", chance=10.0},
            {allele1="Redstone", allele2="Aluminium", result="Titanium", chance=5.0},
            {allele1="Common", allele2="Marshy", result="Cultivated", chance=12.0},
            {allele1="Mystical", allele2="Cultivated", result="Eldritch", chance=12.0},
            {allele1="Attuned", allele2="Common", result="Cultivated", chance=12.0},
            {allele1="Enderium", allele2="Stardust", result="Endermanhead", chance=4.0},
            {allele1="Glowstone", allele2="Gold", result="Sunnarium", chance=5.0},
            {allele1="Redstone", allele2="Gold", result="Electrotine", chance=5.0},
            {allele1="Mystical", allele2="Modest", result="Common", chance=15.0},
            {allele1="Meadows", allele2="Forest", result="Leporine", chance=10.0},
            {allele1="Ender", allele2="Relic", result="Jaded", chance=2.0},
            {allele1="Common", allele2="Meadows", result="Cultivated", chance=12.0},
            {allele1="Wintry", allele2="Meadows", result="Tipsy", chance=10.0},
            {allele1="Infinity Catalyst", allele2="Naquadria", result="Jaegermeister", chance=5.0},
            {allele1="Meadows", allele2="Resilient", result="Rusty", chance=5.0},
            {allele1="Meadows", allele2="Water", result="Common", chance=15.0},
            {allele1="Nameless", allele2="Abandoned", result="Forlorn", chance=6.0},
            {allele1="Mystical", allele2="Meadows", result="Common", chance=15.0},
            {allele1="Sorcerous", allele2="Modest", result="Common", chance=15.0},
            {allele1="Iron", allele2="Copper", result="Nickel", chance=13.0},
            {allele1="Nethershard", allele2="End Dust", result="Endshard", chance=15.0},
            {allele1="Attuned", allele2="Forest", result="Common", chance=15.0},
            {allele1="Redstone", allele2="Gold", result="Glowstone", chance=10.0},
            {allele1="Diamond", allele2="Iron", result="Unstable", chance=3.0},
            {allele1="Stannum", allele2="Common", result="Plumbum", chance=10.0},
            {allele1="Modest", allele2="Diligent", result="Yellow", chance=10.0},
            {allele1="Marshy", allele2="Resilient", result="Tarnished", chance=5.0},
            {allele1="Maroon", allele2="Saffron", result="Amber", chance=5.0},
            {allele1="Nitrogen", allele2="Hydrogen", result="Fluorine", chance=15.0},
            {allele1="Distilled", allele2="Fossilised", result="Tarry", chance=8.0},
            {allele1="Copper", allele2="Redstone", result="Red Alloy", chance=10.0},
            {allele1="Nickel", allele2="Zinc", result="Aluminium", chance=9.0},
            {allele1="Timely", allele2="Lordly", result="Doctoral", chance=7.0},
            {allele1="Industrious", allele2="Oily", result="Distilled", chance=8.0},
            {allele1="Thaumium Dust", allele2="Thaumic Shards", result="Salis Mundus", chance=8.0},
            {allele1="Dragon Essence", allele2="Stardust", result="Rune", chance=2.0},
            {allele1="Common", allele2="Water", result="Cultivated", chance=12.0},
            {allele1="Essentia", allele2="Thauminite", result="Drake", chance=5.0},
            {allele1="Common", allele2="Diligent", result="Red", chance=10.0},
            {allele1="Noble", allele2="Diligent", result="Ancient", chance=10.0},
            {allele1="Infinity Catalyst", allele2="Mysterious Crystal", result="Unknownwater", chance=5.0},
            {allele1="Common", allele2="Forest", result="Cultivated", chance=12.0},
            {allele1="Barnarda", allele2="Neutronium", result="BarnardaF", chance=1.5},
            {allele1="Order", allele2="Fire", result="Chaos", chance=15.0},
            {allele1="Modest", allele2="Desolate", result="Creepy", chance=15.0}
        }
    }

        ---@return ForestryMutation[]
        function Res.BeeGraphActual.GetRawMutationInfo()
            return Res.BeeGraphActual.RawMutationInfo
        end

        ---@return SpeciesGraph
        function Res.BeeGraphActual.GetGraph()
            local graph = {}
            for _, mut in ipairs(Res.BeeGraphActual.GetRawMutationInfo()) do
                GraphParse.AddMutationToGraph(graph, mut.allele1, mut.allele2, mut.result, mut.chance / 100.0)
            end

            return graph
        end

return Res
