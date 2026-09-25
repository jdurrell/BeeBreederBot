local Luaunit = require("Test.luaunit")

local MutationConditionSet = require("Shared.MutationConditionSet")

---@param input string[] | nil
---@param expected MutationConditionSet | nil
local function assertConditionsEqual(input, expected)
    local parsed = MutationConditionSet.ParseFromForestry(input)
    Luaunit.assertEquals(parsed, expected)
end

TestMutationConditionSet = {}
    function TestMutationConditionSet:TestNothing()
        assertConditionsEqual({}, nil)
        assertConditionsEqual(nil, nil)
    end

    function TestMutationConditionSet:TestFoundation()
        assertConditionsEqual(
            {"Requires Clay as a foundation."},
            {foundation = "clay"}
        )
    end

    function TestMutationConditionSet:TestFoundationMultiWord()
        assertConditionsEqual(
            {"Requires Block of Thaumium as a foundation."},
            {foundation = "block of thaumium"}
        )
    end

    function TestMutationConditionSet:TestFoundationNumerical()
        assertConditionsEqual(
            {"Requires Block of Cinobite A243 as a foundation."},
            {foundation = "block of cinobite a243"}
        )
    end

    function TestMutationConditionSet:TestFoundationWeirdCharacter()
        assertConditionsEqual(
            {"Requires α Centauri Bb Surface Block as a foundation."},
            {foundation = "α centauri bb surface block"}
        )
    end

    function TestMutationConditionSet:TestHumidity()
        assertConditionsEqual(
            {"Requires Damp humidity."},
            {humidity = "damp"}
        )
    end

    function TestMutationConditionSet:TestTemperatureSingle()
        assertConditionsEqual(
            {"Requires Icy temperature."},
            {temperature1 = "icy"}
        )
    end

    function TestMutationConditionSet:TestTemperatureDouble()
        assertConditionsEqual(
            {"Requires temperature between Hot and Hellish."},
            {temperature1 = "hot", temperature2 = "hellish"}
        )
    end

    function TestMutationConditionSet:TestDimension()
        assertConditionsEqual(
            {"Required Dimension Callisto"},
            {dimension = "callisto"}
        )
    end

    function TestMutationConditionSet:TestDimensionMultiWord()
        assertConditionsEqual(
            {"Required Dimension Kuiper Belt"},
            {dimension = "kuiper belt"}
        )
    end

    function TestMutationConditionSet:TestBiomeFormulation1()
        assertConditionsEqual(
            {"Occurs within a plains biome."},
            {biome = "plains"}
        )
    end

    function TestMutationConditionSet:TestBiomeFormulation2()
        assertConditionsEqual(
            {"Required Biome Boneyard Biome"},
            {biome = "boneyard biome"}
        )
    end

    function TestMutationConditionSet:TestBiomeFormulation3()
        assertConditionsEqual(
            {"Occurs within biomes like: [ocean, hot]"},
            {biome = "[ocean, hot]"}
        )
    end

    function TestMutationConditionSet:TestTimePeriodicFormulation1()
        assertConditionsEqual(
            {"During the night."},
            {timePeriodic = "night"}
        )
    end

    function TestMutationConditionSet:TestTimePeriodicFormulation1MultiWord()
        assertConditionsEqual(
            {"During the Full Moon"},
            {timePeriodic = "full moon"}
        )
    end

    function TestMutationConditionSet:TestTimePeriodicFormulation3()
        assertConditionsEqual(
            {"Occurs between the Waning Crescent and Waxing Crescent"},
            {timePeriodic = "between the waning crescent and waxing crescent"}
        )
    end

    function TestMutationConditionSet:TestTimePeriodicFake()
        assertConditionsEqual(
            {"Better success during the Full Moon."},
            {}
        )
    end

    function TestMutationConditionSet:TestTimeCalendar()
        assertConditionsEqual(
            {"Occurs between December 27 and January 2."},
            {timeCalendar = "between december 27 and january 2"}
        )
    end

    function TestMutationConditionSet:TestDropIrrelevant()
        assertConditionsEqual(
            {
                "Occurs between February 29 and February 29.",
                "During the day.",
                "Inspired by ",
                "[§4§lR§c§lu§6§ln§e§la§2§lk§a§la§b§li§r, boubou_19§r, Alastors_Game§r, ",
                " BlueWeabo§r, Lewis_Saber§r, True_Aurastorm§r, ",
                " mitchej123§r, minecraft7771§r, _Timbo§r, ",
                " kuba6000§r, Alrightsc§r, YeetYeetDatBoi§r, ",
                " DreamMasterXXL§r, Colen§r, OrderedSet§r]",
            },
            {timePeriodic = "day", timeCalendar = "between february 29 and february 29"}
        )
    end

    function TestMutationConditionSet:TestHandleMultiple()
        assertConditionsEqual(
            {
                "Requires Arid humidity.",
                "Requires End Powder Ore as a foundation.",
                "Required Dimension End",
            },
            {foundation = "end powder ore", dimension = "end", humidity = "arid"}
        )
    end