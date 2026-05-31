-- This program handles querying the tree for the bee breeding path.

local MutationConditionSet = require("Shared.MutationConditionSet")

---@class BFSQueue
---@field count integer
---@field pathlookup table<string, {parents: string[] | nil, conditions: MutationConditionSet}>  Table to lookup the path later.
---@field queue string[]                      Queue of species for the BFS search.
---@field seen table<string, integer>
local BFSQueue = {}

-- Create a new BFS queue.
--- @return BFSQueue
function BFSQueue:Create()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.count = 0
    obj.pathlookup = {}
    obj.queue = {}
    obj.seen = {}
    return obj
end

-- Push an item onto the BFS queue.
---@param name string
---@param parents string[] | nil
---@param conditions MutationConditionSet
function BFSQueue:Push(name, parents, conditions)
    table.insert(self.queue, name)
    if self.seen[name] == nil then
        self.seen[name] = self.count
        self.count = self.count + 1
    end

    self.pathlookup[name] = {}
    self.pathlookup[name].parents = parents
    self.pathlookup[name].conditions = conditions
end

-- Pop the next item off the BFS queue.
---@return string
function BFSQueue:Pop()
    return table.remove(self.queue, 1)
end

local M = {}

---@param graph SpeciesGraph
---@param leafSpecies Set<string>
---@param validTargets Set<string>
---@return BreedPathNode[] | nil
function M.QueryBestBreedingPath(graph, leafSpecies, validTargets)
    -- Start from the leaves (i.e. species already found) and build up the path from there.
    local bfsQueueSearch = BFSQueue:Create()
    for leaf, _ in pairs(leafSpecies) do
        if validTargets[leaf] == nil then
            -- nil marks that this is a leaf node for re-traversal later.
            bfsQueueSearch:Push(leaf, {nil, nil}, {})
        end
    end

    if #(bfsQueueSearch.queue) == 0 then
        -- We need to be able to start from something.
        Print("Error: Failed to start the queue search because no leaf nodes were provided.")
        return nil
    end

    local found = ""
    while #(bfsQueueSearch.queue) > 0 do
        local qNode = bfsQueueSearch:Pop()
        if qNode == nil then
            Print("Error: Failed to find path to any target species in graph from given leaf nodes.")
            return nil
        elseif validTargets[qNode] then
            found = qNode
            break
        end

        local bNode = graph[qNode]
        for result, otherParents in pairs(bNode.childMutations) do
            if bfsQueueSearch.seen[result] == nil then
                local oCount = 999999  -- Large number to be greater than any count.
                local minNode = nil

                -- Get earliest parent that has already been found *and* can create this mutation.
                for _, otherParent in ipairs(otherParents) do
                    if (bfsQueueSearch.seen[otherParent.parent] ~= nil) and (bfsQueueSearch.seen[otherParent.parent] < oCount) then
                        oCount = bfsQueueSearch.seen[otherParent.parent]
                        minNode = otherParent
                    end
                end

                -- If another parent was already found, then push this mutation onto the queue.
                if minNode ~= nil then
                    bfsQueueSearch:Push(result, {qNode, minNode.parent}, minNode.conditions)
                end
            end
        end
    end

    if found == "" then
        Print("Error: Failed to find the target in the graph.")
        return nil
    end

    ---@type BreedPathNode[]
    local path = {}

    -- Retrace the path to return it out.
    local bfsQueueRetrace = BFSQueue:Create()
    bfsQueueRetrace:Push(found, nil, {})
    while #(bfsQueueRetrace.queue) > 0 do
        local name = bfsQueueRetrace:Pop()
        local node = bfsQueueSearch.pathlookup[name]
        if (node.parents[1] ~= nil) or (node.parents[2] ~= nil) then
            table.insert(path, {
                target=name,
                parent1=node.parents[1],
                parent2=node.parents[2],
                conditions=node.conditions
            })
        end

        -- We can skip tracing the path if this is a leaf node, but not if this is the target
        -- (because we might need to rebreed it from other existing species to get a new trait).
        if (leafSpecies[name] == nil) or (name == found) then
            for _, parent in pairs(node.parents) do
                if (parent ~= nil) and (bfsQueueRetrace.seen[parent] == nil) then
                    bfsQueueRetrace:Push(parent, nil, node.conditions)
                end
            end
        end
    end

    table.sort(path, function(a, b)
        return (bfsQueueSearch.seen[a.target] < bfsQueueSearch.seen[b.target])
    end)

    return path
end

return M