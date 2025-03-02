---@class RollingEnum
---@field enumTable table<any, integer>
---@field nextVal integer
local RollingEnum = {}

---@return RollingEnum
function RollingEnum:Create()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.enumTable = {}
    obj.nextVal = 0

    return obj
end

---@param enumVal any
---@return integer
function RollingEnum:Get(enumVal)
    local val = self.enumTable[enumVal]
    if val ~= nil then
        return val
    end

    self.enumTable[enumVal] = self.nextVal
    self.nextVal = self.nextVal + 1
    return self.nextVal - 1
end

return RollingEnum
