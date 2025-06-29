-- This is a module that simulates the 'Component' module from OpenComputers.
---@class Component
---@field beekeeper any
---@field inventory_controller any
---@field modem Modem
---@field tile_for_apiculture_0_name ApicultureTile
---@field tile_for_apiculture_2_name ApicultureTile
local M = {}

M.modem = require("Test.SimulatorModules.Component.Modem")
M.tile_for_apiculture_0_name = require("Test.SimulatorModules.Component.ApicultureTiles")

---@param component string
---@return boolean
function M.isAvailable(component)
    return (component == "modem" or component == "tile_for_apiculture_0_name")
end

---@return table<string, string>
function M.list()
    return {
        ["1"] = "modem",
        ["2"] = "tile_for_apiculture_0_name"
    }
end

return M
