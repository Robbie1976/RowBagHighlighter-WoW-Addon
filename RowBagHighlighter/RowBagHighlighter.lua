-- RowBagHighlighter.lua
-- Addon: hebt Items in Taschen hervor, die über einem Wert liegen (TSM Preis).

local addonName, RBH = ...
_G["RBH"] = RBH
RBH.highlighted = {}
RBH.debug = false

-- SavedVariables (Defaults: 200g, Gelb, Alpha 0.2, DBMarket)
RowBagHighlighterDB = RowBagHighlighterDB or {
    threshold = 2000000, -- 200g in Kupfer
    color = { r = 1, g = 0, b = 1, a = 0.2 },
    tsmPrice = "DBMarket",
}

--------------------------------------------------
-- Utils / Debug
--------------------------------------------------
local function DebugPrint(msg)
    if RBH.debug then
        print("|cff33ff99RBH:|r", msg)
    end
end

local function Clamp(v, minV, maxV)
    if v == nil then return nil end
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

--------------------------------------------------
-- Soulbound-Prüfung (inkl. Käfigtiere)
--------------------------------------------------
local function IsItemSoulbound(bag, slot, info)
    -- Käfig-Haustiere immer erlaubt
    if info and info.hyperlink and info.hyperlink:find("battlepet:") then
        return false
    end
    if info and info.itemID == 82800 then -- „Käfig“-Item
        return false
    end

    local tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltipData or not tooltipData.lines then return false end
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText then
            if line.leftText:find(ITEM_SOULBOUND)
            or line.leftText:find(ITEM_ACCOUNTBOUND)
            or line.leftText:find(ITEM_BNETACCOUNTBOUND) -- manche Clients
            or line.leftText:find("Kriegsmeutengebunden") -- falls Lokalisierung nötig
            then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------
-- TSM ItemString
--------------------------------------------------
local function GetTSMItemString(hyperlink)
    if not hyperlink then return nil end
    local itemID = hyperlink:match("item:(%d+)")
    if itemID then
        return "i:" .. itemID
    end
end

--------------------------------------------------
-- Preis-Cache
--------------------------------------------------
RBH.priceCache = {}

local function GetCachedPrice(itemString)
    if not itemString then return 0 end
    -- Cache-Hit?
    local cached = RBH.priceCache[itemString]
    if cached ~= nil then
        return cached
    end
    -- Abfrage bei TSM
    local price = 0
    if TSM_API and TSM_API.GetCustomPriceValue and RowBagHighlighterDB.tsmPrice then
        price = TSM_API.GetCustomPriceValue(RowBagHighlighterDB.tsmPrice, itemString) or 0
    end
    RBH.priceCache[itemString] = price
    return price
end

function RBH.ClearPriceCache()
    RBH.priceCache = {}
    DebugPrint("Preis-Cache geleert.")
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
-- Overlay zeichnen
--------------------------------------------------
function RBH.UpdateBagSlotOverlay(bag, slot, frame)
    if not frame then return end
    local price = RBH.highlighted[bag] and RBH.highlighted[bag][slot]

    if not frame.RBHOverlay then
        local overlay = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        overlay:SetAllPoints(frame)
        frame.RBHOverlay = overlay
    end

    if price then
        local c = RowBagHighlighterDB.color or {}
        local r = Clamp(c.r, 0, 1) or 1
        local g = Clamp(c.g, 0, 1) or 1
        local b = Clamp(c.b, 0, 1) or 0
        local a = Clamp(c.a, 0, 1) or 0.2
        frame.RBHOverlay:SetColorTexture(r, g, b, a)
        frame.RBHOverlay:Show()
    else
        frame.RBHOverlay:Hide()
    end
end

