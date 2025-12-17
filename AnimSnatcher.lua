local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

local PlayerGui = Player:WaitForChild("PlayerGui")
for _, gui in ipairs(PlayerGui:GetChildren()) do
    if gui:IsA("ScreenGui") and gui:FindFirstChild("HubMainFrame") then
        gui:Destroy()
    end
end

local CursedMode = false
local HeaderSize = 25
local PlayingId = 0
local Track = nil

local Red = Color3.fromRGB(255, 70, 70)
local Green = Color3.fromRGB(0, 200, 120)
local Grey = Color3.fromRGB(45, 45, 45)
local Blue = Color3.fromRGB(0, 170, 255)

local NewBadgeTimers = {}
local StolenList = {}
local SavedSpeeds = {}
local FavoriteList = {}
local EmoteList = {}
local ActiveDropdownFilter = "All"
local DeleteMode = false

local CurrentSearchText = ""

local WindowWidth = 240
local ListWidth = WindowWidth
local ControlRowHeight = 25
local TabRowHeight = 25
local NowPlayingHeight = 30
local ListHeight = 250
local WindowHeight = HeaderSize + (ControlRowHeight * 2) + TabRowHeight + NowPlayingHeight + ListHeight + ControlRowHeight

local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local Panel = Instance.new("Frame")
local StolenAnimationsFrame
local StolenItemsContainer
local PageControlFrame
local DropdownList
local DropdownButton
local Searchbar
local NowPlayingFrame
local NowPlayingLabel
local NowPlayingSpeedBox
local NowPlayingStopButton

local Anim = Instance.new("Animation")
Anim.Name = "HubAnimation"

local ITEMS_PER_PAGE = 25
local Pagination = {
    current = 1,
    total = 1,
    pages = {}
}

local STAR_FULL = (utf8 and utf8.char) and utf8.char(0x2605) or "*"
local STAR_EMPTY = (utf8 and utf8.char) and utf8.char(0x2606) or "-"

local StealStage = 0

local TabStates = {
    All = {page = 1, search = ""},
    Favorite = {page = 1, search = ""},
    Emote = {page = 1, search = ""},
    New = {page = 1, search = ""},
}

local function NormalizeAnimId(id)
    if not id then return nil end
    local s = tostring(id)
    if s:match("^rbxassetid://%d+$") then
        return s
    elseif s:match("^%d+$") then
        return "rbxassetid://" .. s
    else
        local digits = s:match("%d+")
        if not digits then return nil end
        return "rbxassetid://" .. digits
    end
end

local function LoadFavorites()
    if not isfile or not readfile then return end
    if not isfile("FavoriteList.json") then return end
    
    local success, content = pcall(readfile, "FavoriteList.json")
    if not success or not content or content == "" then return end
    
    local success2, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    
    if success2 and type(decoded) == "table" then
        FavoriteList = {}
        for id, data in pairs(decoded) do
            local normalizedId = NormalizeAnimId(id)
            if normalizedId then
                if type(data) == "table" then
                    FavoriteList[normalizedId] = {
                        Name = data.Name or "Unknown"
                    }
                else
                    FavoriteList[normalizedId] = { 
                        Name = tostring(data)
                    }
                end
            end
        end
    end
end

local function SaveFavorites()
    if not writefile then return end
    pcall(function()
        writefile("FavoriteList.json", HttpService:JSONEncode(FavoriteList))
    end)
end

local function UpdateRowEmoteButton(emoteBtn, normalizedID)
    if not emoteBtn then return end
    
    local row = emoteBtn.Parent
    if not row or not row:IsA("Frame") then return end
    
    if EmoteList[normalizedID] then
        emoteBtn.Text = "😊"
        emoteBtn.TextColor3 = Color3.new(1,1,0)
        row:SetAttribute("IsEmote", true)
    else
        emoteBtn.Text = "🫥"
        emoteBtn.TextColor3 = Color3.fromRGB(180,180,180)
        row:SetAttribute("IsEmote", false)
    end
end

local function LoadEmotes()
    if not isfile or not readfile then return end
    if not isfile("EmoteList.json") then return end
    
    local success, content = pcall(readfile, "EmoteList.json")
    if not success or not content or content == "" then return end
    
    local success2, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    
    if success2 and type(decoded) == "table" then
        EmoteList = decoded
        

        task.spawn(function()
            task.wait(0.1)
            for _, row in pairs(StolenItemsContainer:GetChildren()) do
                if row:IsA("Frame") then
                    local animId = row:GetAttribute("AnimId")
                    if animId and EmoteList[animId] then
                        row:SetAttribute("IsEmote", true)
                        local emoteBtn = row:FindFirstChild("EmoteButton")
                        if emoteBtn then
                            UpdateRowEmoteButton(emoteBtn, animId)
                        end
                    end
                end
            end
        end)
    end
end

local function SaveEmotes()
    if not writefile then return end
    pcall(function()
        writefile("EmoteList.json", HttpService:JSONEncode(EmoteList))
    end)
end

local function SaveSpeed(animId, value)
    if not animId then return end
    if value == "" or value == nil then
        SavedSpeeds[animId] = nil
    else
        SavedSpeeds[animId] = tonumber(value)
    end
    pcall(function()
        writefile("AnimSpeed.json", HttpService:JSONEncode(SavedSpeeds))
    end)
end

local function SafeReadStolenList()
    if not isfile or not readfile or not isfile("StolenList.json") then
        return
    end
    local ok, content = pcall(readfile, "StolenList.json")
    if not ok or not content or content == "" then return end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok2 or type(decoded) ~= "table" then return end
    for _, data in pairs(decoded) do
        if data.ID and data.Name then
            local normalizedID = NormalizeAnimId(data.ID)
            if normalizedID then
                local found = false
                for _, v in pairs(StolenList) do
                    local vid = NormalizeAnimId(v.ID)
                    if vid == normalizedID then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(StolenList, {
                        Name = data.Name,
                        ID = normalizedID,
                        animId = tonumber(normalizedID:match("%d+")) or data.animId
                    })
                end
            end
        end
    end
end

local function SafeWriteStolen()
    if not writefile then return end
    pcall(function()
        writefile("StolenList.json", HttpService:JSONEncode(StolenList))
    end)
end

if isfile and isfile("AnimSpeed.json") then
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile("AnimSpeed.json"))
    end)
    if ok and type(data) == "table" then
        SavedSpeeds = data
    end
end

local function AlphaNumericSort(a, b)
    local A = string.lower(a.Name)
    local B = string.lower(b.Name)
    local A_is_digit = A:match("^[0-9]")
    local B_is_digit = B:match("^[0-9]")
    local A_is_alpha = A:match("^[a-z]")
    local B_is_alpha = B:match("^[a-z]")
    if A_is_alpha and not B_is_alpha then return true end
    if B_is_alpha and not A_is_alpha then return false end
    if A_is_digit and not B_is_digit then return true end
    if B_is_digit and not A_is_digit then return false end
    if (not A_is_alpha and not A_is_digit) and (B_is_alpha or B_is_digit) then
        return false
    end
    if (not B_is_alpha and not B_is_digit) and (A_is_alpha or A_is_digit) then
        return true
    end
    return A < B
end

local function GetNearestCharacter(pos)
    local closestChar = nil
    local closestDist = 12
    for _, plr in ipairs(game.Players:GetPlayers()) do
        if plr.Character and plr.Character:FindFirstChild("Humanoid") and plr.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = plr.Character.HumanoidRootPart
            local dist = (hrp.Position - pos).Magnitude
            if dist < closestDist then
                closestDist = dist
                closestChar = plr.Character
            end
        end
    end
    return closestChar
end

local function MassUnToggle(activeButton)
    for _, row in pairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") then
            for _, btn in pairs(row:GetChildren()) do
                if btn:IsA("TextButton") and btn ~= activeButton then
                    if btn:GetAttribute("Toggled") then
                        btn:SetAttribute("Toggled", false)
                        btn.BackgroundColor3 = Red 
                    end
                end
            end
        end
    end
end

