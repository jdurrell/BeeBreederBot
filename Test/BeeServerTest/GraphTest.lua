local Luaunit = require("Test.luaunit")

local Res = require("Test.Resources.TestData")
local Util = require("Test.Utilities.CommonUtilities")

require("Shared.Shared")
local GraphParse = require("BeeServer.GraphParse")
local GraphQuery = require("BeeServer.GraphQuery")

-- Helper function to verify equivalence of two SpeciesGraphs. Since Luaunit's `assertItemsEquals()`
-- is not fully recursive, this is needed to properly compare the unordered lists deeper in the graph.
---@param graph1 SpeciesGraph
---@param graph2 SpeciesGraph
function AssertGraphsEquivalent(graph1, graph2)
    -- Both graphs should have the same species.
    for species, _ in pairs(graph1) do
        Luaunit.assertNotIsNil(graph2[species])
    end
    for species, _ in pairs(graph2) do
        Luaunit.assertNotIsNil(graph1[species])
    end

    for species, g1Node in pairs(graph1) do
        local g2Node = graph2[species]
        Luaunit.assertEquals(g1Node.speciesName, g2Node.speciesName)
        Luaunit.assertNotIsNil(g1Node.parentMutations)
        Luaunit.assertNotIsNil(g1Node.childMutations)
        Luaunit.assertNotIsNil(g2Node.parentMutations)
        Luaunit.assertNotIsNil(g2Node.childMutations)

        -- Assert parent mutations are equal by casting each set of parents to a unique string key
        -- mapped to mutation chance, then directly comparing those output tables.
        local g1Parents = {}
        for i, parents in ipairs(g1Node.parentMutations) do
            Luaunit.assertNotIsNil(g2Node.parentMutations[i])
            local key
            if parents.parents[1] < parents.parents[2] then
                key = parents.parents[1] .. "-" .. parents.parents[2]
            else
                key = parents.parents[2] .. "-" .. parents.parents[1]
            end

            -- Not an equivalence check, but each node's parent mutation should only have
            -- each unique combination of parents appear once.
            Luaunit.assertIsNil(g1Parents[key])
            g1Parents[key] = parents.chance
        end
        local g2Parents = {}
        for i, parents in ipairs(g2Node.parentMutations) do
            Luaunit.assertNotIsNil(g1Node.parentMutations[i])
            local key
            if parents.parents[1] < parents.parents[2] then
                key = parents.parents[1] .. "-" .. parents.parents[2]
            else
                key = parents.parents[2] .. "-" .. parents.parents[1]
            end
            -- Not an equivalence check, but each node's parent mutation should only have
            -- each unique combination of parents appear once.
            Luaunit.assertIsNil(g2Parents[key])
            g2Parents[key] = parents.chance
        end
        Luaunit.assertEquals(g1Parents, g2Parents)

        -- Assert child mutations are equal by first asserting that all children are in both nodes.
        -- Then, for each child, cast the child array to a mapping of otherParents to mutation chances,
        -- and compare the output arrays.
        local g1Children = {}
        for child, g1ChildMuts in pairs(g1Node.childMutations) do
            Luaunit.assertNotIsNil(g2Node.childMutations[child])
            g1Children[child] = {}
            for _, parentAndChance in ipairs(g1ChildMuts) do
                -- Not an equivalence check, but this *should* be unique.
                Luaunit.assertIsNil(g1Children[child][parentAndChance.parent])
                g1Children[child][parentAndChance.parent] = parentAndChance.chance
            end
        end
        local g2Children = {}
        for child, g2ChildMuts in pairs(g2Node.childMutations) do
            Luaunit.assertNotIsNil(g1Node.childMutations[child])
            g2Children[child] = {}
            for _, parentAndChance in ipairs(g2ChildMuts) do
                -- Not an equivalence check, but this *should* be unique.
                Luaunit.assertIsNil(g2Children[child][parentAndChance.parent])
                g2Children[child][parentAndChance.parent] = parentAndChance.chance
            end
        end
        Luaunit.assertEquals(g1Children, g2Children)
    end
end

