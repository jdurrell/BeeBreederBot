-- This program handles querying the tree for the bee breeding path.
-- TODO: Consider using numeric IDs instead of string names for indexing to reduce memory usage.

---@class BFSQueue
---@field queue string[]                      Queue of species for the BFS search.
---@field seen table<string, integer>
---@field pathlookup table<string, string[]>  Table to lookup the path later.
local BFSQueue = {
    queue={},
    seen={},
    pathlookup={}
}

-- Create a new BFS queue.
--- @return BFSQueue
function BFSQueue:Create()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.queue = {}
    obj.seen = {}
    obj.pathlookup = {}
    return obj
end

-- Push an item onto the BFS queue.
---@param name string
---@param count integer
---@param parents string[] | nil
function BFSQueue:Push(name, count, parents)
    table.insert(self.queue, name)
    if parents ~= nil then
        self.seen[name] = count
        self.pathlookup[name] = parents
    end
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
        bfsQueueSearch:Push(spec, 0, {nil, nil})  -- nil marks that this is a leaf node for re-traversal later.
    end

    if #(bfsQueueSearch.queue) == 0 then
        Print("Error: Failed to start the queue search because no leaf nodes were provided.")
        return nil
    end

    local found = false
    local count = 0
    while #(bfsQueueSearch.queue) > 0 do
        count = count + 1
        local qNode = bfsQueueSearch:Pop()
        local bNode = graph[qNode]
        if qNode == target then
            found = true
            break
        end

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
                    bfsQueueSearch:Push(result, count, {qNode, minParent})
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
    bfsQueueRetrace:Push(target, 0, nil)
    while #(bfsQueueRetrace.queue) > 0 do
        local name = bfsQueueRetrace:Pop()
        table.insert(path, {
            target=name,
            parent1=bfsQueueSearch.pathlookup[name][1],
            parent2=bfsQueueSearch.pathlookup[name][2]
        })

        for _, parent in pairs(bfsQueueSearch.pathlookup[name]) do
            if (parent ~= nil) and (bfsQueueRetrace.seen[parent] == nil) then
                bfsQueueRetrace:Push(parent, 0, nil)
            end
        end
    end

    -- Reverse the path to give the forward direction since we built it by retracing.
    for i=1, math.floor((#path) / 2) do
        local temp = path[i]
        path[i] = path[(#path) - (i - 1)]  -- off-by-one because Lua arrays are 1-indexed.
        path[(#path) - (i - 1)] = temp     -- off-by-one because Lua arrays are 1-indexed.
    end

    return path
end

return M