local function CreateInteractable(Size, Name, Text, Color, IsButton, Type, Parent)
    local Interact
    if Type == "TextBox" then
        Interact = Instance.new("TextBox")
        Interact.Text = ""
        Interact.PlaceholderText = Text
        Interact.ClearTextOnFocus = false
        Interact.TextColor3 = Color3.new(1,1,1)
        Interact.TextScaled = true
        Interact.BackgroundColor3 = Color
        Interact.BorderSizePixel = 0
        Interact.Size = Size
        Interact.Parent = Parent
        Instance.new("UICorner", Interact)
        return Interact
    end
    Interact = Instance.new("TextButton")
    Interact.Name = Name
    Interact.Text = ""
    Interact.Size = Size
    Interact.BackgroundColor3 = Color
    Interact.BorderSizePixel = 0
    Interact.Parent = Parent
    local Label = Instance.new("TextLabel")
    Label.Name = "Label"
    Label.Text = Text
    Label.BackgroundTransparency = 1
    Label.Size = UDim2.new(1, 0, 1, 0)
    Label.Position = UDim2.new(0, 0, 0, 0)
    Label.TextColor3 = Color3.new(1,1,1)
    Label.TextWrapped = true
    Label.TextScaled = true
    Label.Parent = Interact
    Instance.new("UICorner", Interact)
    Instance.new("UICorner", Label)
    return Interact
end

local function CreateTextbox(Size, Color, Name, ID, Frame)
    local Box = CreateInteractable(Size, Name, "Speed (default 1)", Color, false, "TextBox", Frame)
    Box.PlaceholderText = "Speed (default 1)"
    Box.LayoutOrder = 1
    local normalized = NormalizeAnimId(ID)
    if SavedSpeeds[normalized] then
        Box.Text = tostring(SavedSpeeds[normalized])
    end
    Box:SetAttribute("AnimId", normalized)
    return Box
end

local function CreateButton(Size, Color, Text, Name, ID, Frame)
    local Button = CreateInteractable(Size, Name, Text, Color, true, "TextButton", Frame)
    Button.LayoutOrder = 2
    Button:SetAttribute("Toggled", false)
    local normalized = NormalizeAnimId(ID)
    Button:SetAttribute("AnimId", normalized)
    Button:SetAttribute("AnimName", Text)
    return Button
end

local function CreateDropdownItem(text)
    local item = Instance.new("TextButton")
    item.Name = text .. "Item"
    item.Size = UDim2.new(1, -4, 0, 20)
    item.Position = UDim2.new(0, 2, 0, 0)
    item.BackgroundColor3 = Grey
    item.BackgroundTransparency = 0.5
    item.Text = text
    item.TextColor3 = Color3.new(1,1,1)
    item.TextScaled = true
    Instance.new("UICorner", item)
    item.Parent = DropdownList
    return item
end

local function CreateListFrame(name)
    local Frame = Instance.new("Frame")
    Frame.Name = name
    Frame.Visible = false
    Frame.Size = UDim2.new(0, ListWidth, 0, ListHeight)
    Frame.Position = UDim2.new(0, 0, 0, HeaderSize + (ControlRowHeight * 2) + TabRowHeight)
    Frame.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    Frame.ClipsDescendants = true
    Frame.Parent = Panel
    Instance.new("UICorner", Frame)


    local Items = Instance.new("ScrollingFrame")
    Items.Name = "ItemsContainer"
    Items.Size = UDim2.new(1, 0, 1, 0)
    Items.Position = UDim2.new(0, 0, 0, 0)
    Items.BackgroundTransparency = 1
    Items.ScrollBarThickness = 6
    Items.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    Items.AutomaticCanvasSize = Enum.AutomaticSize.Y


    Items.SelectionImageObject = nil
    
    Items.CanvasSize = UDim2.new(0, 0, 0, 0)
    Items.Parent = Frame

    local padding = Instance.new("UIPadding")
    padding.PaddingBottom = UDim.new(0, 2)
    padding.PaddingTop = UDim.new(0, 2)
    padding.PaddingLeft = UDim.new(0, 5)
    padding.PaddingRight = UDim.new(0, 5)
    padding.Parent = Items

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = Items
    
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        Items.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
    end)

    return Frame, Items
end

local function PlayAnimation(ID, Speed)
    local Character = Player.Character
    if not Character then return end
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return end
    local normalized = NormalizeAnimId(ID)
    if not normalized then return end
    Anim.AnimationId = normalized
    if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") then
        pcall(function()
            if Track.IsPlaying then
                Track:Stop()
            end
        end)
        Track = nil
    end
    local ok, newTrack = pcall(function()
        return Humanoid:LoadAnimation(Anim)
    end)
    if not ok or not newTrack then
        return
    end
    Track = newTrack
    Track.Looped = true
    local playSuccess, playErr = pcall(function()
        Track:Play()
        local finalSpeed
        local boxSpeed = tonumber(Speed)
        if boxSpeed then
            finalSpeed = boxSpeed
        elseif SavedSpeeds and SavedSpeeds[normalized] then
            finalSpeed = SavedSpeeds[normalized]
        else
            finalSpeed = 1
        end
        Track:AdjustSpeed(finalSpeed)
        Track.Priority = Enum.AnimationPriority.Action
    end)
    if not playSuccess then
        Track = nil
        return
    end
    PlayingId = normalized
end

local function StopAllAnimations()
    local Character = Player.Character
    if Character then
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if Humanoid then
            for _, LocalTrack in pairs(Humanoid:GetPlayingAnimationTracks()) do
                if LocalTrack and typeof(LocalTrack) == "Instance" and LocalTrack:IsA("AnimationTrack") then
                    pcall(function() if LocalTrack.IsPlaying then LocalTrack:Stop() end end)
                end
            end
        end
    end
    if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") then
        pcall(function() if Track.IsPlaying then Track:Stop() end end)
        Track = nil
    end
    MassUnToggle(nil)
    PlayingId = 0
end

local function SyncAllSpeedBoxes(animId, newSpeed)
    local normalized = NormalizeAnimId(animId)
    if not normalized then return end
    newSpeed = tostring(newSpeed)
    for _, row in pairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") and row:GetAttribute("AnimId") == normalized then
            local sb = row:FindFirstChild("SpeedBox")
            if sb then sb.Text = newSpeed end
        end
    end
end

