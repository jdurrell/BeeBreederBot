Luaunit = require("Test.luaunit")
require("BeeServer.GraphParse")

-- Helper function to verify equivalence of two SpeciesGraphs. Since Luaunit's `assertItemsEquals()`
-- is not fully recursive, this is needed to properly compare the unordered lists deeper in the graph.
---@param graph1 SpeciesGraph
---@param graph2 SpeciesGraph
function AssertGraphsEquivalent(graph1, graph2)
    -- Both graphs should have the same species.
    for species, _ in pairs(graph1) do
        Luaunit.assertEvalToTrue(graph2[species] ~= nil)
    end
    for species, _ in pairs(graph2) do
        Luaunit.assertEvalToTrue(graph1[species] ~= nil)
    end

    for species, g1Node in pairs(graph1) do
        local g2Node = graph2[species]
        Luaunit.assertEquals(g1Node.speciesName, g2Node.speciesName)
        Luaunit.assertEvalToTrue(g1Node.parentMutations ~= nil)
        Luaunit.assertEvalToTrue(g1Node.childMutations ~= nil)
        Luaunit.assertEvalToTrue(g2Node.parentMutations ~= nil)
        Luaunit.assertEvalToTrue(g2Node.childMutations ~= nil)

        -- Assert parent mutations are equal by casting each set of parents to a unique string key
        -- mapped to mutation chance, then directly comparing those output tables.
        local g1Parents = {}
        for i, parents in ipairs(g1Node.parentMutations) do
            Luaunit.assertEvalToTrue(g2Node.parentMutations[i] ~= nil)
            local key
            if parents.parents[1] < parents.parents[2] then
                key = parents.parents[1] .. "-" .. parents.parents[2]
            else
                key = parents.parents[2] .. "-" .. parents.parents[1]
            end

            -- Not an equivalence check, but each node's parent mutation should only have
            -- each unique combination of parents appear once.
            Luaunit.assertEvalToTrue(g1Parents[key] == nil)
            g1Parents[key] = parents.chance
        end
        local g2Parents = {}
        for i, parents in ipairs(g2Node.parentMutations) do
            Luaunit.assertEvalToTrue(g1Node.parentMutations[i] ~= nil)
            local key
            if parents.parents[1] < parents.parents[2] then
                key = parents.parents[1] .. "-" .. parents.parents[2]
            else
                key = parents.parents[2] .. "-" .. parents.parents[1]
            end
            -- Not an equivalence check, but each node's parent mutation should only have
            -- each unique combination of parents appear once.
            Luaunit.assertEvalToTrue(g2Parents[key] == nil)
            g2Parents[key] = parents.chance
        end
        Luaunit.assertEquals(g1Parents, g2Parents)

        -- Assert child mutations are equal by first asserting that all children are in both nodes.
        -- Then, for each child, cast the child array to a mapping of otherParents to mutation chances,
        -- and compare the output arrays.
        local g1Children = {}
        for child, g1ChildMuts in pairs(g1Node.childMutations) do
            Luaunit.assertEvalToTrue(g2Node.childMutations[child] ~= nil)
            g1Children[child] = {}
            for _, parentAndChance in ipairs(g1ChildMuts) do
                -- Not an equivalence check, but this *should* be unique.
                Luaunit.assertEvalToTrue(g1Children[child][parentAndChance.parent] == nil)
                g1Children[child][parentAndChance.parent] = parentAndChance.chance
            end
        end
        local g2Children = {}
        for child, g2ChildMuts in pairs(g2Node.childMutations) do
            Luaunit.assertEvalToTrue(g1Node.childMutations[child] ~= nil)
            g2Children[child] = {}
            for _, parentAndChance in ipairs(g2ChildMuts) do
                -- Not an equivalence check, but this *should* be unique.
                Luaunit.assertEvalToTrue(g2Children[child][parentAndChance.parent] == nil)
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
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AssertGraphsEquivalent(graph, expected)
    end

    function TestAddMutationAddMoreParents()
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
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AssertGraphsEquivalent(graph, expected)

        -- Now try it again, but in a different order.
        graph = {}
        AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        AssertGraphsEquivalent(graph, expected)
    end

    function TestAddMutationTestMultiStepLine()
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
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        AssertGraphsEquivalent(graph, expected)

        -- Now try it again in some different orders.
        graph = {}
        AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)        
        AssertGraphsEquivalent(graph, expected)


        graph = {}
        AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AssertGraphsEquivalent(graph, expected)

        graph = {}
        AddMutationToGraph(graph, "Forest", "Tropical", "Common", 0.35)
        AddMutationToGraph(graph, "Marshy", "Tropical", "Common", 0.25)
        AddMutationToGraph(graph, "Forest", "Meadows", "Common", 0.15)
        AddMutationToGraph(graph, "Common", "Meadows", "Cultivated", 0.2)
        AddMutationToGraph(graph, "Forest", "Common", "Cultivated", 0.1)
        AssertGraphsEquivalent(graph, expected)
    end