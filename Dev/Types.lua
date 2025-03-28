-- This file contains types for easy reference and external Intellisense.
-- It isn't needed on the in-game devices since it provides no direct functionality.

---@meta

---@class SpeciesNode
---@field speciesName string          The name of this species.
---@field parentMutations {parents: string[], chance: number, specialConditions: string[]}[]  All parent mutations that can result in this species.
---@field childMutations table<string, {parent: string, chance: number, specialConditions: string[]}[]>    Mapping of results to other parents that combo to yield that result.
local Speciesnode = {}

---@alias SpeciesGraph table<string, SpeciesNode>
---@alias BreedInfo table<string, table<string, number>>

---@class BreedPathNode
---@field target string
---@field parent1 string
---@field parent2 string
---@field foundation string | nil
local BreedPathNode = {}

---@class ForestryMutation
---@field allele1 string
---@field allele2 string
---@field chance number
---@field result string
---@field specialConditions string[]
local ForestryMutation = {}

---@class ParentMutation
---@field allele1 BeeSpecies
---@field allele2 BeeSpecies
---@field chance number
---@field specialConditions string[]
local ParentMutation = {}

---@generic T
---@class Chromosome<T>: {primary: T, secondary: T}
local Chromosome = {}

-- TODO: Add other chromosomes that we will end up caring about later on.
--       In theory, this should be kept in sync with AnalyzedBeeTraits.
---@class ForestryGenome
---@field caveDwelling Chromosome<boolean>  Whether this bee can work without access to the sky above its housing.
---@field effect Chromosome<string>  The effect provided by this bee, or "NONE" if no effect.
---@field fertility Chromosome<integer>  The number of drones produced by this bee upon dying.
---@field flowering Chromosome<integer>  The degree to which this bee spreads flowers.
---@field flowerProvider Chromosome<string>  Describes the flowers required by this bee. TODO: Verify these values and possibly include logic for placing correct flowers.
---@field humidityTolerance Chromosome<string>  The humidity tolerance of this bee, or "NONE" if none.
---@field lifespan Chromosome<integer>
---@field nocturnal Chromosome<boolean>  Whether this bee can work at night.
---@field species Chromosome<BeeSpecies>  Information on the species of this bee.
---@field speed Chromosome<number>
---@field temperatureTolerance Chromosome<string>  The temperature tolerance of this bee, of "NONE" if none.
---@field territory Chromosome<integer[]>
---@field tolerantFlyer Chromosome<boolean>  Whether this bee can work in the rain.
local ForestryGenome = {}

-- Mapping of each species to a boolean that represents whether the species allele is dominant.
-- This is communicated from the server to the robot in production code.
---@class TraitInfoSpecies
---@field species table<string, boolean>
local TraitInfoSpecies = {}

-- Mapping of each trait to a boolean that represents whether the given allele is dominant.
-- This is only used by simulation code.
---@class TraitInfoFull: TraitInfoSpecies
---@field caveDwelling table<boolean, boolean>
---@field effect table<string, boolean>
---@field fertility table<integer, boolean>
---@field flowerProvider table<string, boolean>
---@field humidityTolerance table<string, boolean>
---@field nocturnal table<boolean, boolean>
---@field species table<string, boolean>  indexed by species.uid
---@field speed table<number, boolean>
---@field temperatureTolerance table<string, boolean>
---@field territory table<integer, boolean>  indexed by territory[1]
---@field tolerantFlyer table<boolean, boolean>
local TraitInfoFull = {}


-- TODO: All of this information was sourced from a drone. I *think* princesses have the exact same structure, but this should be verified.
-- TODO: All of this information was sourced from a Forest bee. Other species could potentially have additional information.
---@class AnalyzedBeeStack
---@field damage number
---@field hasTag boolean
---@field individual AnalyzedBeeIndividual  The actual bee information.
---@field inputs {}  Empty table? It seems that there is nothing actually in here.
---@field isCraftable boolean
---@field label string  Translated name (appears as the "common name" of the item in-game).
---@field maxDamage number
---@field maxSize integer
---@field name string   Untranslated name (internal Minecraft name).
---@field outputs {}  Empty table? It seems that there is nothing actually in here.
---@field size integer  Number of items in the stack.
---@field tag string  Not really sure what type this technically is. It doesn't matter, though, and I don't think it's technically supposed to be exposed anyways.
---@field slotInChest integer  Must be assigned upon reading the stack from the chest.
---@field __hash string  Testing field for simulator optimization.
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
---@field __genome ForestryGenome  For use by modules internal to testing *only*! This field is not accessible from production code.
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
---@field temperatureTolerance string  The temperature tolerance of this bee, of "NONE" if none.
---@field territory integer[]
---@field tolerantFlyer boolean  Whether this bee can work in the rain.
local AnalyzedBeeTraits = {}

---@class BeeSpecies
---@field humidity string  The humidity required by this species for its jubilant state.
---@field name string  The "common" name of this species.
---@field temperature string  The temperature required by this species for its jubilant state.
---@field uid string  The unique identifier for this species like "forestry.speciesForest".
local BeeSpecies = {}

---@class StorageNode
---@field loc Point
---@field timestamp integer
local StorageNode = {}

---@alias ChestArray table<string, StorageNode>


---@class StorageInfo
---@field nextChest Point  The next open chest to use for a new species.
---@field chestArray ChestArray  Mapping of species to the chest where they are stored.
local StorageInfo = {}

---@class Point
---@field x integer
---@field y integer
---@field z integer
local Point = {}

-- TODO: Define types for message payloads.
--- Generics are still in progress, which is why this looks a little weird compared to the other types.
---@class Message
---@field code integer
---@field payload table
local Message = {}

---@class CodedMessage<T>: {code: integer, payload: T}
local CodedMessage = {}

-- Mapping of target to cached breed info elements.
---@alias BreedInfoCache table<string, BreedInfoCacheElement>

-- TODO: Refactor this to be a unique key like "parent1-parent2".
-- Mapping of princess to drone to chance for parents to mutate into the target and chance for parents to mutate into a different species.
---@alias BreedInfoCacheElement table<string, table<string, {targetMutChance: number, nonTargetMutChance: number}>>

---@alias BreedInfoRequestPayload {parent1: string, parent2: string, target: string}
---@alias BreedInfoResponsePayload {targetMutChance: number, nonTargetMutChance: number}
---@alias PingRequestPayload {transactionId: integer}
---@alias PingResponsePayload {transactionId: integer}
---@alias SpeciesFoundRequestPayload {species: string}
---@alias LocationRequestPayload {species: string}
---@alias LocationResponsePayload {loc: Point, isNew: boolean}
---@alias TraitInfoRequestPayload {species: string}
---@alias TraitInfoResponsePaytoad {dominant: boolean}
---@alias BreedCommandPayload BreedPathNode[]
---@alias ReplicateCommandPayload {species: string}
---@alias PromptConditionsPayload {target: string, parent1: string, parent2: string, promptFoundation: boolean}
---@alias PropagateTemplatePayload {traits: AnalyzedBeeTraits}
---@alias PrintErrorPayload {errorMessage: string}

---@class Set<T>: table<T, boolean>
local Set = {}