local function UpdateNowPlayingUI()
    if NowPlayingFrame then
        NowPlayingFrame.Visible = true
        local playingName = ""
        local currentAnimId = PlayingId
        
        for _, row in pairs(StolenItemsContainer:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("AnimId") == currentAnimId then
                playingName = row:GetAttribute("AnimName") or ""
                break
            end
        end
        
        if playingName ~= "" then
            local displayName = playingName
            if #displayName > 20 then
                displayName = displayName:sub(1, 17) .. "..."
            end
            NowPlayingLabel.Text = "Now: " .. displayName
        else
            NowPlayingLabel.Text = "Now Playing:"
        end
    end
end

local function TextboxSpeedAdjust(Box, rawID)
    local normalizedID = NormalizeAnimId(rawID)
    if not normalizedID then return end
    Box.FocusLost:Connect(function()
        local txt = Box.Text or ""
        if txt == "" then
            if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") and Track.IsPlaying then
                local playingAnimId = Track.Animation and Track.Animation.AnimationId
                local normPlay = NormalizeAnimId(playingAnimId)
                if normPlay == normalizedID then
                    pcall(function()
                        Track:AdjustSpeed(1)
                    end)
                end
            end
            Box.Text = ""
            return
        end
        if txt:match("^%.%d+$") then
            txt = "0" .. txt
            Box.Text = txt
        end
        local speedValue = tonumber(txt)
        if not speedValue or speedValue <= 0 then
            Box.Text = ""
            return
        end
        Box.Text = tostring(speedValue)
        SyncAllSpeedBoxes(normalizedID, speedValue)
        SaveSpeed(normalizedID, speedValue)
        
        if PlayingId == normalizedID and NowPlayingSpeedBox then
             NowPlayingSpeedBox.Text = tostring(speedValue)
        end
        
        if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") and Track.IsPlaying then
            local playingAnimId = Track.Animation and Track.Animation.AnimationId
            local normPlay = NormalizeAnimId(playingAnimId)
            if normPlay == normalizedID then
                pcall(function()
                    Track:AdjustSpeed(speedValue)
                end)
            end
        end
    end)
end

local function RecalculatePagination()
    local rows = {}
    for _, child in pairs(StolenItemsContainer:GetChildren()) do
        if child:IsA("Frame") and child:GetAttribute("SearchMatch") == true then
            table.insert(rows, child)
        end
    end

    local totalRows = #rows

    if totalRows == 0 then
        Pagination.pages = {}
        Pagination.total = 0
        Pagination.current = 1
        return
    end

    local pages = {}
    for i = 1, totalRows, ITEMS_PER_PAGE do
        local pageRows = {}
        for j = i, math.min(i + ITEMS_PER_PAGE - 1, totalRows) do
            table.insert(pageRows, rows[j])
        end
        table.insert(pages, pageRows)
    end

    Pagination.pages = pages
    Pagination.total = #pages

    if Pagination.current > Pagination.total then
        Pagination.current = Pagination.total
    end
    if Pagination.current < 1 then
        Pagination.current = 1
    end
end

local function ShowPage(page)
    local total = Pagination.total
    if total == 0 then
        for _, child in pairs(StolenItemsContainer:GetChildren()) do
            if child:IsA("Frame") then
                child.Visible = false
                child.Size = UDim2.new(1, child.Size.X.Offset, 0, 0)
            end
        end
        return
    end

    if page < 1 then page = 1 end
    if page > total then page = total end
    
    Pagination.current = page

    for _, child in pairs(StolenItemsContainer:GetChildren()) do
        if child:IsA("Frame") then
            child.Visible = false
            child.Size = UDim2.new(1, child.Size.X.Offset, 0, 0)
        end
    end

    local currentPage = Pagination.pages[page]
    if currentPage then
        for _, row in ipairs(currentPage) do
            if row:IsA("Frame") then
                row.Visible = true
                local h = row:GetAttribute("OriginalHeight") or 25
                row.Size = UDim2.new(1, row.Size.X.Offset, 0, h)
            end
        end
    end
end

local function UpdateFilteredRows()
    TabStates[ActiveDropdownFilter].search = CurrentSearchText

    for _, row in pairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") then
            local match = true

            if ActiveDropdownFilter == "Favorite" then
                match = row:GetAttribute("IsFavorite") == true
            elseif ActiveDropdownFilter == "Emote" then
                match = row:GetAttribute("IsEmote") == true
            elseif ActiveDropdownFilter == "New" then
                match = row:GetAttribute("IsNew") == true
            end

            if CurrentSearchText ~= "" then
                local name = string.lower(row:GetAttribute("AnimName") or "")
                local searchLower = string.lower(CurrentSearchText)

                local exactMatch = name == searchLower
                local startsWithMatch = name:sub(1, #searchLower) == searchLower

                if exactMatch then
                    match = match and true
                    row:SetAttribute("SearchPriority", 1)
                elseif startsWithMatch then
                    match = match and true
                    local nextChar = name:sub(#searchLower + 1, #searchLower + 1) or ""
                    if nextChar:match("[a-z]") then
                        row:SetAttribute("SearchPriority", 2)
                    elseif nextChar == " " then
                        row:SetAttribute("SearchPriority", 3)
                    elseif nextChar:match("%d") then
                        row:SetAttribute("SearchPriority", 4)
                    elseif nextChar ~= "" then
                        row:SetAttribute("SearchPriority", 5)
                    end
                else
                    match = false
                    row:SetAttribute("SearchPriority", nil)
                end
            else
                row:SetAttribute("SearchPriority", nil)
            end

            row:SetAttribute("SearchMatch", match)
            row.LayoutOrder = 0
        end
    end

    if CurrentSearchText ~= "" then
        local rows = {}
        for _, row in pairs(StolenItemsContainer:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("SearchMatch") then
                table.insert(rows, row)
            end
        end

        local searchLower = string.lower(CurrentSearchText)

        table.sort(rows, function(a, b)
            local prioA = a:GetAttribute("SearchPriority") or 999
            local prioB = b:GetAttribute("SearchPriority") or 999

            if prioA ~= prioB then
                return prioA < prioB
            end

            local nameA = string.lower(a:GetAttribute("AnimName") or "")
            local nameB = string.lower(b:GetAttribute("AnimName") or "")

            if prioA >= 2 and prioA <= 5 then
                local nextCharA = nameA:sub(#searchLower + 1, #searchLower + 1) or ""
                local nextCharB = nameB:sub(#searchLower + 1, #searchLower + 1) or ""

                if nextCharA ~= nextCharB then
                    if prioA == 2 then
                        return nextCharA < nextCharB
                    elseif prioA == 3 then
                        return nameA < nameB
                    elseif prioA == 4 then
                        return nextCharA < nextCharB
                    elseif prioA == 5 then
                        return nameA < nameB
                    end
                end
            end

            return nameA < nameB
        end)

        for i, row in ipairs(rows) do
            row.LayoutOrder = i
        end
    else
        local rows = {}
        for _, row in pairs(StolenItemsContainer:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("SearchMatch") then
                table.insert(rows, row)
            end
        end

        table.sort(rows, function(a, b)
            return AlphaNumericSort(
                { Name = a:GetAttribute("AnimName") or "" },
                { Name = b:GetAttribute("AnimName") or "" }
            )
        end)

        for i, row in ipairs(rows) do
            row.LayoutOrder = i
        end
    end

    RecalculatePagination()

    if Pagination.total > 0 then
        if Pagination.current > Pagination.total then
            Pagination.current = Pagination.total
        end
        if Pagination.current < 1 then
            Pagination.current = 1
        end
    else
        Pagination.current = 1
    end

    ShowPage(Pagination.current)

    if PageControlFrame then
        local group = PageControlFrame:FindFirstChild("PageControls")
        if group then
            local indicator = group:FindFirstChild("Indicator")
            if indicator then
                if Pagination.total > 0 then
                    indicator.Text = "Page\n" .. Pagination.current .. " / " .. Pagination.total
                else
                    indicator.Text = "Page\n0 / 0"
                end
            end

            local pageBox = group:FindFirstChild("PageBox")
            if pageBox then
                pageBox.Text = tostring(Pagination.current)
            end

            local fileInd = group:FindFirstChild("FileIndicator")
            if fileInd then
                local totalRows = 0
                for _, set in ipairs(Pagination.pages) do
                    totalRows = totalRows + #set
                end
                if totalRows > 0 then
                    local endIndex = math.min(Pagination.current * ITEMS_PER_PAGE, totalRows)
                    fileInd.Text = "File\n" .. endIndex .. " / " .. totalRows
                else
                    fileInd.Text = "File\n0 / 0"
                end
            end
        end
    end
end

local function CreatePageControls()
    local group = Instance.new("Frame")
    group.Name = "PageControls"
    group.Size = UDim2.new(1, 0, 1, 0)
    group.BackgroundTransparency = 1
    group.Parent = PageControlFrame

    local totalW = ListWidth
    local h = ControlRowHeight

    local wBtn = math.floor(totalW * 0.10)
    local wBox = math.floor(totalW * 0.12)
    local wText = math.floor(totalW * 0.22)
    local wFile = math.floor(totalW * 0.22)

    local x = 0

    local function MakeBtn(name, txt)
        local b = CreateInteractable(
            UDim2.new(0, wBtn, 1, 0),
            name,
            txt,
            Grey,
            true,
            "TextButton",
            group
        )
        b.Position = UDim2.new(0, x, 0, 0)
        x += wBtn + 4
        return b
    end

    local firstBtn = MakeBtn("First", "|<")
    local lastBtn = MakeBtn("Last", ">|")

    local pageBox = CreateInteractable(
        UDim2.new(0, wBox, 1, 0),
        "PageBox",
        "",
        Grey,
        false,
        "TextBox",
        group
    )
    pageBox.Position = UDim2.new(0, x, 0, 0)
    pageBox.Text = tostring(Pagination.current)
    pageBox.ClearTextOnFocus = false
    x += wBox + 4

    local indicator = Instance.new("TextLabel")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(0, wText, 1, 0)
    indicator.Position = UDim2.new(0, x, 0, 0)
    indicator.Text = "Page " .. tostring(Pagination.current) .. " / " .. tostring(Pagination.total)
    indicator.BackgroundTransparency = 1
    indicator.TextColor3 = Color3.new(1,1,1)
    indicator.TextScaled = true
    indicator.TextXAlignment = Enum.TextXAlignment.Left
    indicator.Parent = group
    x += wText + 4

    local backBtn = MakeBtn("Back", "<")
    local nextBtn = MakeBtn("Next", ">")

    local fileInd = Instance.new("TextLabel")
    fileInd.Name = "FileIndicator"
    fileInd.Size = UDim2.new(0, wFile, 1, 0)
    fileInd.Position = UDim2.new(1, -wFile, 0, 0)
    fileInd.Text = "File 0/0"
    fileInd.BackgroundTransparency = 1
    fileInd.TextColor3 = Color3.new(1,1,1)
    fileInd.TextScaled = true
    fileInd.TextXAlignment = Enum.TextXAlignment.Right
    fileInd.Parent = group

    return group, firstBtn, lastBtn, backBtn, nextBtn, pageBox, indicator, fileInd
end



local function SetupWindow()
    ScreenGui.Name = "MyAnimationHub"
    ScreenGui.Parent = PlayerGui
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    MainFrame.Name = "HubMainFrame"
    MainFrame.Size = UDim2.new(0, WindowWidth, 0, WindowHeight)
    MainFrame.Position = UDim2.new(0, 100, 0, 100)
    MainFrame.BackgroundTransparency = 0
    MainFrame.Parent = ScreenGui

    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

    Panel.Name = "PanelContainer"
    Panel.Size = UDim2.new(1, 0, 1, 0)
    Panel.Position = UDim2.new(0, 0, 0, 0)
    Panel.BackgroundColor3 = Color3.fromRGB(18,18,18)
    Panel.BorderSizePixel = 0
    Panel.Parent = MainFrame

    Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)

    StolenAnimationsFrame, StolenItemsContainer = CreateListFrame("StolenTabFrame")
    StolenAnimationsFrame.Visible = true

    local DragBar = Instance.new("TextButton")
    DragBar.Text = "AnimSnatcher"
    DragBar.TextColor3 = Color3.new(1,1,1)
    DragBar.AutoButtonColor = false
    DragBar.Size = UDim2.new(1, -5, 0, HeaderSize)
    DragBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    DragBar.Position = UDim2.new(0, 0, 0, 0)
    DragBar.Parent = Panel
    DragBar.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", DragBar)
    Instance.new("UIPadding", DragBar).PaddingLeft = UDim.new(0, 8)

    local CloseButton = Instance.new("TextButton")
    CloseButton.Text = "X"
    CloseButton.Size = UDim2.new(0, HeaderSize, 0, HeaderSize)
    CloseButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    CloseButton.Position = UDim2.new(1, -HeaderSize, 0, 0)
    CloseButton.Parent = DragBar
    Instance.new("UICorner", CloseButton)

    local MinimizeButton = Instance.new("TextButton")
    MinimizeButton.Text = "-"
    MinimizeButton.Size = UDim2.new(0, HeaderSize, 0, HeaderSize)
    MinimizeButton.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
    MinimizeButton.Position = UDim2.new(1, -(HeaderSize * 2), 0, 0)
    MinimizeButton.Parent = DragBar
    Instance.new("UICorner", MinimizeButton)

    local RestoreButton = Instance.new("TextButton")
    RestoreButton.Text = "AnimSnatcher"
    RestoreButton.TextColor3 = Color3.new(1,1,1)
    RestoreButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    RestoreButton.Size = UDim2.new(0, 50, 0, 50)
    RestoreButton.Position = UDim2.new(1, -60, 0, 10)
    RestoreButton.AutoButtonColor = false
    RestoreButton.Visible = false
    RestoreButton.Parent = ScreenGui
    Instance.new("UICorner", RestoreButton)

    local ButtonsRow = Instance.new("Frame")
    ButtonsRow.Name = "ButtonsRow"
    ButtonsRow.Size = UDim2.new(0, ListWidth, 0, ControlRowHeight)
    ButtonsRow.Position = UDim2.new(0, 0, 0, HeaderSize)
    ButtonsRow.BackgroundTransparency = 1
    ButtonsRow.Parent = Panel

    local EStopButton = CreateInteractable(UDim2.new(0, math.floor(ListWidth/4), 0, ControlRowHeight), "EStop", "E-Stop", Grey, true, "TextButton", ButtonsRow)
    EStopButton.Position = UDim2.new(0, 0, 0, 0)

    local StealButton = CreateInteractable(UDim2.new(0, math.floor(ListWidth/4), 0, ControlRowHeight), "Steal", "Steal", Grey, true, "TextButton", ButtonsRow)
    StealButton.Position = UDim2.new(0, math.floor(ListWidth/4), 0, 0)

    local CopyMyAnimButton = CreateInteractable(UDim2.new(0, math.floor(ListWidth/4), 0, ControlRowHeight), "CopyMyAnim", "CopyMe", Grey, true, "TextButton", ButtonsRow)
    CopyMyAnimButton.Position = UDim2.new(0, 2*math.floor(ListWidth/4), 0, 0)

    local DeleteButton = CreateInteractable(UDim2.new(0, math.floor(ListWidth/4), 0, ControlRowHeight), "Delete", "Delete (Stolen)", Grey, true, "TextButton", ButtonsRow)
    DeleteButton.Position = UDim2.new(0, 3*math.floor(ListWidth/4), 0, 0)

    local SearchRow = Instance.new("Frame")
    SearchRow.Name = "SearchRow"
    SearchRow.Size = UDim2.new(0, ListWidth, 0, ControlRowHeight)
    SearchRow.Position = UDim2.new(0, 0, 0, HeaderSize + ControlRowHeight)
    SearchRow.BackgroundTransparency = 1
    SearchRow.Parent = Panel

    Searchbar = CreateInteractable(UDim2.new(1, -23, 0, ControlRowHeight), "Searchbar", "Search", Grey, false, "TextBox", SearchRow)
    Searchbar.PlaceholderColor3 = Color3.fromRGB(180, 180, 180)
    Searchbar.ClearTextOnFocus = false
    Searchbar.Position = UDim2.new(0, 0, 0, 0)

    local ClearSearchButton = Instance.new("TextButton")
    ClearSearchButton.Name = "ClearSearch"
    ClearSearchButton.Size = UDim2.new(0, 23, 0, ControlRowHeight)
    ClearSearchButton.Position = UDim2.new(1, -23, 0, 0)
    ClearSearchButton.BackgroundColor3 = Color3.fromRGB(150, 70, 70)
    ClearSearchButton.BorderSizePixel = 0
    ClearSearchButton.Text = "X"
    ClearSearchButton.TextColor3 = Color3.new(1, 1, 1)
    ClearSearchButton.TextScaled = true
    ClearSearchButton.Visible = true
    ClearSearchButton.Parent = SearchRow

    Instance.new("UICorner", Searchbar)
    Instance.new("UICorner", ClearSearchButton)

    local DropdownFrame = Instance.new("Frame")
    DropdownFrame.Name = "DropdownFrame"
    DropdownFrame.Size = UDim2.new(1, 0, 0, TabRowHeight)
    DropdownFrame.Position = UDim2.new(0, 0, 0, HeaderSize + ControlRowHeight * 2 - 2)
    DropdownFrame.BackgroundTransparency = 1
    DropdownFrame.Parent = Panel
    DropdownFrame.ZIndex = 200

    DropdownButton = Instance.new("TextButton")
    DropdownButton.Name = "DropdownButton"
    DropdownButton.Size = UDim2.new(1, 0, 0, TabRowHeight)
    DropdownButton.Position = UDim2.new(0, 0, 0, 0)
    DropdownButton.BackgroundColor3 = Grey
    DropdownButton.Text = "All v"
    DropdownButton.TextColor3 = Color3.new(1,1,1)
    DropdownButton.TextScaled = true
    Instance.new("UICorner", DropdownButton)
    DropdownButton.Parent = DropdownFrame
    DropdownButton.ZIndex = 210

    DropdownList = Instance.new("ScrollingFrame")
    DropdownList.Name = "DropdownList"
    DropdownList.Size = UDim2.new(1, 0, 0, 80)
    DropdownList.Position = UDim2.new(0, 0, 0, TabRowHeight)
    DropdownList.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    DropdownList.BackgroundTransparency = 0.5
    DropdownList.BorderSizePixel = 0
    DropdownList.Visible = false
    DropdownList.CanvasSize = UDim2.new(0, 0, 0, 0)
    DropdownList.ScrollBarThickness = 4
    DropdownList.ScrollingEnabled = true
    DropdownList.ElasticBehavior = Enum.ElasticBehavior.Never
    DropdownList.ScrollBarImageTransparency = 0.7
    DropdownList.Parent = DropdownFrame
    DropdownList.ZIndex = 220

    local DropdownLayout = Instance.new("UIListLayout")
    DropdownLayout.FillDirection = Enum.FillDirection.Vertical
    DropdownLayout.SortOrder = Enum.SortOrder.LayoutOrder
    DropdownLayout.Padding = UDim.new(0, 1)
    DropdownLayout.Parent = DropdownList

    DropdownLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        DropdownList.CanvasSize = UDim2.new(0, 0, 0, DropdownLayout.AbsoluteContentSize.Y)
        DropdownList.Size = UDim2.new(1, 0, 0, math.min(80, DropdownLayout.AbsoluteContentSize.Y))
    end)

    CreateDropdownItem("All")
    CreateDropdownItem("Favorite")
    CreateDropdownItem("Emote")
    CreateDropdownItem("New")

    PageControlFrame = Instance.new("Frame")
    PageControlFrame.Name = "PageControlFrame"
    PageControlFrame.Size = UDim2.new(0, ListWidth, 0, ControlRowHeight)
    PageControlFrame.Position = UDim2.new(0, 0, 0, HeaderSize + (ControlRowHeight * 2) + TabRowHeight + ListHeight)
    PageControlFrame.BackgroundTransparency = 1
    PageControlFrame.BackgroundColor3 = Color3.fromRGB(22,22,22)
    PageControlFrame.Parent = Panel

    NowPlayingFrame = Instance.new("Frame")
    NowPlayingFrame.Name = "NowPlayingFrame"
    NowPlayingFrame.Size = UDim2.new(0, ListWidth, 0, NowPlayingHeight)
    NowPlayingFrame.Position = UDim2.new(0, 0, 1, -NowPlayingHeight)
    NowPlayingFrame.BackgroundTransparency = 1
    NowPlayingFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Instance.new("UICorner", NowPlayingFrame)
    NowPlayingFrame.Parent = Panel
    NowPlayingFrame.Visible = true

    NowPlayingLabel = Instance.new("TextLabel")
    NowPlayingLabel.BackgroundTransparency = 1
    NowPlayingLabel.Size = UDim2.new(0.55, 0, 1, 0)
    NowPlayingLabel.Position = UDim2.new(0, 5, 0, 0)
    NowPlayingLabel.TextColor3 = Color3.new(1,1,1)
    NowPlayingLabel.TextXAlignment = Enum.TextXAlignment.Left
    NowPlayingLabel.TextScaled = true
    NowPlayingLabel.Font = Enum.Font.SourceSans
    NowPlayingLabel.Text = "Now Playing:"
    NowPlayingLabel.Parent = NowPlayingFrame

    NowPlayingSpeedBox = Instance.new("TextBox")
    NowPlayingSpeedBox.Size = UDim2.new(0, 40, 0.8, 0)
    NowPlayingSpeedBox.Position = UDim2.new(0.55, 0, 0.1, 0)
    NowPlayingSpeedBox.BackgroundColor3 = Grey
    NowPlayingSpeedBox.Text = "1"
    NowPlayingSpeedBox.TextScaled = true
    NowPlayingSpeedBox.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", NowPlayingSpeedBox)
    NowPlayingSpeedBox.Parent = NowPlayingFrame

    NowPlayingStopButton = Instance.new("TextButton")
    NowPlayingStopButton.Size = UDim2.new(0, 50, 0.8, 0)
    NowPlayingStopButton.Position = UDim2.new(0.55 + 40/ListWidth, 5, 0.1, 0)
    NowPlayingStopButton.Text = "Stop"
    NowPlayingStopButton.BackgroundColor3 = Red
    NowPlayingStopButton.TextScaled = true
    NowPlayingStopButton.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", NowPlayingStopButton)
    NowPlayingStopButton.Parent = NowPlayingFrame

    return DragBar, CloseButton, MinimizeButton, RestoreButton, EStopButton, StealButton, CopyMyAnimButton, DeleteButton, ClearSearchButton
end


local function ShowConfirm(message, onYes)
    local overlay = Instance.new("Frame")
    overlay.Name = "ConfirmOverlay"
    overlay.Size = UDim2.new(1,0,1,0)
    overlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
    overlay.BackgroundTransparency = 1
    overlay.ZIndex = 99999
    overlay.Parent = ScreenGui
    overlay.Active = true
    local box = Instance.new("Frame")
    box.Size = UDim2.new(0,260,0,120)
    box.Position = UDim2.new(0.5,-130,0.5,-60)
    box.BackgroundColor3 = Color3.fromRGB(45,45,45)
    box.ZIndex = 100000
    Instance.new("UICorner", box)
    box.Parent = overlay
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-20,0.5,-10)
    label.Position = UDim2.new(0,10,0,10)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1,1,1)
    label.Text = message
    label.TextWrapped = true
    label.TextScaled = true
    label.ZIndex = 100001
    label.Parent = box
    local yes = Instance.new("TextButton")
    yes.Size = UDim2.new(0.45,-10,0.3,0)
    yes.Position = UDim2.new(0.05,0,0.6,0)
    yes.BackgroundColor3 = Color3.fromRGB(0,170,0)
    yes.Text = "Yes"
    yes.TextColor3 = Color3.new(1,1,1)
    yes.ZIndex = 100001
    Instance.new("UICorner", yes)
    yes.Parent = box
    local no = Instance.new("TextButton")
    no.Size = UDim2.new(0.45,-10,0.3,0)
    no.Position = UDim2.new(0.5,0,0.6,0)
    no.BackgroundColor3 = Color3.fromRGB(170,0,0)
    no.Text = "Cancel"
    no.TextColor3 = Color3.new(1,1,1)
    no.ZIndex = 100001
    Instance.new("UICorner", no)
    no.Parent = box
    local function cleanup()
        overlay:Destroy()
    end
    yes.MouseButton1Click:Connect(function()
        cleanup()
        if onYes then onYes() end
    end)
    no.MouseButton1Click:Connect(function()
        cleanup()
    end)
end

local function CheckForOwnedAnimations(ID, PlayIt)
    local normalized = NormalizeAnimId(ID)
    if not normalized then return false end
    for _, data in pairs(StolenList) do
        if NormalizeAnimId(data.ID) == normalized then
            if PlayIt then PlayAnimation(normalized, "1") end
            return true
        end
    end
    for _, row in pairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") then
            local rid = row:GetAttribute("AnimId")
            if rid and NormalizeAnimId(rid) == normalized then
                if PlayIt then PlayAnimation(normalized, "1") end
                return true
            end
        end
    end
    if PlayIt then PlayAnimation(normalized, "1") end
    return false
end

local function updateBadgeUI(animId, colorIndex)
    animId = NormalizeAnimId(animId)
    if not animId then return end
    for _, row in ipairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") and row:GetAttribute("AnimId") == animId then
            local playBtn = row:FindFirstChildWhichIsA("TextButton")
            if not playBtn then return end
            local lbl = playBtn:FindFirstChild("Label")
            if not lbl then return end
            local base = row:GetAttribute("AnimName") or lbl.Text
            lbl.Text = base
            lbl.TextColor3 = Color3.new(1,1,1)
            local newTag = playBtn:FindFirstChild("NewTag")
            if colorIndex then
                if not newTag then
                    newTag = Instance.new("TextLabel")
                    newTag.Name = "NewTag"
                    newTag.Parent = playBtn
                    newTag.BackgroundTransparency = 1
                    newTag.BorderSizePixel = 0
                    newTag.Font = Enum.Font.GothamBold
                    newTag.TextSize = lbl.TextSize + 10
                    newTag.Text = "New"
                    newTag.TextXAlignment = Enum.TextXAlignment.Right
                    newTag.TextYAlignment = Enum.TextYAlignment.Center
                    newTag.AnchorPoint = Vector2.new(1, 0.5)
                    newTag.Position = UDim2.new(1, 8, 0.5, 0)
                    newTag.Size = UDim2.new(0, 50, 1, 0)
                end
                if colorIndex == 1 then
                    newTag.TextColor3 = Color3.fromRGB(255, 215, 0)
                elseif colorIndex == 2 then
                    newTag.TextColor3 = Color3.fromRGB(255, 235, 120)
                elseif colorIndex == 3 then
                    newTag.TextColor3 = Color3.fromRGB(255, 255, 255)
                elseif colorIndex == 4 then
                    newTag.TextColor3 = Color3.fromRGB(255, 180, 80)
                elseif colorIndex == 5 then
                    newTag.TextColor3 = Color3.fromRGB(255, 255, 120)
                elseif colorIndex == 6 then
                    newTag.TextColor3 = Color3.fromRGB(120, 200, 255)
                elseif colorIndex == 7 then
                    newTag.TextColor3 = Color3.fromRGB(120, 255, 180)
                end
                newTag.Visible = true
            else
                if newTag then 
                    newTag:Destroy() 
                end
            end
        end
    end
end

local function addNewBadge(animId)
    local normalized = NormalizeAnimId(animId)
    if not normalized then return end
    NewBadgeTimers[normalized] = os.time() + 600
    
    for _, row in ipairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") and row:GetAttribute("AnimId") == normalized then
            row:SetAttribute("IsNew", true)
        end
    end
    
    if ActiveDropdownFilter == "New" then
        UpdateFilteredRows()
    end
    
    task.spawn(function()
        local expire = os.time() + 1200
        local colorIndex = 1
        local bounce = 0
        local glow = 0
        local glowInc = 0.06
        

        while os.time() < expire and ScreenGui and ScreenGui.Parent do
            if not NewBadgeTimers[normalized] then break end
            
            updateBadgeUI(normalized, colorIndex)
            colorIndex = (colorIndex % 7) + 1
            
            for _, row in ipairs(StolenItemsContainer:GetChildren()) do
                if row:IsA("Frame") and row:GetAttribute("AnimId") == normalized then
                    local playBtn = row:FindFirstChildWhichIsA("TextButton")
                    if playBtn then
                        local tag = playBtn:FindFirstChild("NewTag")
                        if tag then
                            local floatPos = (bounce == 0) and -2 or 0
                            TweenService:Create(
                                tag,
                                TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                                { Position = UDim2.new(1, 8, 0.5, floatPos) }
                            ):Play()
                        end
                    end
                end
            end
            
            bounce = 1 - bounce
            glow += glowInc
            if glow > 0.25 then glowInc = -glowInc end
            if glow < 0   then glowInc = -glowInc end
            
            for _, row in ipairs(StolenItemsContainer:GetChildren()) do
                if row:IsA("Frame") and row:GetAttribute("AnimId") == normalized then
                    local playBtn = row:FindFirstChildWhichIsA("TextButton")
                    if playBtn then
                        local tag = playBtn:FindFirstChild("NewTag")
                        if tag then
                            TweenService:Create(
                                tag,
                                TweenInfo.new(0.4, Enum.EasingStyle.Sine),
                                { TextTransparency = 0.15 + glow }
                            ):Play()
                        end
                    end
                end
            end
            
            task.wait(0.6)
        end
        

        if ScreenGui and ScreenGui.Parent then
            updateBadgeUI(normalized, nil)
            
            for _, row in ipairs(StolenItemsContainer:GetChildren()) do
                if row:IsA("Frame") and row:GetAttribute("AnimId") == normalized then
                    row:SetAttribute("IsNew", false)
                end
            end
        end
        
        NewBadgeTimers[normalized] = nil
        

        if ScreenGui and ScreenGui.Parent and ActiveDropdownFilter == "New" then
            UpdateFilteredRows()
        end
    end)
end

local function SelectDropdownItem(filterName)
    TabStates[ActiveDropdownFilter].page = Pagination.current
    TabStates[ActiveDropdownFilter].search = CurrentSearchText
    
    ActiveDropdownFilter = filterName
    DropdownList.Visible = false

    if filterName == "All" then
        DropdownButton.Text = "All v"
    elseif filterName == "Favorite" then
        DropdownButton.Text = "Favorite v"
    elseif filterName == "Emote" then
        DropdownButton.Text = "Emote v"
    elseif filterName == "New" then
        DropdownButton.Text = "New v"
    end
    
    CurrentSearchText = TabStates[filterName].search or ""
    Searchbar.Text = CurrentSearchText
    
    if CurrentSearchText ~= "" then
        Pagination.current = 1
    else
        Pagination.current = TabStates[filterName].page or 1
    end
    
    UpdateFilteredRows()
    StolenItemsContainer.CanvasPosition = Vector2.new(0, 0)
end

local function DeleteStolenById(animIdNormalized)
    animIdNormalized = NormalizeAnimId(animIdNormalized)
    if not animIdNormalized then return end
    

    if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") and PlayingId == animIdNormalized then
        pcall(function()
            if Track.IsPlaying then Track:Stop() end
        end)
        Track = nil
        PlayingId = 0
    end
    

    for i = #StolenList, 1, -1 do
        local entryId = NormalizeAnimId(StolenList[i].ID)
        if entryId == animIdNormalized then
            table.remove(StolenList, i)
        end
    end
    
    SafeWriteStolen()
    

    if FavoriteList[animIdNormalized] then
        FavoriteList[animIdNormalized] = nil
        SaveFavorites()
    end
    

    if EmoteList[animIdNormalized] then
        EmoteList[animIdNormalized] = nil
        SaveEmotes()
    end
    

    if NewBadgeTimers[animIdNormalized] then
        NewBadgeTimers[animIdNormalized] = nil
    end
    

    for _, row in pairs(StolenItemsContainer:GetChildren()) do
        if row:IsA("Frame") then
            local rid = row:GetAttribute("AnimId")
            if rid and NormalizeAnimId(rid) == animIdNormalized then
                row:Destroy()
            end
        end
    end
    

    if CurrentSearchText == "" then
        Pagination.current = TabStates[ActiveDropdownFilter].page or 1
    end
    
    UpdateFilteredRows()
end


local function CreateStolenRow(name, animIdNum, normalizedID)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, -10, 0, 25)
    Row:SetAttribute("OriginalHeight", Row.Size.Y.Offset)
    Row.BackgroundTransparency = 1
    Row.BorderSizePixel = 0
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding = UDim.new(0, 6)
    layout.Parent = Row
    

    local speedBox = CreateTextbox(UDim2.new(0, 45, 0, 20), Grey, "", normalizedID, Row)
    speedBox.Name = "SpeedBox"
    speedBox.Parent = Row
    speedBox:SetAttribute("AnimId", normalizedID)
    

    local playBtn = CreateButton(
        UDim2.new(0, 120, 0, 23),
        Red,
        name,
        name,
        normalizedID,
        Row
    )
    playBtn.LayoutOrder = 2
    playBtn.Parent = Row
    

    local favBtn = Instance.new("TextButton")
    favBtn.Name = "FavButton"
    favBtn.Size = UDim2.new(0, 25, 0, 25)
    favBtn.BackgroundTransparency = 1
    favBtn.BorderSizePixel = 0
    favBtn.Font = Enum.Font.GothamBold
    favBtn.TextSize = 23 
    favBtn.AutoButtonColor = false
    favBtn.LayoutOrder = 3
    favBtn.Parent = Row
    favBtn:SetAttribute("AnimId", normalizedID)
    

    if FavoriteList[normalizedID] then
        favBtn.Text = STAR_FULL
        favBtn.TextColor3 = Color3.new(1, 1, 0)
    else
        favBtn.Text = STAR_EMPTY
        favBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
    end
    

    local emoteBtn = Instance.new("TextButton")
    emoteBtn.Name = "EmoteButton"
    emoteBtn.Size = UDim2.new(0, 20, 0, 20)
    emoteBtn.BackgroundTransparency = 1
    emoteBtn.BorderSizePixel = 0
    emoteBtn.Font = Enum.Font.GothamBold
    emoteBtn.TextSize = 16 
    emoteBtn.AutoButtonColor = false
    emoteBtn.LayoutOrder = 4
    emoteBtn.Parent = Row
    emoteBtn:SetAttribute("AnimId", normalizedID)
    

    UpdateRowEmoteButton(emoteBtn, normalizedID)
    
    Row.Parent = StolenItemsContainer
    Row:SetAttribute("AnimName", name)
    Row:SetAttribute("AnimId", normalizedID)
    Row:SetAttribute("IsFavorite", FavoriteList[normalizedID] ~= nil)
    Row:SetAttribute("IsEmote", EmoteList[normalizedID] == true)
    Row:SetAttribute("IsNew", NewBadgeTimers[normalizedID] ~= nil)
    
    return Row, playBtn, favBtn, emoteBtn, speedBox
end

local function BindRowEvents(row, playBtn, favBtn, emoteBtn, speedBox, normalizedID, name)
    TextboxSpeedAdjust(speedBox, normalizedID)
    
    playBtn.MouseButton1Click:Connect(function()
        if DeleteMode then
            ShowConfirm("Delete Animation\n"..tostring(name).." ?", function() 
                DeleteStolenById(normalizedID) 
            end)
            return 
        end
        if CursedMode then return end
        if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") then
            pcall(function()
                if Track.IsPlaying then Track:Stop() end
            end)
        end
        if PlayingId == normalizedID and playBtn:GetAttribute("Toggled") then
            playBtn:SetAttribute("Toggled", false)
            playBtn.BackgroundColor3 = Red
            PlayingId = 0
            UpdateNowPlayingUI()
            return
        end
        MassUnToggle(playBtn)
        local speed = speedBox and speedBox.Text or ""
        if speed == "" then speed = "1"
        elseif speed:sub(1,1) == "." then speed = "0" .. speed end
        local ok = pcall(function()
            PlayAnimation(normalizedID, speed)
        end)
        if not ok then return end
        playBtn:SetAttribute("Toggled", true)
        playBtn.BackgroundColor3 = Green
        PlayingId = normalizedID
        if NowPlayingSpeedBox then
            NowPlayingSpeedBox.Text = tostring(speed)
        end
        UpdateNowPlayingUI()
    end)
    
    favBtn.MouseButton1Click:Connect(function()
        if FavoriteList[normalizedID] then
            FavoriteList[normalizedID] = nil
            SaveFavorites()
            favBtn.Text = STAR_EMPTY
            favBtn.TextColor3 = Color3.fromRGB(180,180,180)
            row:SetAttribute("IsFavorite", false)
        else
            FavoriteList[normalizedID] = { 
                Name = name
            }
            SaveFavorites()
            favBtn.Text = STAR_FULL
            favBtn.TextColor3 = Color3.new(1,1,0)
            row:SetAttribute("IsFavorite", true)
        end
        UpdateFilteredRows()
    end)
    
    emoteBtn.MouseButton1Click:Connect(function()
        if EmoteList[normalizedID] then
            EmoteList[normalizedID] = nil
            row:SetAttribute("IsEmote", false)
        else
            EmoteList[normalizedID] = true
            row:SetAttribute("IsEmote", true)
        end
        SaveEmotes()
        UpdateRowEmoteButton(emoteBtn, normalizedID)
        
        if ActiveDropdownFilter == "Emote" then
            UpdateFilteredRows()
        end
    end)
end

local DragBar, CloseButton, MinimizeButton, RestoreButton, EStopButton, StealButton, CopyMyAnimButton, DeleteButton, ClearSearchButton = SetupWindow()
LoadFavorites()
LoadEmotes()
local pageControls, firstBtn, lastBtn, backBtn, nextBtn, pageBox, indicator, fileInd = CreatePageControls()

SelectDropdownItem("All")

task.spawn(function()
    local cam = workspace.CurrentCamera
    if not cam then
        workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
        cam = workspace.CurrentCamera
    end
    cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        local abs = MainFrame.AbsolutePosition
        local size = MainFrame.AbsoluteSize
        local screen = cam.ViewportSize
        local outOfBounds = abs.X + size.X < 0 or abs.Y + size.Y < 0 or abs.X > screen.X or abs.Y > screen.Y
        if outOfBounds then
            MainFrame.Position = UDim2.new(0.5, -size.X/2, 0.5, -size.Y/2)
        end
    end)
end)


MinimizeButton.MouseButton1Click:Connect(function()
    local confirmOverlay = ScreenGui:FindFirstChild("ConfirmOverlay")
    if confirmOverlay then
        confirmOverlay.Visible = false
    end
    
    MainFrame.Visible = false
    RestoreButton.Visible = true
    DeleteMode = false
    StealStage = 0
    StealButton.BackgroundColor3 = Grey
    DeleteButton.BackgroundColor3 = Grey
end)

RestoreButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = true
    RestoreButton.Visible = false
    DeleteMode = false
    StealStage = 0
    StealButton.BackgroundColor3 = Grey
    DeleteButton.BackgroundColor3 = Grey
    
    SelectDropdownItem(ActiveDropdownFilter)
    
    local confirmOverlay = ScreenGui:FindFirstChild("ConfirmOverlay")
    if confirmOverlay then
        confirmOverlay:Destroy()
    end
end)

