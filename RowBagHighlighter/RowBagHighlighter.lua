--------------------------------------------------
-- Preis-Cache
--------------------------------------------------
RBH.priceCache = {}

local function GetCachedPrice(itemString)
    if not itemString then return 0 end
    -- aus Cache lesen
    if RBH.priceCache[itemString] then
        return RBH.priceCache[itemString]
    end
    -- neu abfragen
    local price = 0
    if TSM_API and TSM_API.GetCustomPriceValue and RowBagHighlighterDB.tsmPrice then
        price = TSM_API.GetCustomPriceValue(RowBagHighlighterDB.tsmPrice, itemString) or 0
    end
    RBH.priceCache[itemString] = price
    return price
end

function RBH.ClearPriceCache()
    RBH.priceCache = {}
end

--------------------------------------------------
-- Preis-Scan (mit Cache)
--------------------------------------------------
function RBH.ScanBags()
    DebugPrint("Starte Scan...")
    RBH.highlighted = {}

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        RBH.highlighted[bag] = {}
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local itemString = GetTSMItemString(info.hyperlink)
                local price = GetCachedPrice(itemString)
                if not IsItemSoulbound(bag, slot, info) and price >= (RowBagHighlighterDB.threshold or 2000000) then
                    RBH.highlighted[bag][slot] = price
                    DebugPrint(("Bag %d Slot %d Wert %dg"):format(bag, slot, price/10000))
                end
            end
        end
    end
end

--------------------------------------------------
-- ApplySettings (Scan + Overlays)
--------------------------------------------------
function RBH.ApplySettings()
    RBH.ScanBags()
    RBH.UpdateAllOverlays()
end

--------------------------------------------------
-- Event-Handling mit Debounce
--------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")

-- debounce state
local scanScheduled = false
local function ScheduleScan()
    if not scanScheduled then
        scanScheduled = true
        C_Timer.After(0.5, function()
            scanScheduled = false
            RBH.ApplySettings()
        end)
    end
end

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        DebugPrint("Addon geladen.")
        BuildOptionsPanel()
        RBH.ApplySettings()

        -- Hooks für Taschenfenster
        if ContainerFrameCombinedBags then
            ContainerFrameCombinedBags:HookScript("OnShow", function() RBH.ApplySettings() end)
        end
        for i = 1, NUM_CONTAINER_FRAMES do
            local frame = _G["ContainerFrame"..i]
            if frame then frame:HookScript("OnShow", function() RBH.ApplySettings() end) end
        end
        local bagnonRoots = { _G["BagnonInventory1"], _G["BagnonFrameinventory"], _G["BagnonInventoryFrame"] }
        for _, root in ipairs(bagnonRoots) do
            if root then root:HookScript("OnShow", function() RBH.ApplySettings() end) end
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        ScheduleScan()
    end
end)

--------------------------------------------------
-- Slash-Befehle (Cache-Reset integriert)
--------------------------------------------------
SLASH_RBH1 = "/rbh"
SlashCmdList["RBH"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "config" or msg == "options" or msg == "settings" then
        OpenOptions()
    elseif msg == "scan" then
        RBH.ClearPriceCache()
        RBH.ApplySettings()
    elseif msg == "debug" then
        RBH.debug = not RBH.debug
        print("RBH Debug:", RBH.debug and "an" or "aus")
    else
        print("RBH Befehle:")
        print("/rbh scan     - Cache leeren & Taschen neu scannen")
        print("/rbh config   - Einstellungen öffnen (Optionen > AddOns)")
        print("/rbh debug    - Debug an/aus")
    end
end
