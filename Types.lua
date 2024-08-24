-- This file contains types for easy reference and external IntelliSense.
-- It isn't needed on the in-game devices since it provides no direct functionality.

---@class SpeciesNode
---@field speciesName string          The name of this species.
---@field parentMutations string[][]  All parent mutations that can result in this species.
---@field childMutations table<string, string[]>    Mapping of results to other parents that can yield that result.
local SpeciesNode = {}

---@alias SpeciesGraph table<string, SpeciesNode>

-- TODO: All of this information was sourced from a drone. I *think* princesses have the exact same structure, but this should be verified.
-- TODO: All of this information was sourced from a Forest bee. Other species could potentially have additional information.
---@class AnalyzedBeeStack
---@field damage number
---@field hasTag boolean
---@field individual AnalyzedBeeIndividual  The actual bee information.
---@field inputs {}  -- Empty table? It seems that there is nothing actually in here.
---@field isCraftable boolean
---@field label string  Translated name (appears as the "common name" of the item in-game).
---@field maxDamage number
---@field maxSize integer
---@field name string   Untranslated name (internal Minecraft name).
---@field outputs {} -- Empty table? It seems that there is nothing actually in here.
---@field size integer  Number of items in the stack.
---@field tag string  Not really sure what type this technically is. It doesn't matter, though, and I don't think it's technically supposed to be exposed anyways.
local AnalyzedBeeStack = {}


---@class AnalyzedBeeIndividual
---@field active AnalyzedBeeTraits  Active traits for this individual.
---@field canSpawn boolean
---@field displayName string  "Common" name of the primary species.
---@field generation integer
---@field hasEffect boolean
---@field health integer  -- Unsure whether this is 'number' or 'integer'? Either way, it doesn't seem to be relevant.
---@field ident string  An identifier like "forestry.speciesForest".
---@field inactive AnalyzedBeeTraits  Inactive traits for this individual.
---@field isAlive boolean
---@field isAnalyzed boolean  Whether this bee has been analyzed.
---@field isSecret boolean
---@field isNatural boolean  Whether this species spawns naturally in hives in the world.
---@field maxHealth integer
---@field type string  For bees, this seems to always be set to "bee".
local AnalyzedBeeIndividual = {}


---@class AnalyzedBeeTraits
---@field caveDwelling boolean  Whether this bee can work without access to the sky above its housing.
---@field effect string  The effect provided by this bee, or "NONE" if no effect.
---@field fertility integer  The number of drones produced by this bee upon dying.
---@field flowering integer  The degree to which this bee spreads flowers.
---@field flowerProvider string  Describes the flowers required by this bee. TODO: Verify these values and possibly include logic for placing correct flowers.
---@field humidityTolerance string  The humidity tolerance of this bee, or "NONE" if none.
---@field lifespan integer
---@field nocturnal boolean  Whether this bee can work at night.
---@field species BeeSpecies  Information on the species of this bee.
---@field speed number
---@field temperatureTolerance string  The termperature tolerance of this bee, of "NONE" if none.
---@field territory integer[]
---@field tolerantFlyer boolean  Whether this bee can work in the rain.
local AnalyzedBeeTraits = {}


---@class BeeSpecies
---@field humidity string  The humidity required by this species for its jubilant state.
---@field name string  The "common" name of this species.
---@field temperature string  The temperature required by this species for its jubilant state.
---@field uid string  The unique identifier for this species like "forestry.speciesForest".
local BeeSpecies = {}