DragBar.MouseButton1Down:Connect(function()
    local mouse = Player:GetMouse()
    local offsetX = mouse.X - MainFrame.AbsolutePosition.X
    local offsetY = mouse.Y - MainFrame.AbsolutePosition.Y

    local sideGrip   = 100 
    local bottomPeek = 100 
    local topLimit   = -50 

    local conn
    conn = game:GetService("RunService").Heartbeat:Connect(function()
        if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            conn:Disconnect()
            return
        end

        local newX = mouse.X - offsetX
        local newY = mouse.Y - offsetY

        local cam = workspace.CurrentCamera
        local screen = cam.ViewportSize
        local frame = MainFrame.AbsoluteSize


        if newY < topLimit then
            newY = topLimit
        end


        local maxY = screen.Y - bottomPeek
        if newY > maxY then
            newY = maxY
        end


        newX = math.max(newX, -frame.X + sideGrip)
        newX = math.min(newX, screen.X - sideGrip)

        MainFrame.Position = UDim2.new(0, newX, 0, newY)
    end)
end)

CloseButton.MouseButton1Click:Connect(function()
    ShowConfirm("Close AnimSnatcher?\nThe currently playing animation will be stopped.", function()
        DeleteMode = false
        StealStage = 0
        

        NewBadgeTimers = {}
        
        if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") then
            pcall(function()
                if Track.IsPlaying then
                    Track:Stop()
                end
            end)
            Track = nil
        end
        
        if ScreenGui then
            ScreenGui:Destroy()
        end
    end)
end)

