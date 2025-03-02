-- This is a generic queue module.

---@class Queue
---@field arr table<integer, any>
---@field leadingIdx integer
---@field trailingIdx integer
local M = {}

---@return Queue
function M:Create()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    self.leadingIdx = 1
    self.trailingIdx = 1
    self.arr = {}

    return obj
end

---@return boolean
function M:IsEmpty()
    return (self.leadingIdx == self.trailingIdx)
end

---@param element any
function M:Push(element)
    self.arr[self.leadingIdx] = element
    self.leadingIdx = self.leadingIdx + 1
end

---@return any | nil
function M:Pull()
    if self:IsEmpty() then
        return nil
    end

    local element = self.arr[self.trailingIdx]
    self.arr[self.trailingIdx] = nil  -- Allow the garbage collector to reclaim it eventually.
    self.trailingIdx = self.trailingIdx + 1
    return element
end

return M
