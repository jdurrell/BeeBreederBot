# BeeBreederBot
The BeeBreeerBot is a (work-in-progress) automated system that uses OpenComputers to breed Forestry bees. Given a target species, it breeds a full stack of drones for that species and converts some princesses to pure-breds of that species, which a user can then use in a production system however they please. It consists of three components: the BeeServer, the BeekeeperBot, and some piping system. 

## BeeServer
The BeeServer provides the front-facing user interface where the user selects a target species to breed, and it also manages the breeding tree and mutation information queried from an attached apiary.

## BeekeeperBot
The BeekeeperBot communicates with the BeeServer to determine the sequence of species to breed, then continually matches drones and princesses for the highest chance of mutating into the target species. It also manages storing away pure-bred drones so that it can re-use them in the future for other breeds.

## Piping System
The piping system is not directly handled by OpenComputers and instead consists of more standard automation methods to pull drones, princesses, and byproducts out of the apiaries, separate them, and send the bees through an analyzer so that the BeekeeperBot can properly determine how to use them.

## Usage
This system is still under development and does not have an official release date. Currently, Gregtech: New Horizons in 1.7.10 is the only modpack targeted for support, but it is possible that this system might end up working for other similar scenarios.

## Running Development Tests 
1. Install LuaUnit v3.4 from [https://github.com/bluebird75/luaunit](https://github.com/bluebird75/luaunit/tree/LUAUNIT_V3_4) to `${BeeBreederBot}/Test/`.
2. In a terminal from the root of the repository, run `lua Test/BeeBreederBotTest.lua`.