EStopButton.MouseButton1Click:Connect(function() 
    StopAllAnimations()
    UpdateNowPlayingUI()
    EStopButton.BackgroundColor3 = Red
    task.wait(0.5)
    EStopButton.BackgroundColor3 = Grey
end)

NowPlayingStopButton.MouseButton1Click:Connect(function() 
    StopAllAnimations()
    UpdateNowPlayingUI()
end)

NowPlayingSpeedBox.FocusLost:Connect(function()
    local newSpeed = tonumber(NowPlayingSpeedBox.Text)
    if not newSpeed or newSpeed <= 0 then newSpeed = 1; NowPlayingSpeedBox.Text = "1" end
    if Track and typeof(Track) == "Instance" and Track:IsA("AnimationTrack") and Track.IsPlaying then
        pcall(function() Track:AdjustSpeed(newSpeed) end)
    end
    SyncAllSpeedBoxes(PlayingId, newSpeed)
    SaveSpeed(PlayingId, newSpeed)
end)

StealButton.MouseButton1Click:Connect(function()
    if StealStage == 0 then
        StealStage = 1
        StealButton.BackgroundColor3 = Green
        print("Steal mode ON")
    else
        StealStage = 0
        StealButton.BackgroundColor3 = Grey
        print("Steal mode OFF")
    end
end)

