-- This is a module that simulates the 'Component' module from OpenComputers.
---@class Component
---@field beekeeper any
---@field inventory_controller any
---@field modem Modem
---@field tile_for_apiculture_0_name ApicultureTile
local M = {}

M.modem = require("Test.SimulatorModules.Component.Modem")
M.tile_for_apiculture_0_name = require("Test.SimulatorModules.Component.ApicultureTiles")

return M
