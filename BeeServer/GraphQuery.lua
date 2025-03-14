-- This program handles querying the tree for the bee breeding path.

---@class BFSQueue
---@field count integer
---@field pathlookup table<string, string[]>  Table to lookup the path later.
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
function BFSQueue:Push(name, parents)
    table.insert(self.queue, name)
    if self.seen[name] == nil then
        self.seen[name] = self.count
        self.count = self.count + 1
    end

    self.pathlookup[name] = parents
end

-- Pop the next item off the BFS queue.
---@return string
function BFSQueue:Pop()
    return table.remove(self.queue, 1)
end

local M = {}

---@param graph SpeciesGraph
---@param leafSpecies string[]
---@param target string
---@return BreedPathNode[] | nil
function M.QueryBreedingPath(graph, leafSpecies, target)
    -- Start from the leaves (i.e. species already found) and build up the path from there.
    local bfsQueueSearch = BFSQueue:Create()
    for _, spec in ipairs(leafSpecies) do
        -- If we already have the species, then it should be the only thing in the breed path.
        if spec == target then
            return {{target = target, parent1 = nil, parent2 = nil}}
        end

        bfsQueueSearch:Push(spec, {nil, nil})  -- nil marks that this is a leaf node for re-traversal later.
    end

    if #(bfsQueueSearch.queue) == 0 then
        -- We need to be able to start from something.
        Print("Error: Failed to start the queue search because no leaf nodes were provided.")
        return nil
    end

    local found = false
    while #(bfsQueueSearch.queue) > 0 do
        local qNode = bfsQueueSearch:Pop()
        if qNode == nil then
            Print("Failed to find path to species " .. target .. " in graph from given leaf nodes.")
            return nil
        elseif qNode == target then
            found = true
            break
        end

        local bNode = graph[qNode]
        for result, otherParents in pairs(bNode.childMutations) do
            if bfsQueueSearch.seen[result] == nil then
                local oCount = 999999  -- Large number to be greater than any count.
                local minParent = nil

                -- Get earliest parent that has already been found *and* can create this mutation.
                for _, otherParent in ipairs(otherParents) do
                    if (bfsQueueSearch.seen[otherParent.parent] ~= nil) and (bfsQueueSearch.seen[otherParent.parent] < oCount) then
                        oCount = bfsQueueSearch.seen[otherParent.parent]
                        minParent = otherParent.parent
                    end
                end

                -- If another parent was already found, then push this mutation onto the queue.
                if minParent ~= nil then
                    bfsQueueSearch:Push(result, {qNode, minParent})
                end
            end
        end
    end

    if not found then
        Print("Failed to find the target in the graph.")
        return nil
    end

    ---@type BreedPathNode[]
    local path = {}

    -- Retrace the path to return it out.
    -- In theory, we could have built the path as we did the search, but we are memory-limited,
    -- so we trade off some time to limit the information stored and rebuild the path later.
    local bfsQueueRetrace = BFSQueue:Create()
    bfsQueueRetrace:Push(target, nil)
    while #(bfsQueueRetrace.queue) > 0 do
        local name = bfsQueueRetrace:Pop()
        if bfsQueueSearch.pathlookup[name][1] ~= nil or bfsQueueSearch.pathlookup[name][2] then
            table.insert(path, {
                target = name,
                parent1 = bfsQueueSearch.pathlookup[name][1],
                parent2 = bfsQueueSearch.pathlookup[name][2]
            })
        end

        for _, parent in pairs(bfsQueueSearch.pathlookup[name]) do
            if (parent ~= nil) and (bfsQueueRetrace.seen[parent] == nil) then
                bfsQueueRetrace:Push(parent, nil)
            end
        end
    end

    table.sort(path, function(a, b)
        return (bfsQueueSearch.seen[a.target] < bfsQueueSearch.seen[b.target])
    end)

    return path
end

return M