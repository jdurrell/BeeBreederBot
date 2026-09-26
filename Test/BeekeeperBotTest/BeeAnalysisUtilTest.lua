local Luaunit = require("Test.luaunit")

local AnalysisUtil = require("BeekeeperBot.BeeAnalysisUtil")

TestAnalyzedBeeStackFromRaw = {}
    function TestAnalyzedBeeStackFromRaw:TestRawStack()
        local expected = {
            __hash = nil,
            slotInChest = 3,
            size = 6,
            individual = {
                active = {
                    nocturnal = true,
                    fertility = 1,
                    caveDwelling = true,
                    flowerProvider = "extrabees.flower.rock",
                    temperatureTolerance = "BOTH_2",
                    territory = {
                        [1] = 9,
                        [2] = 6,
                        [3] = 9,
                    },
                    species = {
                        uid = "extrabees.species.sapphire",
                    },
                    lifespan = 30,
                    speed = 0.30000001192093,
                    humidityTolerance = "BOTH_2",
                    effect = "forestry.allele.effect.none",
                    tolerantFlyer = true,
                    flowering = 5,
                },
                inactive = {
                    nocturnal = false,
                    fertility = 2,
                    caveDwelling = false,
                    flowerProvider = "flowersVanilla",
                    temperatureTolerance = "DOWN_5",
                    territory = {
                        [1] = 12,
                        [2] = 13,
                        [3] = 12,
                    },
                    species = {
                        uid = "extrabees.species.ruby",
                    },
                    lifespan = 20,
                    speed = 0.60000002384186,
                    humidityTolerance = "DOWN_5",
                    effect = "forestry.allele.effect.miasmic",
                    tolerantFlyer = false,
                    flowering = 20,
                }
            }
        }

        local rawStack = {
            size = 6,
            damage = 0,
            isCraftable = false,
            outputs = {},
            inputs = {},
            name = "Forestry:beeDroneGE",
            maxSize = 64,
            label = "Sapphire Drone",
            maxDamage = 0,
            tag = "",
            individual = {
                isAnalyzed = true,
                isSecret = true,
                displayName = "Sapphire",
                ident = "extrabees.species.sapphire",
                isNatural = true,
                hasEffect = false,
                inactive = {
                    nocturnal = false,
                    fertility = 2,
                    caveDwelling = false,
                    flowerProvider = "flowersVanilla",
                    temperatureTolerance = "DOWN_5",
                    territory = {
                        [1] = 12,
                        [2] = 13,
                        [3] = 12,
                    },
                    species = {
                        temperature = "Normal",
                        uid = "extrabees.species.ruby",
                        humidity = "Normal",
                        name = "Sapphire",
                    },
                    lifespan = 20,
                    speed = 0.60000002384186,
                    humidityTolerance = "DOWN_5",
                    effect = "forestry.allele.effect.miasmic",
                    tolerantFlyer = false,
                    flowering = 20,
                },
                health = 30,
                maxHealth = 30,
                canSpawn = false,
                active = {
                    nocturnal = true,
                    fertility = 1,
                    caveDwelling = true,
                    flowerProvider = "extrabees.flower.rock",
                    temperatureTolerance = "BOTH_2",
                    territory = {
                        [1] = 9,
                        [2] = 6,
                        [3] = 9,
                    },
                    species = {
                        temperature = "Normal",
                        uid = "extrabees.species.sapphire",
                        humidity = "Normal",
                        name = "Sapphire",
                    },
                    lifespan = 30,
                    speed = 0.30000001192093,
                    humidityTolerance = "BOTH_2",
                    effect = "forestry.allele.effect.none",
                    tolerantFlyer = true,
                    flowering = 5,
                },
                isAlive = true,
                type = "bee",
                generation = 0,
            },
            hasTag = true,
        }

        local actual = AnalysisUtil.AnalyzedBeeStackFromRaw(rawStack, 3)
        Luaunit.assertEquals(actual, expected)
    end

TestAnalyzedBeeTraitsFromRaw = {}
    function TestAnalyzedBeeTraitsFromRaw:TestRawTraits()
        local expected = {
            nocturnal = true,
            fertility = 1,
            caveDwelling = true,
            flowerProvider = "extrabees.flower.rock",
            temperatureTolerance = "BOTH_2",
            territory = {
                [1] = 9,
                [2] = 6,
                [3] = 9,
            },
            species = {
                uid = "extrabees.species.sapphire",
            },
            lifespan = 30,
            speed = 0.30000001192093,
            humidityTolerance = "BOTH_2",
            effect = "forestry.allele.effect.none",
            tolerantFlyer = true,
            flowering = 5,
        }

        local rawTraits = {
            nocturnal = true,
            fertility = 1,
            caveDwelling = true,
            flowerProvider = "extrabees.flower.rock",
            temperatureTolerance = "BOTH_2",
            territory = {
                [1] = 9,
                [2] = 6,
                [3] = 9,
            },
            species = {
                temperature = "Normal",
                uid = "extrabees.species.sapphire",
                humidity = "Normal",
                name = "Sapphire",
            },
            lifespan = 30,
            speed = 0.30000001192093,
            humidityTolerance = "BOTH_2",
            effect = "forestry.allele.effect.none",
            tolerantFlyer = true,
            flowering = 5,
        }

        local actual = AnalysisUtil.AnalyzedBeeTraitsFromRaw(rawTraits)
        Luaunit.assertEquals(actual, expected)
    end