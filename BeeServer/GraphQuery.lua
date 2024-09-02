-- This program handles querying the tree for the bee breeding path.
-- TODO: Consider using numeric IDs instead of string names for indexing to reduce memory usage.

---@class BFSQueue
---@field queue string[]                      Queue of species for the BFS search.
---@field seen table<string, integer>
---@field pathlookup table<string, string[]>  Table to lookup the path later.
---@function 
local BFSQueue = {queue={}, seen={}, pathlookup={}}

---@return BFSQueue
function BFSQueue:Create()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    self.queue = {}
    self.seen = {}
    self.pathlookup = {}
    return obj
end

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

---@return string
function BFSQueue:Pop()
    return table.remove(self.queue)
end

---@param graph SpeciesGraph
---@param leafSpecies string[]
---@param target string
---@return string[] | nil
function QueryBreedingPath(graph, leafSpecies, target)
    -- Start from the leaves (i.e. species already found) and build up the path from there.
    local bfsQueueSearch = BFSQueue:Create()
    for _, spec in pairs(leafSpecies) do
        bfsQueueSearch:Push(spec, 0, {nil, nil})  -- nil marks that this is a leaf node for re-traversal later.
    end

    if #(bfsQueueSearch.queue) == 0 then
        print("Error: Failed to start the queue search because no leaf nodes were provided.")
        return nil
    end

    local found = false
    local count = 0
    while (#(bfsQueueSearch.queue) > 0) and (not found) do
        count = count + 1
        local qNode = bfsQueueSearch:Pop()
        local bNode = graph[qNode]
        for result, otherParents in pairs(bNode.childMutations) do
            if bfsQueueSearch.seen[result] == nil then
                local oCount = 999999  -- Large number to be greater than any count.
                local minParent = nil

                -- Get earliest parent that has already been found *and* can create this mutation.
                for i,otherParent in ipairs(otherParents) do
                    if (bfsQueueSearch.seen[otherParent] ~= nil) and (bfsQueueSearch.seen[otherParent] < oCount) then
                        oCount = bfsQueueSearch.seen[otherParent]
                        minParent = otherParent
                    end
                end

                -- If we another parent was already found, then push this mutation onto the queue.
                if minParent ~= nil then
                    bfsQueueSearch:Push(result, count {qNode, minParent})

                    -- If we found the path to the target, then no point in continuing the search.
                    found = (result == target)
                    if found then
                        break
                    end
                end
            end
        end
    end

    -- Retrace the path to return it out.
    -- In theory, we could have built the path as we did the search, but we are memory-limited,
    -- so we trade off some time to limit the information stored and rebuild the path later.
    local path = {}
    local name = bfsQueueSearch.queue[#(bfsQueueSearch.queue)]  -- Target node is at the back since we just added it.
    local bfsQueueRetrace = BFSQueue:Create()
    bfsQueueRetrace:Push(name, 0, nil)
    while #(bfsQueueRetrace.queue) > 0 do
        name = bfsQueueRetrace:Pop()
        path.insert(name)
        for _,parent in ipairs(bfsQueueSearch.pathlookup[name]) do
            if (parent ~= nil) and (bfsQueueRetrace.seen[parent] ~= nil) then
                bfsQueueRetrace:Push(parent, 0, nil)
            end
        end
    end

    -- Reverse the path to give the forward direction since we built it by retracing.
    for i=1,(#path)/2 do  -- TODO: verify that this does integer division and can't return some float.
        local temp = path[i]
        path[i] = path[#path - i]
        path[#path - i] = temp
    end

    return path
end