CopyMyAnimButton.MouseButton1Click:Connect(function()
    CopyMyAnimButton.BackgroundColor3 = Green
    task.wait(0.1)
    local Character = Player.Character
    if not Character then return end
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return end
    local copiedCount = 0
    for _, localTrack in pairs(Humanoid:GetPlayingAnimationTracks()) do
        local animId = localTrack.Animation and localTrack.Animation.AnimationId
        local normalized = NormalizeAnimId(animId)
        if normalized and not CheckForOwnedAnimations(normalized, false) then
            local numeric = tonumber(normalized:match("%d+"))
            local success, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, numeric)
            local name = "My Animation"
            if success and info and info.Name then name = info.Name end
            local lowerName = string.lower(name)
            if not (lowerName:find("idle") or lowerName:find("walk") or lowerName:find("run")) then

                local row, playBtn, favBtn, emoteBtn, speedBox = CreateStolenRow(name, numeric, normalized)

                BindRowEvents(row, playBtn, favBtn, emoteBtn, speedBox, normalized, name)
                table.insert(StolenList, { Name = name, ID = normalized, animId = numeric })
                addNewBadge(normalized)
                copiedCount = copiedCount + 1
            end
        end
    end
    if copiedCount > 0 then SafeWriteStolen() end
    UpdateFilteredRows()
    
    task.wait(0.3)
    CopyMyAnimButton.BackgroundColor3 = Grey