TestGraphParse = {}
    function TestGraphParse:TestAddMutationToEmptyGraph()
        local expected = {
            Forest={
                speciesName="Forest",
                parentMutations={},
                childMutations={Common={{parent="Meadows", chance=0.15}}}
            },
            Meadows={
                speciesName="Meadows",
                parentMutations={},
                childMutations={Common={{parent="Forest", chance=0.15}}}
            },
            Common={
                speciesName="Common",
                parentMutations={{parents={"Forest", "Meadows"}, chance=0.15}},
                childMutations={}
            }
        }
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AssertGraphsEquivalent(graph, expected)
    end

    function TestGraphParse:TestAddMutationAddMoreParents()
        local expected = {
            Forest={
                speciesName="Forest",
                parentMutations={},
                childMutations={Common={{parent="Meadows", chance=0.15}, {parent="Tropical", chance=0.35}}}
            },
            Meadows={
                speciesName="Meadows",
                parentMutations={},
                childMutations={Common={{parent="Forest", chance=0.15}}}
            },
            Marshy={
                speciesName="Marshy",
                parentMutations={},
                childMutations={Common={{parent="Tropical", chance=0.25}}}
            },
            Tropical={
                speciesName="Tropical",
                parentMutations={},
                childMutations={Common={{parent="Marshy", chance=0.25}, {parent="Forest", chance=0.35}}}
            },
            Common={
                speciesName="Common",
                parentMutations={
                    {parents={"Forest", "Meadows"}, chance=0.15},
                    {parents={"Marshy", "Tropical"}, chance=0.25},
                    {parents={"Forest", "Tropical"}, chance=0.35}
                },
                childMutations={}
            }
        }
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AssertGraphsEquivalent(graph, expected)

        -- Now try it again, but in a different order.
        graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        AssertGraphsEquivalent(graph, expected)
    end

    function TestGraphParse:TestAddMutationTestMultiStepLine()
        local expected = {
            Forest={
                speciesName="Forest",
                parentMutations={},
                childMutations={
                    Common={{parent="Meadows", chance=0.15}, {parent="Tropical", chance=0.35}},
                    Cultivated={{parent="Common", chance=0.1}}
                }
            },
            Meadows={
                speciesName="Meadows",
                parentMutations={},
                childMutations={
                    Common={{parent="Forest", chance=0.15}},
                    Cultivated={{parent="Common", chance=0.2}}
                }
            },
            Marshy={
                speciesName="Marshy",
                parentMutations={},
                childMutations={Common={{parent="Tropical", chance=0.25}}}
            },
            Tropical={
                speciesName="Tropical",
                parentMutations={},
                childMutations={Common={{parent="Marshy", chance=0.25}, {parent="Forest", chance=0.35}}}
            },
            Common={
                speciesName="Common",
                parentMutations={
                    {parents={"Forest", "Meadows"}, chance=0.15},
                    {parents={"Marshy", "Tropical"}, chance=0.25},
                    {parents={"Forest", "Tropical"}, chance=0.35}
                },
                childMutations={Cultivated={{parent="Forest", chance=0.1}, {parent="Meadows", chance=0.2}}}
            },
            Cultivated={
                speciesName="Cultivated",
                parentMutations={
                    {parents={"Forest", "Common"}, chance=0.1},
                    {parents={"Common", "Meadows"}, chance=0.2}
                },
                childMutations={}
            }
        }
        local graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        GraphParse.AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        GraphParse.AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        AssertGraphsEquivalent(graph, expected)

        -- Now try it again in some different orders.
        graph = {}
        GraphParse.AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        GraphParse.AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)        
        AssertGraphsEquivalent(graph, expected)


        graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        GraphParse.AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AssertGraphsEquivalent(graph, expected)

        graph = {}
        GraphParse.AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        GraphParse.AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        GraphParse.AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        GraphParse.AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        GraphParse.AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        AssertGraphsEquivalent(graph, expected)
    end

TestGraphQuery = {}
    function TestGraphQuery:TestLeafNode()
        local graph = Res.BeeGraphMundaneIntoCommon.GetGraph()
        for _, spec in ipairs(Res.MundaneBees) do
            local path = GraphQuery.QueryBreedingPath(graph, Res.MundaneBees, spec, false)
            Luaunit.assertEquals(path, {{target=spec, parent1=nil, parent2=nil}})
        end
    end

    function TestGraphQuery:TestNoExist()
        local graph = Res.BeeGraphMundaneIntoCommon.GetGraph()
        local path = GraphQuery.QueryBreedingPath(graph, Res.MundaneBees, "shouldntexist", false)
        Luaunit.assertIsNil(path)
    end

    function TestGraphQuery:TestBasic()
        local graph = Res.BeeGraphMundaneIntoCommon.GetGraph()
        local target = "Common"
        local path = GraphQuery.QueryBreedingPath(graph, Res.MundaneBees, target, false)
        Util.AssertPathIsValidInGraph(graph, Res.MundaneBees, path, target)
    end

    function TestGraphQuery:TestMultistep()
        local graph = Res.BeeGraphMundaneIntoCommonIntoCultivated.GetGraph()
        local target = "Cultivated"
        local path = GraphQuery.QueryBreedingPath(graph, Res.MundaneBees, target, false)
        Util.AssertPathIsValidInGraph(graph, Res.MundaneBees, path, target)
    end

    function TestGraphQuery:TestComplex()
        local graph = Res.BeeGraphActual.GetGraph()
        local target = "gregtech.bee.speciesIron"
        local leafNodes = {"forestry.speciesForest", "forestry.speciesMarshy", "forestry.speciesMeadows", "forestry.speciesModest", "forestry.speciesTropical", "forestry.speciesWintry"}
        local path = GraphQuery.QueryBreedingPath(graph, leafNodes, target, false)
        Luaunit.assertNotIsNil(path)
        Util.AssertPathIsValidInGraph(graph, leafNodes, path, target)
    end
