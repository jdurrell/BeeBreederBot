-- This program handles querying the tree for the bee breeding path.
-- TODO: Consider using numeric IDs instead of string names for indexing to reduce memory usage.

---@return BFSQueue
function BFSQueueCreate()
    local bfsQueue = {
        queue={},
        seen={},
        pathlookup={}
    }
    return bfsQueue
end

---@param queue BFSQueue
---@param name string
---@param count integer
---@param parents string[] | nil
function BFSQueuePush(queue, name, count, parents)
    table.insert(queue.queue, name)
    if parents ~= nil then
        queue.seen[name] = count
        queue.pathlookup[name] = parents
    end
end

---@param queue BFSQueue
---@return string
function BFSQueuePop(queue)
    return table.remove(queue.queue, 1)
end

---@param graph SpeciesGraph
---@param leafSpecies ChestArray
---@param target string
---@return BreedPathNode[] | nil
function QueryBreedingPath(graph, leafSpecies, target)
    -- Start from the leaves (i.e. species already found) and build up the path from there.
    local bfsQueueSearch = BFSQueueCreate()
    for spec, _ in pairs(leafSpecies) do
        BFSQueuePush(bfsQueueSearch, spec, 0, {nil, nil})  -- nil marks that this is a leaf node for re-traversal later.
    end

    if #(bfsQueueSearch.queue) == 0 then
        print("Error: Failed to start the queue search because no leaf nodes were provided.")
        return nil
    end

    local found = false
    local count = 0
    while (#(bfsQueueSearch.queue) > 0) and (not found) do
        count = count + 1
        local qNode = BFSQueuePop(bfsQueueSearch)
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

                -- If another parent was already found, then push this mutation onto the queue.
                if minParent ~= nil then
                    BFSQueuePush(bfsQueueSearch, result, count, {qNode, minParent})

                    -- If we found the path to the target, then no point in continuing the search.
                    found = (result == target)
                    if found then
                        break
                    end
                end
            end
        end
    end

    if not found then
        print("Failed to find the target in the graph.")
        return nil
    end

    ---@type BreedPathNode[]
    local path = {}

    -- Retrace the path to return it out.
    -- In theory, we could have built the path as we did the search, but we are memory-limited,
    -- so we trade off some time to limit the information stored and rebuild the path later.
    local name = bfsQueueSearch.queue[#(bfsQueueSearch.queue)]  -- Target node is at the back since we exited the above search immediately after adding it.
    local bfsQueueRetrace = BFSQueueCreate()
    BFSQueuePush(bfsQueueRetrace, name, 0, nil)
    while #(bfsQueueRetrace.queue) > 0 do
        name = BFSQueuePop(bfsQueueRetrace)
        table.insert(path, {
            target=name,
            parent1=bfsQueueSearch.pathlookup[name][1],
            parent2=bfsQueueSearch.pathlookup[name][2]
        })

        for _, parent in pairs(bfsQueueSearch.pathlookup[name]) do
            if (parent ~= nil) and (bfsQueueRetrace.seen[parent] == nil) then
                BFSQueuePush(bfsQueueRetrace, parent, 0, nil)
            end
        end
    end

    -- Reverse the path to give the forward direction since we built it by retracing.
    for i=1, math.floor((#path) / 2) do
        local temp = path[i]
        path[i] = path[#path - (i - 1)]  -- off-by-one because Lua arrays are 1-indexed.
        path[#path - (i - 1)] = temp     -- off-by-one because Lua arrays are 1-indexed.
    end

    return path
end