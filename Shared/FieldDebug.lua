-- This module contains debug features that might be helpful for debugging in the field on an actual live system.
-- It is not returned as a distinct module because it is intended to be imported into the global namespace for ease of use.

Event = require("event")
require("Shared.Shared")

function DebugPromptForKeyPress(message)
    Print(tostring(message))
    Sleep(0.25)
    Event.pull("key_up")
end