end)

DeleteButton.MouseButton1Click:Connect(function()
    DeleteMode = not DeleteMode
    if DeleteMode then DeleteButton.BackgroundColor3 = Color3.fromRGB(255,70,70)
    else DeleteButton.BackgroundColor3 = Grey end
end)

ClearSearchButton.MouseButton1Click:Connect(function()
    if Searchbar.Text ~= "" then 
        Searchbar.Text = ""
        CurrentSearchText = ""
        Pagination.current = TabStates[ActiveDropdownFilter].page or 1
        UpdateFilteredRows()
    end
end)

local searchToken = 0

Searchbar:GetPropertyChangedSignal("Text"):Connect(function()
    searchToken += 1
    local myToken = searchToken
    
    task.delay(0.25, function()
        if myToken ~= searchToken then return end
        if not Searchbar or not Searchbar.Parent then return end
        
        local searchText = Searchbar.Text or ""
        local oldSearch = CurrentSearchText
        CurrentSearchText = string.lower(searchText)
        
        if (oldSearch == "" and CurrentSearchText ~= "") or 
           (oldSearch ~= "" and CurrentSearchText ~= "" and oldSearch ~= CurrentSearchText) then
            Pagination.current = 1
        elseif oldSearch ~= "" and CurrentSearchText == "" then
            Pagination.current = TabStates[ActiveDropdownFilter].page or 1
        end
        
        UpdateFilteredRows()
        StolenItemsContainer.CanvasPosition = Vector2.new(0, 0)
    end)
end)