--------------------------------------------------
-- Bag/Slot von ItemButton bestimmen
--------------------------------------------------
local function ResolveButtonBagSlot(button, parentFrame)
    if button.GetBagID then
        local ok, bagID = pcall(button.GetBagID, button)
        if ok and type(bagID) == "number" then
            local slotID = (button.GetSlot and button:GetSlot()) or (button.GetID and button:GetID()) or nil
            if type(slotID) == "number" then
                return bagID, slotID
            end
        end
    end
    if button.bagID and button.slot then return button.bagID, button.slot end
    if button.bag   and button.slot then return button.bag,   button.slot end
    local bag = parentFrame and parentFrame.GetID and parentFrame:GetID() or (button:GetParent() and button:GetParent().GetID and button:GetParent():GetID())
    local slot = button.GetID and button:GetID() or nil
    return bag, slot
end

--------------------------------------------------
-- Rekursiv alle ItemButtons durchlaufen
--------------------------------------------------
local function ForEachItemButton(root, cb)
    if not root or not root.GetChildren then return end
    local function visit(frame)
        local n = select("#", frame:GetChildren())
        for i = 1, n do
            local child = select(i, frame:GetChildren())
            if type(child) == "table" then
                if child.GetObjectType and child:GetObjectType() == "Button" and child.IsVisible and child:IsVisible() then
                    local bag, slot = ResolveButtonBagSlot(child, frame)
                    if type(bag) == "number" and type(slot) == "number" then
                        local maxSlots = C_Container.GetContainerNumSlots(bag) or 0
                        if bag >= 0 and bag <= 4 and slot >= 1 and slot <= maxSlots then
                            cb(child, bag, slot)
                        end
                    end
                end
                if child.GetChildren then
                    visit(child)
                end
            end
        end
    end
    visit(root)
end

--------------------------------------------------
-- Overlays erneuern (Standard, Combined, Bagnon)
--------------------------------------------------
function RBH.UpdateAllOverlays()
    -- Combined Bags (Blizzard)
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        ForEachItemButton(ContainerFrameCombinedBags, function(btn, bag, slot)
            RBH.UpdateBagSlotOverlay(bag, slot, btn)
        end)
    end

    -- Einzelne ContainerFrames (Blizzard)
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame"..i]
        if frame and frame:IsShown() then
            ForEachItemButton(frame, function(btn, bag, slot)
                RBH.UpdateBagSlotOverlay(bag, slot, btn)
            end)
        end
    end

    -- Bagnon/BagBrother (mehrere mögliche Wurzel-Frames)
    -- Bagnon/BagBrother: Scan beim Öffnen
    local bagnonRoots = { _G["BagnonInventory1"], _G["BagnonFrameinventory"], _G["BagnonInventoryFrame"] }
    for _, root in ipairs(bagnonRoots) do
        if root then
            root:HookScript("OnShow", function()
                DebugPrint("Bagnon Inventar geöffnet – automatischer Scan")
                C_Timer.After(0.1, RBH.ApplySettings)  -- kleiner Delay, damit Buttons sicher gebaut sind
            end)
        end
    end

    -- Bagnon/BagBrother Buttons
    for i = 1, 300 do  -- genügend hoch, Standard-Inventar < 200
        local btn = _G["BagnonContainerItem"..i]
        if btn and btn:IsVisible() then
            local bag = btn.bag or (btn.GetBagID and btn:GetBagID()) or nil
            local slot = btn.slot or (btn.GetID and btn:GetID()) or nil
            if type(bag) == "number" and type(slot) == "number" then
                RBH.UpdateBagSlotOverlay(bag, slot, btn)
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
-- Options-UI (Dropdown für TSM, RGB-ColorPicker, Alpha-Slider)
--------------------------------------------------
RBH._optionsPanel = nil
RBH._settingsCategory = nil

local TSMPriceSources = {
    "DBMarket",
    "DBRegionMarketAvg",
    "DBRegionSaleAvg",
    "Crafting",
    "VendorSell",
    "Benutzerdefiniert…",
}

