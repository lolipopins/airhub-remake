    --// в начале файла, рядом с другими local-таблицами (после speedMethods):
    local spiderModes  = { "Default", "Pixelwalk", "Wallfucker" }

    --// ... блок MOVEMENT ...

    local spiderSec = MovementTab:CreateSection({ Name = "Spider (Bhop assist)", Side = "Right" })
    spiderSec:AddToggle({ Name = "Enabled", Value = Bhop.Settings.Spider.Enabled,
        Callback = function(v) Bhop.Settings.Spider.Enabled = v end })
    spiderSec:AddDropdown({ Name = "Mode",
        Value = Bhop.Settings.Spider.Mode or "Default",
        List = spiderModes,
        Callback = function(v) Bhop.Settings.Spider.Mode = v end })
    spiderSec:AddSlider({ Name = "Wall Range (Default)", Value = Bhop.Settings.Spider.Range,
        Min = 1, Max = 10, Decimals = 1,
        Callback = function(v) Bhop.Settings.Spider.Range = v end })
    spiderSec:AddSlider({ Name = "Ray Count (Default)", Value = Bhop.Settings.Spider.RayCount,
        Min = 4, Max = 24,
        Callback = function(v) Bhop.Settings.Spider.RayCount = v end })

    --// ==== Spider: Pixelwalk ====
    local pxwSec = MovementTab:CreateSection({ Name = "Spider: Pixelwalk", Side = "Right" })
    pxwSec:AddSlider({ Name = "Down Range", Value = Bhop.Settings.Spider.Pixelwalk.DownRange,
        Min = 1, Max = 10, Decimals = 1,
        Callback = function(v) Bhop.Settings.Spider.Pixelwalk.DownRange = v end })
    pxwSec:AddSlider({ Name = "Max Part Width (thin)", Value = Bhop.Settings.Spider.Pixelwalk.MaxWidth,
        Min = 0.05, Max = 5, Decimals = 2,
        Callback = function(v) Bhop.Settings.Spider.Pixelwalk.MaxWidth = v end })
    pxwSec:AddSlider({ Name = "Snap Distance", Value = Bhop.Settings.Spider.Pixelwalk.SnapDistance,
        Min = 0.1, Max = 6, Decimals = 2,
        Callback = function(v) Bhop.Settings.Spider.Pixelwalk.SnapDistance = v end })
    pxwSec:AddSlider({ Name = "Stick Power (0..1)", Value = Bhop.Settings.Spider.Pixelwalk.StickPower,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) Bhop.Settings.Spider.Pixelwalk.StickPower = v end })
    pxwSec:AddToggle({ Name = "Force Running State", Value = Bhop.Settings.Spider.Pixelwalk.ForceRunning ~= false,
        Callback = function(v) Bhop.Settings.Spider.Pixelwalk.ForceRunning = v end })

    --// ==== Spider: Wallfucker ====
    local wfkSec = MovementTab:CreateSection({ Name = "Spider: Wallfucker", Side = "Right" })
    wfkSec:AddSlider({ Name = "Chance per Frame (0..1)", Value = Bhop.Settings.Spider.Wallfucker.Chance,
        Min = 0, Max = 1, Decimals = 2,
        Callback = function(v) Bhop.Settings.Spider.Wallfucker.Chance = v end })
    wfkSec:AddSlider({ Name = "Wall Range", Value = Bhop.Settings.Spider.Wallfucker.WallRange,
        Min = 1, Max = 10, Decimals = 1,
        Callback = function(v) Bhop.Settings.Spider.Wallfucker.WallRange = v end })
    wfkSec:AddSlider({ Name = "Ray Count", Value = Bhop.Settings.Spider.Wallfucker.RayCount,
        Min = 4, Max = 24,
        Callback = function(v) Bhop.Settings.Spider.Wallfucker.RayCount = v end })
    wfkSec:AddToggle({ Name = "Hold Y (prevent fall)", Value = Bhop.Settings.Spider.Wallfucker.HoldY ~= false,
        Callback = function(v) Bhop.Settings.Spider.Wallfucker.HoldY = v end })
    wfkSec:AddSlider({ Name = "Push Up Strength", Value = Bhop.Settings.Spider.Wallfucker.PushStrength,
        Min = 0, Max = 50, Decimals = 1,
        Callback = function(v) Bhop.Settings.Spider.Wallfucker.PushStrength = v end })