DropdownButton.MouseButton1Click:Connect(function()
    DropdownList.Visible = not DropdownList.Visible
end)

for _, item in ipairs(DropdownList:GetChildren()) do
    if item:IsA("TextButton") then
        item.MouseButton1Click:Connect(function()
            SelectDropdownItem(item.Text)
        end)
    end
end

firstBtn.MouseButton1Click:Connect(function()
    Pagination.current = 1

    if CurrentSearchText == "" then
        TabStates[ActiveDropdownFilter].page = 1
    end
    UpdateFilteredRows()
end)

lastBtn.MouseButton1Click:Connect(function()
    Pagination.current = Pagination.total

    if CurrentSearchText == "" then
        TabStates[ActiveDropdownFilter].page = Pagination.total
    end
    UpdateFilteredRows()
end)

backBtn.MouseButton1Click:Connect(function()
    if Pagination.current > 1 then
        Pagination.current = Pagination.current - 1

        if CurrentSearchText == "" then
            TabStates[ActiveDropdownFilter].page = Pagination.current
        end
        UpdateFilteredRows()
    end
end)

nextBtn.MouseButton1Click:Connect(function()
    if Pagination.current < Pagination.total then
        Pagination.current = Pagination.current + 1

        if CurrentSearchText == "" then
            TabStates[ActiveDropdownFilter].page = Pagination.current
        end
        UpdateFilteredRows()
    end
end)

pageBox.FocusLost:Connect(function()
    local v = tonumber(pageBox.Text)
    if not v then
        pageBox.Text = tostring(Pagination.current)
        return
    end
    v = math.clamp(v, 1, Pagination.total)
    Pagination.current = v

    if CurrentSearchText == "" then
        TabStates[ActiveDropdownFilter].page = v
    end
    UpdateFilteredRows()
end)

UserInputService.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and StealStage == 1 then

        local mouse = Player:GetMouse()
        local guiPos = MainFrame.AbsolutePosition
        local guiSize = MainFrame.AbsoluteSize
        
        if mouse.X >= guiPos.X and mouse.X <= guiPos.X + guiSize.X and
           mouse.Y >= guiPos.Y and mouse.Y <= guiPos.Y + guiSize.Y then

            return
        end
        

        local pos = Mouse.Hit.Position
        local character = GetNearestCharacter(pos)
        if not character then return end
        local Humanoid = character:FindFirstChildOfClass("Humanoid")
        if not Humanoid then return end
        for _, TheirTrack in pairs(Humanoid:GetPlayingAnimationTracks()) do
            local ID = TheirTrack.Animation and TheirTrack.Animation.AnimationId
            local normalized = NormalizeAnimId(ID)
            local animIdNum = normalized and tonumber(normalized:match("%d+"))
            if animIdNum then
                local success, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, animIdNum)
                if success and info and info.Name then
                    local lowerName = string.lower(info.Name)
                    if not (lowerName:find("idle") or lowerName:find("walk") or lowerName:find("run")) then
                        if TheirTrack.Length ~= 0 and not CheckForOwnedAnimations(normalized, false) then
                            local row, playBtn, favBtn, emoteBtn, speedBox = CreateStolenRow(info.Name, animIdNum, normalized)
                            BindRowEvents(row, playBtn, favBtn, emoteBtn, speedBox, normalized, info.Name)
                            table.insert(StolenList, { Name = info.Name, ID = normalized, animId = animIdNum })
                            addNewBadge(normalized)
                            SafeWriteStolen()
                            StealStage = 0
                            UpdateFilteredRows()
                            break
                        end
                    end
                end
            end
        end
    end
end)

SafeReadStolenList()
table.sort(StolenList, AlphaNumericSort)

for _, data in pairs(StolenList) do
    local normalized = NormalizeAnimId(data.ID)
    local animNum = data.animId or (normalized and tonumber(normalized:match("%d+")))
    if normalized and animNum then
        local row, playBtn, favBtn, emoteBtn, speedBox = CreateStolenRow(data.Name, animNum, normalized)
        BindRowEvents(row, playBtn, favBtn, emoteBtn, speedBox, normalized, data.Name)
        

        if EmoteList[normalized] then
            row:SetAttribute("IsEmote", true)
            UpdateRowEmoteButton(emoteBtn, normalized)
        end
    end
end

for id, fav in pairs(FavoriteList) do
    local normalized = NormalizeAnimId(id)
    if normalized then
        for _, row in pairs(StolenItemsContainer:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("AnimId") == normalized then
                row:SetAttribute("IsFavorite", true)
                
                local favBtn = row:FindFirstChild("FavButton")
                if favBtn then
                    favBtn.Text = STAR_FULL
                    favBtn.TextColor3 = Color3.new(1,1,0)
                end
            end
        end
    end
end

for _, row in pairs(StolenItemsContainer:GetChildren()) do
    if row:IsA("Frame") then
        local animId = row:GetAttribute("AnimId")
        row:SetAttribute("IsEmote", EmoteList[animId] == true)
        

        local emoteBtn = row:FindFirstChild("EmoteButton")
        if not emoteBtn then

            emoteBtn = Instance.new("TextButton")
            emoteBtn.Name = "EmoteButton"
            emoteBtn.Size = UDim2.new(0,22,0,22)
            emoteBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            emoteBtn.BackgroundTransparency = 0
            emoteBtn.BorderSizePixel = 1
            emoteBtn.BorderColor3 = Color3.fromRGB(80, 80, 80)
            emoteBtn.Font = Enum.Font.GothamBold
            emoteBtn.TextSize = 16
            emoteBtn.AutoButtonColor = false
            emoteBtn.LayoutOrder = 4
            emoteBtn.Parent = row
            emoteBtn:SetAttribute("AnimId", animId)
            Instance.new("UICorner", emoteBtn)
            

            emoteBtn.MouseButton1Click:Connect(function()
                if EmoteList[animId] then
                    EmoteList[animId] = nil
                    row:SetAttribute("IsEmote", false)
                else
                    EmoteList[animId] = true
                    row:SetAttribute("IsEmote", true)
                end
                SaveEmotes()
                UpdateRowEmoteButton(emoteBtn, animId)
                
                if ActiveDropdownFilter == "Emote" then
                    UpdateFilteredRows()
                end
            end)
        end
        
        UpdateRowEmoteButton(emoteBtn, animId)
    end
end

UpdateFilteredRows()
print("AnimSnatcher - Loaded Successfully!")