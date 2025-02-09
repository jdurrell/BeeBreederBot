-- This file contains data for running tests.
-- NOTE: The data here is not necessarily reflective of actual genetics in any version of Forestry.

GraphParse = require("BeeServer.GraphParse")

local Res = {
    MathMargin = 0.001,
    MundaneBees = {"Forest", "Marshy", "Meadows", "Modest", "Tropical", "Wintry"}
}
    -- A graph made up of only mundane bees that breed into Common with 15% chance each.
    Res.BeeGraphMundaneIntoCommon = {
        MutationChanceIndividual = 0.15,
        ExpectedBreedInfo = {
            Forest={},
            Marshy={},
            Meadows={},
            Modest={},
            Tropical={},
            Wintry={},
            Common={
                Forest={Marshy=0.15, Meadows=0.15, Modest=0.15, Tropical=0.15, Wintry=0.15},
                Marshy={Forest=0.15, Meadows=0.15, Modest=0.15, Tropical=0.15, Wintry=0.15},
                Meadows={Forest=0.15, Marshy=0.15, Modest=0.15, Tropical=0.15, Wintry=0.15},
                Modest={Forest=0.15, Marshy=0.15, Meadows=0.15, Tropical=0.15, Wintry=0.15},
                Tropical={Forest=0.15, Marshy=0.15, Meadows=0.15, Modest=0.15, Wintry=0.15},
                Wintry={Forest=0.15, Marshy=0.15, Meadows=0.15, Modest=0.15, Tropical=0.15}
            }
        }
    }
        ---@return SpeciesGraph
        function Res.BeeGraphMundaneIntoCommon.GetGraph()
            local graph = {}

            for i=1, #Res.MundaneBees do
                for j=(i+1), #Res.MundaneBees do
                    GraphParse.AddMutationToGraph(graph, Res.MundaneBees[i], Res.MundaneBees[j], "Common", Res.BeeGraphMundaneIntoCommon.MutationChanceIndividual)
                end
            end

            return graph
        end

    -- A graph made up of only mundane bees that breed into Common, then can breed with Common to create Cultivated.
    Res.BeeGraphMundaneIntoCommonIntoCultivated = {
        ExpectedBreedInfo = {
            Forest={},
            Marshy={},
            Meadows={},
            Modest={},
            Tropical={},
            Wintry={},
            Common={
                Forest={Marshy=0.15, Meadows=0.15, Modest=0.15, Tropical=0.15, Wintry=0.15},
                Marshy={Forest=0.15, Meadows=0.15, Modest=0.15, Tropical=0.15, Wintry=0.15},
                Meadows={Forest=0.15, Marshy=0.15, Modest=0.15, Tropical=0.15, Wintry=0.15},
                Modest={Forest=0.15, Marshy=0.15, Meadows=0.15, Tropical=0.15, Wintry=0.15},
                Tropical={Forest=0.15, Marshy=0.15, Meadows=0.15, Modest=0.15, Wintry=0.15},
                Wintry={Forest=0.15, Marshy=0.15, Meadows=0.15, Modest=0.15, Tropical=0.15}
            },
            Cultivated={
                Common={Forest=0.12, Marshy=0.12, Meadows=0.12, Modest=0.12, Tropical=0.12, Wintry=0.12},
                Forest={Common=0.12},
                Marshy={Common=0.12},
                Meadows={Common=0.12},
                Modest={Common=0.12},
                Tropical={Common=0.12},
                Wintry={Common=0.12}
            }
        }
    }
        ---@return SpeciesGraph
        function Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
            local graph = Res.BeeGraphMundaneIntoCommon.GetGraph()

            for i=1, #Res.MundaneBees do
                GraphParse.AddMutationToGraph(graph, Res.MundaneBees[i], "Common", "Cultivated", 0.12)
            end

            return graph
        end

    Res.BeeGraphSimpleDuplicateMutations = {
        ExpectedBreedInfo = {
            Root1={},
            Root2={},
            Result1={Root1={Root2=0.45}, Root2={Root1=0.45}},
            Result2={Root1={Root2=0.15}, Root2={Root1=0.15}}
        }
    }
        ---@return SpeciesGraph    
        function Res.BeeGraphSimpleDuplicateMutations.GetGraph()
            local graph = {}

            GraphParse.AddMutationToGraph(graph, "Root1", "Root2", "Result1", 0.5)
            GraphParse.AddMutationToGraph(graph, "Root1", "Root2", "Result2", 0.2)

            return graph
        end

return Res