local function BuildOptionsPanel()
    if RBH._optionsPanel then return RBH._optionsPanel end

    local panel = CreateFrame("Frame", "RBHOptionsPanel")
    panel.name = "RowBagHighlighter"

    local function refreshFields()
        -- wird unten nach Erstellung mit Leben gefüllt
    end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RowBagHighlighter")

    -- Threshold
    local thLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    thLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    thLabel:SetText("Schwellenwert (Gold):")

    local thBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    thBox:SetSize(80, 20)
    thBox:SetPoint("LEFT", thLabel, "RIGHT", 10, 0)
    thBox:SetAutoFocus(false)
    thBox:SetText(string.format("%.2f", (RowBagHighlighterDB.threshold or 2000000) / 10000))
    thBox:SetCursorPosition(0)

    local thHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    thHint:SetPoint("LEFT", thBox, "RIGHT", 8, 0)
    thHint:SetText("(z.B. 200 = 200g)")

    -- TSM Preisquelle: Dropdown
    local prLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    prLabel:SetPoint("TOPLEFT", thLabel, "BOTTOMLEFT", 0, -30)
    prLabel:SetText("TSM-Preisquelle:")

    local dropdown = CreateFrame("Frame", "RBH_TSMPriceDropdown", panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", prLabel, "RIGHT", -10, -4)
    UIDropDownMenu_SetWidth(dropdown, 220)

    local function setTSMPriceSource(source, customVal)
        if source == "Benutzerdefiniert…" then
            local val = customVal or RowBagHighlighterDB.tsmPrice or "DBMarket"
            if val == "" then val = "DBMarket" end
            RowBagHighlighterDB.tsmPrice = val
            UIDropDownMenu_SetText(dropdown, val)
        else
            RowBagHighlighterDB.tsmPrice = source
            UIDropDownMenu_SetText(dropdown, source)
        end
        RBH.ApplySettings()
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, source in ipairs(TSMPriceSources) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = source
            info.func = function()
                if source == "Benutzerdefiniert…" then
                    StaticPopupDialogs["RBH_CUSTOM_PRICE"] = {
                        text = "Gib einen TSM-Custom-Preis ein:",
                        button1 = "OK",
                        button2 = "Abbrechen",
                        hasEditBox = true,
                        maxLetters = 128,
                        OnAccept = function(popup)
                            local val = popup.editBox:GetText()
                            setTSMPriceSource("Benutzerdefiniert…", val)
                        end,
                        timeout = 0, whileDead = true, hideOnEscape = true,
                    }
                    StaticPopup_Show("RBH_CUSTOM_PRICE")
                else
                    setTSMPriceSource(source)
                end
            end
            info.checked = (RowBagHighlighterDB.tsmPrice == source)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(dropdown, RowBagHighlighterDB.tsmPrice or "DBMarket")

    -- Farbe (RGB) via ColorPicker (OHNE Opacity)
    local colLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    colLabel:SetPoint("TOPLEFT", prLabel, "BOTTOMLEFT", 0, -40)
    colLabel:SetText("Highlight-Farbe:")

    local swatch = CreateFrame("Button", nil, panel)
    swatch:SetSize(24, 24)
    swatch:SetPoint("LEFT", colLabel, "RIGHT", 10, 0)
    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(swatch)

    -- Alpha-Slider (0..1) – steuert NUR Transparenz, unabhängig vom ColorPicker
    local alphaSlider = CreateFrame("Slider", "RBHAlphaSlider", panel, "OptionsSliderTemplate")
    alphaSlider:SetPoint("LEFT", swatch, "RIGHT", 120, 0)
    alphaSlider:SetMinMaxValues(0, 1)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetWidth(180)
    _G[alphaSlider:GetName().."Low"]:SetText("0")
    _G[alphaSlider:GetName().."High"]:SetText("1")

    local function UpdateSwatch(r,g,b,a)
        RowBagHighlighterDB.color = { r=r, g=g, b=b, a=a }
        tex:SetColorTexture(r, g, b, 1)
        _G[alphaSlider:GetName().."Text"]:SetText(("Transparenz (α): %.2f"):format(a))
        if math.abs(alphaSlider:GetValue() - a) > 0.001 then
            alphaSlider:SetValue(a)
        end
        RBH.ApplySettings()
    end

    swatch:SetScript("OnClick", function()
        local col = RowBagHighlighterDB.color or {r=1,g=1,b=0,a=0.2}
        -- Nur RGB wählen; Alpha bleibt vom Slider bestimmt
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            local info = {
                r = col.r, g = col.g, b = col.b,
                hasOpacity = false, -- WICHTIG: keine Alpha-Steuerung im Picker
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    UpdateSwatch(nr, ng, nb, RowBagHighlighterDB.color.a or 0.2)
                end,
                cancelFunc = function(prev)
                    if prev then
                        UpdateSwatch(prev.r or col.r, prev.g or col.g, prev.b or col.b, RowBagHighlighterDB.color.a or 0.2)
                    end
                end,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            -- Alte API
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                UpdateSwatch(nr, ng, nb, RowBagHighlighterDB.color.a or 0.2)
            end
            ColorPickerFrame.cancelFunc = function(prev)
                if prev then UpdateSwatch(prev.r, prev.g, prev.b, RowBagHighlighterDB.color.a or 0.2) end
            end
            ColorPickerFrame:SetColorRGB(col.r, col.g, col.b)
            ColorPickerFrame:Show()
        end
    end)

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        -- zwei Nachkommastellen
        value = math.floor(value * 100 + 0.5) / 100
        local c = RowBagHighlighterDB.color or {r=1,g=1,b=0,a=0.2}
        RowBagHighlighterDB.color.a = value
        _G[self:GetName().."Text"]:SetText(("Transparenz (α): %.2f"):format(value))
        RBH.ApplySettings()
    end)

    -- Apply-Button
    local applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applyBtn:SetSize(120, 22)
    applyBtn:SetPoint("TOPLEFT", colLabel, "BOTTOMLEFT", 0, -30)
    applyBtn:SetText("Übernehmen")
    applyBtn:SetScript("OnClick", function()
        local goldText = thBox:GetText() or "0"
        goldText = goldText:gsub(",", ".")
        local gold = tonumber(goldText) or 0
        if gold < 0 then gold = 0 end
        RowBagHighlighterDB.threshold = math.floor(gold * 10000 + 0.5)
        RBH.ApplySettings()
    end)

    -- Refresh bei Öffnen des Panels
    refreshFields = function()
        thBox:SetText(string.format("%.2f", (RowBagHighlighterDB.threshold or 2000000) / 10000))
        local c = RowBagHighlighterDB.color or {r=1,g=1,b=0,a=0.2}
        tex:SetColorTexture(c.r, c.g, c.b, 1)
        alphaSlider:SetValue(c.a or 0.2)
        _G[alphaSlider:GetName().."Text"]:SetText(("Transparenz (α): %.2f"):format(c.a or 0.2))
        UIDropDownMenu_SetText(dropdown, RowBagHighlighterDB.tsmPrice or "DBMarket")
    end

    panel:SetScript("OnShow", refreshFields)

    -- Registrierung (Retail bevorzugt, sonst Classic)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        RBH._settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    RBH._optionsPanel = panel
    return panel
end

local function OpenOptions()
    BuildOptionsPanel()
    if Settings and Settings.OpenToCategory and RBH._settingsCategory then
        -- Retail
        Settings.OpenToCategory(RBH._settingsCategory.ID or RBH._settingsCategory)
    elseif InterfaceOptionsFrame_OpenToCategory and RBH._optionsPanel then
        -- Classic Fallback (zweimal aufrufen, um sicher zu sein)
        InterfaceOptionsFrame_OpenToCategory(RBH._optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(RBH._optionsPanel)
    else
        print("|cff33ff99RBH:|r Konnte Optionspanel nicht öffnen.")
    end
end

--------------------------------------------------
-- Events (mit Debounce)
--------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE_DELAYED")

-- Debounce-Status
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
-- Slash-Befehle
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
