-- 
--   STRAFE TAG  v2  .  full lobby + gamemode system
--   Bridge detection via shared _G key broadcast
--   Lobby opens automatically on load
-- 

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local LP           = Players.LocalPlayer

-- 
--  BRIDGE  - shared _G detection
--  Every client running this script writes to _G.StrafeTagV2
--  We poll it to find other script users in the same session
-- 
local BRIDGE_KEY = "StrafeTagV2"
_G[BRIDGE_KEY] = _G[BRIDGE_KEY] or {}
local bridge = _G[BRIDGE_KEY]

bridge[LP.Name] = {
    player        = LP,
    status        = "idle",
    invite        = nil,
    acceptedFrom  = nil,
}

local function getBridgePeers()
    local peers = {}
    for name, data in pairs(bridge) do
        if name ~= LP.Name and data.player and data.player.Parent then
            table.insert(peers, data)
        end
    end
    return peers
end

-- 
--  SOUNDS
-- 
local SFX = {
    click    = "876939830",
    invite   = "4612378735",
    ready    = "4590662766",
    start    = "1369158752",
    tag_them = "5522091500",
    freeze   = "4612378735",
    win      = "4590662766",
}
local function playSound(id, vol)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. id
    s.Volume  = vol or 1
    s.Parent  = SoundService
    s:Play()
    game:GetService("Debris"):AddItem(s, 4)
end

-- 
--  CONFIG
-- 
local CFG = {
    TAG_DISTANCE  = 7,
    TAG_COOLDOWN  = 2,
    SCAN_INTERVAL = 12,
    SCAN_DURATION = 5,
    ARROW_RADIUS  = 280,
    FREEZE_TIME   = 10,
}

-- 
--  GAME STATE
-- 
local STATE = {
    phase     = "lobby",
    party     = {},
    settings  = { rounds = 1, useTimer = false, timerSecs = 120 },
    itPlayer  = nil,
    itWeights = {},
    roundNum  = 1,
    scores    = {},
}

-- ESP storage
local activeESP     = {}
local skeletonLines = {}
local screenArrows  = {}

-- 
--  COLOUR PALETTE
-- 
local C = {
    bg      = Color3.fromHex("#080808"),
    panel   = Color3.fromHex("#0f0f0f"),
    card    = Color3.fromHex("#141414"),
    stroke  = Color3.fromHex("#222222"),
    accent  = Color3.fromHex("#E8FF00"),
    danger  = Color3.fromHex("#FF3333"),
    safe    = Color3.fromHex("#33FF88"),
    muted   = Color3.fromHex("#444444"),
    text    = Color3.fromHex("#EEEEEE"),
    subtext = Color3.fromHex("#666666"),
    gold    = Color3.fromHex("#FFD700"),
}

-- 
--  ROOT GUI
-- 
local gui = Instance.new("ScreenGui")
gui.Name           = "StrafeTagV2"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 999
gui.Parent         = LP:WaitForChild("PlayerGui")

-- 
--  DRAGGABLE TAB SYSTEM
--  A small pill sits on screen at all times.
--  Click it to expand/collapse the lobby card.
--  Drag it anywhere. During gameplay it shows the IT badge.
-- 
local TAB_W, TAB_H = 180, 36
local tabExpanded = false

-- The draggable pill (always visible)
local tabPill = Instance.new("TextButton", gui)
tabPill.Size             = UDim2.new(0, TAB_W, 0, TAB_H)
tabPill.Position         = UDim2.new(0, 16, 0, 16)
tabPill.BackgroundColor3 = C.card
tabPill.BorderSizePixel  = 0
tabPill.Text             = ""
tabPill.AutoButtonColor  = false
tabPill.ZIndex           = 100
do
    local c = Instance.new("UICorner", tabPill); c.CornerRadius = UDim.new(0, 10)
    local s = Instance.new("UIStroke", tabPill)
    s.Color = C.accent; s.Thickness = 1.4; s.Transparency = 0.3
end

-- Left accent bar
local tabBar = Instance.new("Frame", tabPill)
tabBar.Size             = UDim2.new(0, 3, 1, -12)
tabBar.Position         = UDim2.new(0, 8, 0, 6)
tabBar.BackgroundColor3 = C.accent
tabBar.BorderSizePixel  = 0
tabBar.ZIndex           = 101
do Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 2) end

-- Title text inside pill
local tabTitleL = Instance.new("TextLabel", tabPill)
tabTitleL.Size             = UDim2.new(1, -48, 1, 0)
tabTitleL.Position         = UDim2.new(0, 18, 0, 0)
tabTitleL.BackgroundTransparency = 1
tabTitleL.TextColor3       = C.accent
tabTitleL.Font             = Enum.Font.GothamBold
tabTitleL.TextSize         = 13
tabTitleL.Text             = "STRAFE TAG"
tabTitleL.TextXAlignment   = Enum.TextXAlignment.Left
tabTitleL.ZIndex           = 102

-- Chevron / toggle indicator
local tabChevron = Instance.new("TextLabel", tabPill)
tabChevron.Size             = UDim2.new(0, 28, 1, 0)
tabChevron.AnchorPoint      = Vector2.new(1, 0.5)
tabChevron.Position         = UDim2.new(1, -6, 0.5, 0)
tabChevron.BackgroundTransparency = 1
tabChevron.TextColor3       = C.subtext
tabChevron.Font             = Enum.Font.GothamBold
tabChevron.TextSize         = 14
tabChevron.Text             = "v"
tabChevron.TextXAlignment   = Enum.TextXAlignment.Center
tabChevron.ZIndex           = 102

-- Dragging logic
local dragging, dragStart, startPos = false, nil, nil

tabPill.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = tabPill.Position
    end
end)

tabPill.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement or
        input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - dragStart
        tabPill.Position = UDim2.new(
            0, startPos.X.Offset + delta.X,
            0, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Expand / collapse the lobby container
-- (the lobby card is wrapped in a container that anchors to the pill)
local lobbyContainer = Instance.new("Frame", gui)
lobbyContainer.Size             = UDim2.new(0, 540, 0, 600)
lobbyContainer.BackgroundTransparency = 1
lobbyContainer.BorderSizePixel  = 0
lobbyContainer.Visible          = false
lobbyContainer.ZIndex           = 99
lobbyContainer.ClipsDescendants = false

local function repositionLobbyContainer()
    -- always appears just below the pill
    local px = tabPill.Position.X.Offset
    local py = tabPill.Position.Y.Offset
    local vp = workspace.CurrentCamera.ViewportSize
    -- clamp so it stays on screen
    local cx = math.clamp(px, 0, vp.X - 545)
    local cy = math.clamp(py + TAB_H + 6, 0, vp.Y - 610)
    lobbyContainer.Position = UDim2.new(0, cx, 0, cy)
end

local function setExpanded(v)
    tabExpanded = v
    tabChevron.Text = v and "^" or "v"
    if v then
        repositionLobbyContainer()
        lobbyContainer.Visible = true
        lobbyContainer.Size    = UDim2.new(0, 0, 0, 0)
        TweenService:Create(lobbyContainer, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, 540, 0, 600) }):Play()
    else
        TweenService:Create(lobbyContainer, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Size = UDim2.new(0, 0, 0, 0) }):Play()
        task.delay(0.17, function() lobbyContainer.Visible = false end)
    end
end

-- track drag vs click
local mouseDownPos = nil
tabPill.MouseButton1Down:Connect(function()
    mouseDownPos = UIS:GetMouseLocation()
end)
tabPill.MouseButton1Up:Connect(function()
    local cur = UIS:GetMouseLocation()
    local moved = mouseDownPos and (cur - mouseDownPos).Magnitude or 0
    if moved < 5 then   -- it was a click not a drag
        setExpanded(not tabExpanded)
    end
end)

-- keep container pinned when pill is dragged
RunService.Heartbeat:Connect(function()
    if tabExpanded then repositionLobbyContainer() end
end)

-- 
--  UI HELPERS
-- 
local function corner(p, r)
    local c = Instance.new("UICorner", p); c.CornerRadius = UDim.new(0, r or 10); return c
end
local function stroke(p, col, thick, trans)
    local s = Instance.new("UIStroke", p)
    s.Color = col or C.stroke; s.Thickness = thick or 1.2; s.Transparency = trans or 0; return s
end
local function pad(p, px)
    local u = UDim.new(0, px)
    local pp = Instance.new("UIPadding", p)
    pp.PaddingLeft = u; pp.PaddingRight = u; pp.PaddingTop = u; pp.PaddingBottom = u
end
local function listL(p, spacing, align)
    local l = Instance.new("UIListLayout", p)
    l.Padding = UDim.new(0, spacing or 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
    return l
end
local function frame(parent, size, pos, bg)
    local f = Instance.new("Frame", parent)
    f.Size = size or UDim2.new(1,0,1,0)
    f.Position = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = bg or C.panel
    f.BorderSizePixel = 0
    return f
end
local function lbl(parent, text, size, col, font, xa)
    local l = Instance.new("TextLabel", parent)
    l.Size = UDim2.new(1,0,0,size+6)
    l.BackgroundTransparency = 1
    l.Text = text; l.TextSize = size
    l.TextColor3 = col or C.text
    l.Font = font or Enum.Font.GothamBold
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    return l
end

local function makeBtn(parent, text, accent, onClick)
    accent = accent or C.accent
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1,0,0,44)
    btn.BackgroundColor3 = C.card
    btn.BorderSizePixel = 0
    btn.TextColor3 = accent
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.Text = text
    btn.AutoButtonColor = false
    corner(btn, 8); stroke(btn, accent, 1.2, 0.55)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3=accent, TextColor3=C.bg }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3=C.card, TextColor3=accent }):Play()
    end)
    btn.MouseButton1Click:Connect(function() playSound(SFX.click,0.7); onClick() end)
    return btn
end

local function makeToggle(parent, labelText, default, onChange)
    local row = frame(parent, UDim2.new(1,0,0,44), nil, C.card)
    corner(row,8); stroke(row,C.stroke,1); pad(row,12)
    local l2 = Instance.new("TextLabel", row)
    l2.Size=UDim2.new(0.6,0,1,0); l2.BackgroundTransparency=1
    l2.TextColor3=C.text; l2.Font=Enum.Font.GothamBold; l2.TextSize=13
    l2.Text=labelText; l2.TextXAlignment=Enum.TextXAlignment.Left
    local pill = Instance.new("TextButton", row)
    pill.Size=UDim2.new(0,54,0,26); pill.AnchorPoint=Vector2.new(1,0.5)
    pill.Position=UDim2.new(1,-4,0.5,0); pill.AutoButtonColor=false
    pill.BorderSizePixel=0; pill.Font=Enum.Font.GothamBold; pill.TextSize=11
    corner(pill,13)
    local val = default
    local function refresh()
        pill.BackgroundColor3 = val and C.accent or C.muted
        pill.TextColor3 = val and C.bg or C.subtext
        pill.Text = val and "ON" or "OFF"
    end
    refresh()
    pill.MouseButton1Click:Connect(function()
        val=not val; refresh(); playSound(SFX.click,0.5)
        if onChange then onChange(val) end
    end)
    return row, function() return val end
end

local function makeStepper(parent, labelText, minV, maxV, defaultV, onChange)
    local row = frame(parent, UDim2.new(1,0,0,44), nil, C.card)
    corner(row,8); stroke(row,C.stroke,1); pad(row,12)
    local l2 = Instance.new("TextLabel", row)
    l2.Size=UDim2.new(0.55,0,1,0); l2.BackgroundTransparency=1
    l2.TextColor3=C.text; l2.Font=Enum.Font.GothamBold; l2.TextSize=13
    l2.Text=labelText; l2.TextXAlignment=Enum.TextXAlignment.Left
    local val = defaultV
    local minus = Instance.new("TextButton", row)
    minus.Size=UDim2.new(0,28,0,28); minus.AnchorPoint=Vector2.new(1,0.5)
    minus.Position=UDim2.new(1,-4,0.5,0); minus.BackgroundColor3=C.stroke
    minus.BorderSizePixel=0; minus.TextColor3=C.text; minus.Font=Enum.Font.GothamBold
    minus.TextSize=16; minus.Text="-"; minus.AutoButtonColor=false; corner(minus,6)
    local numL = Instance.new("TextLabel", row)
    numL.Size=UDim2.new(0,28,0,28); numL.AnchorPoint=Vector2.new(1,0.5)
    numL.Position=UDim2.new(1,-36,0.5,0); numL.BackgroundTransparency=1
    numL.TextColor3=C.accent; numL.Font=Enum.Font.GothamBold; numL.TextSize=16
    numL.Text=tostring(val); numL.TextXAlignment=Enum.TextXAlignment.Center
    local plus = Instance.new("TextButton", row)
    plus.Size=UDim2.new(0,28,0,28); plus.AnchorPoint=Vector2.new(1,0.5)
    plus.Position=UDim2.new(1,-68,0.5,0); plus.BackgroundColor3=C.stroke
    plus.BorderSizePixel=0; plus.TextColor3=C.text; plus.Font=Enum.Font.GothamBold
    plus.TextSize=16; plus.Text="+"; plus.AutoButtonColor=false; corner(plus,6)
    local function refresh2() numL.Text=tostring(val); if onChange then onChange(val) end end
    plus.MouseButton1Click:Connect(function() if val<maxV then val=val+1; playSound(SFX.click,0.4); refresh2() end end)
    minus.MouseButton1Click:Connect(function() if val>minV then val=val-1; playSound(SFX.click,0.4); refresh2() end end)
    return row, function() return val end
end

local function toast(msg, col, dur)
    col = col or C.accent
    local f = frame(gui, UDim2.new(0,0,0,50), UDim2.new(0.5,0,0.88,0), C.card)
    f.AnchorPoint=Vector2.new(0.5,0.5); f.ClipsDescendants=true; f.ZIndex=50
    corner(f,10); stroke(f,col,1.5)
    local l2 = Instance.new("TextLabel", f)
    l2.Size=UDim2.new(1,-24,1,0); l2.Position=UDim2.new(0,12,0,0)
    l2.BackgroundTransparency=1; l2.TextColor3=col
    l2.Font=Enum.Font.GothamBold; l2.TextSize=16; l2.Text=msg; l2.ZIndex=51
    local w = math.clamp(#msg*11+40,180,500)
    TweenService:Create(f,TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
        {Size=UDim2.new(0,w,0,50)}):Play()
    task.delay(dur or 2.5, function()
        TweenService:Create(f,TweenInfo.new(0.25),{Size=UDim2.new(0,w,0,0)}):Play()
        TweenService:Create(l2,TweenInfo.new(0.2),{TextTransparency=1}):Play()
        task.delay(0.3, function() f:Destroy() end)
    end)
end

-- 
--  SCREEN MANAGER
-- 
local screens = {}

local function showScreen(name)
    -- hide all fullscreen overlays
    for sname, s in pairs(screens) do
        if sname ~= "lobby" and s and s.Parent then
            s.Visible = false
        end
    end
    if name == "lobby" then
        -- just open the tab
        setExpanded(true)
        -- update pill text
        tabTitleL.Text = "STRAFE TAG"
        tabBar.BackgroundColor3 = C.accent
    else
        -- collapse lobby tab, show the fullscreen screen
        setExpanded(false)
        if screens[name] then screens[name].Visible = true end
        -- update pill to show current phase
        tabTitleL.Text = name:upper()
        tabBar.BackgroundColor3 = C.muted
    end
end

-- forward declarations
local startFreezePhase, startPlayPhase, endRound, pickItPlayer

-- 
--    LOBBY SCREEN  
-- 
do
    -- lobby lives inside lobbyContainer (the draggable popup)
    local S = lobbyContainer
    screens.lobby = S

    -- card fills the container
    local card = frame(S, UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), C.panel)
    card.ZIndex = 4; corner(card,16); stroke(card, C.accent, 1.5, 0.45)
    card.ClipsDescendants = true

    -- header
    local hdr = frame(card, UDim2.new(1,0,0,76), nil, C.card)
    hdr.ZIndex = 5; corner(hdr, 16); stroke(hdr, C.accent, 1.5, 0.5)

    local titleL = Instance.new("TextLabel", hdr)
    titleL.Size=UDim2.new(1,-24,0,44); titleL.Position=UDim2.new(0,20,0,6)
    titleL.BackgroundTransparency=1; titleL.TextColor3=C.accent
    titleL.Font=Enum.Font.GothamBlack; titleL.TextSize=30
    titleL.Text="STRAFE  TAG"; titleL.TextXAlignment=Enum.TextXAlignment.Left; titleL.ZIndex=6

    local subL = Instance.new("TextLabel", hdr)
    subL.Size=UDim2.new(1,-24,0,20); subL.Position=UDim2.new(0,20,0,50)
    subL.BackgroundTransparency=1; subL.TextColor3=C.subtext
    subL.Font=Enum.Font.Gotham; subL.TextSize=12
    subL.Text="private gamemode . script bridge v2"; subL.TextXAlignment=Enum.TextXAlignment.Left; subL.ZIndex=6

    local verL = Instance.new("TextLabel", hdr)
    verL.Size=UDim2.new(0,60,0,20); verL.AnchorPoint=Vector2.new(1,0)
    verL.Position=UDim2.new(1,-16,0,14); verL.BackgroundTransparency=1
    verL.TextColor3=C.muted; verL.Font=Enum.Font.Gotham; verL.TextSize=11
    verL.Text="v2.0"; verL.TextXAlignment=Enum.TextXAlignment.Right; verL.ZIndex=6

    -- scroll body
    local body = Instance.new("ScrollingFrame", card)
    body.Position=UDim2.new(0,0,0,78); body.Size=UDim2.new(1,0,1,-78)
    body.BackgroundTransparency=1; body.BorderSizePixel=0
    body.ScrollBarThickness=3; body.ScrollBarImageColor3=C.muted
    body.CanvasSize=UDim2.new(0,0,0,0); body.ZIndex=5
    pad(body, 18)
    local bodyL = listL(body, 10)

    -- section: detected players
    local pHdr = lbl(body, "PLAYERS WITH SCRIPT DETECTED", 11, C.subtext, Enum.Font.GothamBold)
    pHdr.ZIndex = 6

    local peersBox = frame(body, UDim2.new(1,0,0,0), nil, Color3.new(0,0,0))
    peersBox.BackgroundTransparency=1; peersBox.ZIndex=6
    local peersL = listL(peersBox, 6)

    local noPeersL = lbl(peersBox, "...  scanning for other players...", 12, C.muted, Enum.Font.Gotham, Enum.TextXAlignment.Center)
    noPeersL.ZIndex=7

    -- section: party
    local ptHdr = lbl(body, "YOUR PARTY", 11, C.subtext, Enum.Font.GothamBold)
    ptHdr.ZIndex=6

    local partyBox = frame(body, UDim2.new(1,0,0,0), nil, Color3.new(0,0,0))
    partyBox.BackgroundTransparency=1; partyBox.ZIndex=6
    local partyLL = listL(partyBox, 6)

    -- self row (permanent)
    local selfRow = frame(partyBox, UDim2.new(1,0,0,42), nil, C.card)
    selfRow.ZIndex=7; corner(selfRow,8); stroke(selfRow, C.accent, 1.2, 0.3)
    local selfL = lbl(selfRow,"  *  "..LP.Name.."  (you)", 13, C.accent, Enum.Font.GothamBold)
    selfL.Size=UDim2.new(1,0,1,0); selfL.ZIndex=8

    -- section: settings
    local stHdr = lbl(body, "GAME SETTINGS", 11, C.subtext, Enum.Font.GothamBold)
    stHdr.ZIndex=6

    local settingsBox = frame(body, UDim2.new(1,0,0,0), nil, Color3.new(0,0,0))
    settingsBox.BackgroundTransparency=1; settingsBox.ZIndex=6
    local settingsLL = listL(settingsBox, 8)

    local roundsRow, getRounds = makeStepper(settingsBox, "Rounds", 1, 10, 1, function(v) STATE.settings.rounds=v end)
    roundsRow.ZIndex=7
    local timerRow, getTimer = makeToggle(settingsBox, "Match Timer", false, function(v) STATE.settings.useTimer=v end)
    timerRow.ZIndex=7
    local timerDurRow, getTimerDur = makeStepper(settingsBox, "Timer (seconds)", 30, 300, 120, function(v) STATE.settings.timerSecs=v end)
    timerDurRow.ZIndex=7

    local spacerEl = frame(body, UDim2.new(1,0,0,4), nil, Color3.new(0,0,0))
    spacerEl.BackgroundTransparency=1

    local startBtn = makeBtn(body, "START GAME", C.accent, function() end)
    startBtn.Size=UDim2.new(1,0,0,52); startBtn.TextSize=17; startBtn.ZIndex=6

    -- party + peer state
    local partyMembers   = { LP }
    local pendingInvites = {}

    local function isInParty(p)
        for _, pm in pairs(partyMembers) do if pm==p then return true end end
    end

    local function rebuildParty()
        for _, c in pairs(partyBox:GetChildren()) do
            if c~=selfRow and (c:IsA("Frame") or c:IsA("TextButton")) then c:Destroy() end
        end
        for _, p in pairs(partyMembers) do
            if p==LP then continue end
            local row = frame(partyBox, UDim2.new(1,0,0,42), nil, C.card)
            row.ZIndex=7; corner(row,8); stroke(row, C.safe, 1.2, 0.4)
            local nl = lbl(row,"  +  "..p.Name, 13, C.safe, Enum.Font.GothamBold)
            nl.Size=UDim2.new(0.7,0,1,0); nl.ZIndex=8
            local kb = Instance.new("TextButton", row)
            kb.Size=UDim2.new(0,60,0,28); kb.AnchorPoint=Vector2.new(1,0.5)
            kb.Position=UDim2.new(1,-10,0.5,0); kb.BackgroundColor3=C.card
            kb.BorderSizePixel=0; kb.TextColor3=C.danger; kb.Font=Enum.Font.GothamBold
            kb.TextSize=11; kb.Text="REMOVE"; kb.AutoButtonColor=false; kb.ZIndex=9
            corner(kb,6); stroke(kb, C.danger, 1, 0.5)
            kb.MouseButton1Click:Connect(function()
                for i,pm in ipairs(partyMembers) do if pm==p then table.remove(partyMembers,i); break end end
                pendingInvites[p.Name]=nil; playSound(SFX.click,0.5); rebuildParty()
            end)
        end
        partyBox.Size=UDim2.new(1,0,0, partyLL.AbsoluteContentSize.Y+4)
        startBtn.Text = #partyMembers<2
            and "NEED AT LEAST 2 PLAYERS"
            or ("START GAME  ("..#partyMembers.." players)")
    end

    local function rebuildPeers()
        for _, c in pairs(peersBox:GetChildren()) do
            if c~=noPeersL and (c:IsA("Frame") or c:IsA("TextButton")) then c:Destroy() end
        end
        local peers = getBridgePeers()
        noPeersL.Visible = #peers == 0
        for _, data in pairs(peers) do
            local p = data.player
            if isInParty(p) then continue end
            local row = frame(peersBox, UDim2.new(1,0,0,46), nil, C.card)
            row.ZIndex=7; corner(row,8); stroke(row, C.stroke, 1)
            local nl = Instance.new("TextLabel", row)
            nl.Size=UDim2.new(0.55,0,1,0); nl.Position=UDim2.new(0,12,0,0)
            nl.BackgroundTransparency=1; nl.TextColor3=C.text
            nl.Font=Enum.Font.GothamBold; nl.TextSize=13; nl.Text=p.Name
            nl.TextXAlignment=Enum.TextXAlignment.Left; nl.ZIndex=8
            local stL = Instance.new("TextLabel", row)
            stL.Size=UDim2.new(0.22,0,1,0); stL.Position=UDim2.new(0.54,0,0,0)
            stL.BackgroundTransparency=1; stL.TextColor3=C.subtext
            stL.Font=Enum.Font.Gotham; stL.TextSize=11; stL.Text=data.status; stL.ZIndex=8
            local invited = pendingInvites[p.Name]
            local ib = Instance.new("TextButton", row)
            ib.Size=UDim2.new(0,78,0,30); ib.AnchorPoint=Vector2.new(1,0.5)
            ib.Position=UDim2.new(1,-10,0.5,0)
            ib.BackgroundColor3 = invited and C.muted or C.accent
            ib.BorderSizePixel=0
            ib.TextColor3 = invited and C.subtext or C.bg
            ib.Font=Enum.Font.GothamBold; ib.TextSize=12
            ib.Text = invited and "SENT" or "INVITE"
            ib.AutoButtonColor=false; corner(ib,6); ib.ZIndex=9
            ib.MouseButton1Click:Connect(function()
                if pendingInvites[p.Name] then return end
                pendingInvites[p.Name]=true; playSound(SFX.invite,1)
                if bridge[p.Name] then bridge[p.Name].invite=LP.Name end
                ib.Text="SENT"; ib.BackgroundColor3=C.muted; ib.TextColor3=C.subtext
                toast("Invite sent to "..p.Name, C.accent)
            end)
        end
        peersBox.Size=UDim2.new(1,0,0, peersL.AbsoluteContentSize.Y+4)
    end

    local function checkIncomingInvites()
        local myData = bridge[LP.Name]
        if myData and myData.invite then
            local fromName = myData.invite
            myData.invite = nil
            playSound(SFX.invite, 1.5)
            -- invite overlay
            local ov = frame(gui, UDim2.new(0,360,0,130), UDim2.new(0.5,-180,0.5,-65), C.panel)
            ov.ZIndex=60; corner(ov,14); stroke(ov, C.accent, 2, 0.15)
            local ol = Instance.new("TextLabel", ov)
            ol.Size=UDim2.new(1,-24,0,60); ol.Position=UDim2.new(0,12,0,10)
            ol.BackgroundTransparency=1; ol.TextColor3=C.text
            ol.Font=Enum.Font.GothamBold; ol.TextSize=15
            ol.Text=fromName.." invited you\nto their party!"; ol.ZIndex=61
            ol.TextXAlignment=Enum.TextXAlignment.Center
            local ab = Instance.new("TextButton", ov)
            ab.Size=UDim2.new(0,120,0,36); ab.Position=UDim2.new(0.5,-134,1,-48)
            ab.BackgroundColor3=C.accent; ab.BorderSizePixel=0; ab.TextColor3=C.bg
            ab.Font=Enum.Font.GothamBold; ab.TextSize=13; ab.Text="ACCEPT"
            ab.AutoButtonColor=false; corner(ab,8); ab.ZIndex=62
            local db = Instance.new("TextButton", ov)
            db.Size=UDim2.new(0,100,0,36); db.Position=UDim2.new(0.5,8,1,-48)
            db.BackgroundColor3=C.card; db.BorderSizePixel=0; db.TextColor3=C.danger
            db.Font=Enum.Font.GothamBold; db.TextSize=13; db.Text="DECLINE"
            db.AutoButtonColor=false; corner(db,8); stroke(db,C.danger,1,0.5); db.ZIndex=62
            ab.MouseButton1Click:Connect(function()
                ov:Destroy()
                local hd = bridge[fromName]
                if hd then hd.acceptedFrom=LP.Name end
                bridge[LP.Name].status="lobby"
                toast("Joined "..fromName.."'s party!", C.safe)
                playSound(SFX.click,1)
            end)
            db.MouseButton1Click:Connect(function() ov:Destroy(); playSound(SFX.click,0.5) end)
            task.delay(12, function() if ov and ov.Parent then ov:Destroy() end end)
        end

        local myBridge = bridge[LP.Name]
        if myBridge and myBridge.acceptedFrom then
            local jn = myBridge.acceptedFrom
            myBridge.acceptedFrom = nil
            local jp = Players:FindFirstChild(jn)
            -- if the other player still exists and isn't already in party, add them
            if jp and not isInParty(jp) then
                table.insert(partyMembers, jp)
                pendingInvites[jn]=nil
                rebuildParty(); rebuildPeers()
                toast(jn.." joined the party!", C.safe)
                playSound(SFX.click,0.8)
            end
        end
    end

    startBtn.MouseButton1Click:Connect(function()
        if #partyMembers < 2 then
            toast("Need at least 2 players in party!", C.danger); return
        end
        STATE.settings.rounds    = getRounds()
        STATE.settings.useTimer  = getTimer()
        STATE.settings.timerSecs = getTimerDur()
        STATE.party              = partyMembers
        for _, p in pairs(STATE.party) do
            STATE.itWeights[p.Name] = 1.0
            STATE.scores[p.Name]    = 0
        end
        STATE.roundNum = 1
        setExpanded(false)
        task.delay(0.2, function()
            pickItPlayer()
        end)
    end)

    task.spawn(function()
        while true do
            task.wait(1.5)
            if screens.lobby.Visible then
                rebuildPeers(); checkIncomingInvites()
                bodyL:ApplyLayout()
                body.CanvasSize=UDim2.new(0,0,0, bodyL.AbsoluteContentSize.Y+24)
                settingsBox.Size=UDim2.new(1,0,0, settingsLL.AbsoluteContentSize.Y+4)
            end
        end
    end)

    rebuildParty(); rebuildPeers()
end

-- 
--  IT PICKER
-- 
pickItPlayer = function()
    -- weighted random for real games; players who were IT recently are less likely
    local totalW = 0
    for _, p in pairs(STATE.party) do
        totalW = totalW + (1 / (STATE.itWeights[p.Name] or 1))
    end
    local roll = math.random() * totalW
    local cum  = 0
    for _, p in pairs(STATE.party) do
        cum = cum + (1 / (STATE.itWeights[p.Name] or 1))
        if roll <= cum then
            STATE.itPlayer = p
            break
        end
    end
    -- safety fallback
    if not STATE.itPlayer then
        STATE.itPlayer = STATE.party[1]
    end

    STATE.itWeights[STATE.itPlayer.Name] = (STATE.itWeights[STATE.itPlayer.Name] or 1) * 2
    bridge[LP.Name].status = "ingame"
    startFreezePhase()
end

-- startFreezePhase: no countdown screen, just go straight to playing
startFreezePhase = function()
    local itName = STATE.itPlayer and STATE.itPlayer.Name or "?"
    local isItMe = STATE.itPlayer == LP
    playSound(SFX.start, 2)
    local msg = isItMe and "!! YOU ARE IT - run!" or ("[IT] "..itName.." is IT - dodge!")
    toast(msg, isItMe and C.danger or C.gold, 3)
    showScreen("playing")
    startPlayPhase()
end

-- 
--    PLAYING HUD  
-- 
local playRefs = {}

do
    local S = frame(gui, UDim2.new(1,0,0,0), nil, Color3.new(0,0,0))
    S.BackgroundTransparency=1; S.ZIndex=5; S.Visible=false
    screens.playing = S

    local itBadge = frame(S, UDim2.new(0,280,0,48), UDim2.new(0.5,-140,0,12), C.card)
    itBadge.ZIndex=6; corner(itBadge,10); stroke(itBadge, C.gold, 1.5, 0.25)
    local itHud = lbl(itBadge,"[IT]  IT: ...",17,C.gold,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    itHud.Size=UDim2.new(1,0,1,0); itHud.ZIndex=7

    local rndBadge = frame(S, UDim2.new(0,150,0,42), UDim2.new(0,12,0,12), C.card)
    rndBadge.ZIndex=6; corner(rndBadge,10); stroke(rndBadge, C.muted, 1)
    local rndHud = lbl(rndBadge,"ROUND 1/1",13,C.subtext,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    rndHud.Size=UDim2.new(1,0,1,0); rndHud.ZIndex=7

    local tmrBadge = frame(S, UDim2.new(0,130,0,42), UDim2.new(1,-144,0,12), C.card)
    tmrBadge.ZIndex=6; corner(tmrBadge,10); stroke(tmrBadge, C.muted, 1)
    local tmrHud = lbl(tmrBadge,"2:00",18,C.subtext,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    tmrHud.Size=UDim2.new(1,0,1,0); tmrHud.ZIndex=7

    local scnBadge = frame(S, UDim2.new(0,140,0,38), UDim2.new(1,-154,0,66), C.card)
    scnBadge.ZIndex=6; corner(scnBadge,10); stroke(scnBadge, C.muted, 1)
    local scnHud = lbl(scnBadge,"SCAN 12s",12,C.subtext,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    scnHud.Size=UDim2.new(1,0,1,0); scnHud.ZIndex=7

    playRefs = {
        itLbl      = itHud,
        itBadge    = itBadge,
        roundLbl   = rndHud,
        timerLbl   = tmrHud,
        timerBadge = tmrBadge,
        scanLbl    = scnHud,
    }
end

-- 
--    END / SCOREBOARD SCREEN  
-- 
local endRefs = {}

do
    local S = frame(gui, UDim2.new(1,0,1,0), nil, C.bg)
    S.ZIndex=30; S.Visible=false
    screens.endscreen = S

    local card = frame(S, UDim2.new(0,480,0,520), UDim2.new(0.5,-240,0.5,-260), C.panel)
    card.ZIndex=31; corner(card,16); stroke(card, C.accent, 1.5, 0.35)
    pad(card,24)

    local eTitle = Instance.new("TextLabel", card)
    eTitle.Size=UDim2.new(1,0,0,42); eTitle.BackgroundTransparency=1
    eTitle.TextColor3=C.accent; eTitle.Font=Enum.Font.GothamBlack
    eTitle.TextSize=30; eTitle.Text="GAME OVER"; eTitle.TextXAlignment=Enum.TextXAlignment.Center; eTitle.ZIndex=32

    local winnerL = Instance.new("TextLabel", card)
    winnerL.Size=UDim2.new(1,0,0,30); winnerL.BackgroundTransparency=1
    winnerL.TextColor3=C.gold; winnerL.Font=Enum.Font.GothamBold
    winnerL.TextSize=19; winnerL.Text=""; winnerL.TextXAlignment=Enum.TextXAlignment.Center; winnerL.ZIndex=32

    local scoreBox = frame(card, UDim2.new(1,0,0,300), nil, Color3.new(0,0,0))
    scoreBox.BackgroundTransparency=1; scoreBox.ZIndex=32
    listL(scoreBox, 8)

    local paBtn = makeBtn(card,"PLAY AGAIN",C.accent,function()
        STATE.roundNum=1; STATE.itPlayer=nil
        for k in pairs(STATE.scores) do STATE.scores[k]=0 end
        for k in pairs(STATE.itWeights) do STATE.itWeights[k]=1.0 end
        pickItPlayer()
    end)
    paBtn.TextSize=15; paBtn.ZIndex=32

    local mmBtn = makeBtn(card,"MAIN MENU",C.muted,function()
        STATE.party={}
        showScreen("lobby")
        setExpanded(true)
    end)
    mmBtn.ZIndex=32

    endRefs = { winnerLbl=winnerL, scoreBox=scoreBox }
end

-- 
--  ESP ENGINE
-- 
local skeletonPairs = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local function espCol(p) return p==STATE.itPlayer and C.gold or C.danger end

local function destroyESP(p)
    if activeESP[p] then pcall(function() activeESP[p].bb:Destroy() end); activeESP[p]=nil end
    if screenArrows[p] then pcall(function() screenArrows[p]:Destroy() end); screenArrows[p]=nil end
    if skeletonLines[p] then
        for _,e in pairs(skeletonLines[p]) do pcall(function() e.line:Remove() end) end
        skeletonLines[p]=nil
    end
end

local function destroyAllESP() for p in pairs(activeESP) do destroyESP(p) end end

local function createESP(p)
    if activeESP[p] then return end
    if not p.Character then return end  -- bot mock has no Character, safely skipped
    local root = p.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local col = espCol(p)
    local bb = Instance.new("BillboardGui", root)
    bb.Size=UDim2.new(0,160,0,54); bb.AlwaysOnTop=true
    bb.StudsOffset=Vector3.new(0,3.5,0); bb.LightInfluence=0; bb.ZIndex=8
    local bg = frame(bb, UDim2.new(1,0,1,0), nil, Color3.fromHex("#080808"))
    bg.BackgroundTransparency=0.2; corner(bg,6); stroke(bg,col,1.4,0.1)
    local bl = Instance.new("TextLabel", bg)
    bl.Size=UDim2.new(1,-8,1,0); bl.Position=UDim2.new(0,4,0,0)
    bl.BackgroundTransparency=1; bl.TextColor3=col
    bl.Font=Enum.Font.GothamBold; bl.TextSize=13
    bl.TextXAlignment=Enum.TextXAlignment.Left; bl.ZIndex=9
    local arrow = Instance.new("ImageLabel", gui)
    arrow.Size=UDim2.new(0,28,0,28); arrow.AnchorPoint=Vector2.new(0.5,0.5)
    arrow.BackgroundTransparency=1; arrow.Image="rbxassetid://6034818372"
    arrow.ImageColor3=col; arrow.Visible=false; arrow.ZIndex=8
    activeESP[p]={bb=bb,bg=bg,label=bl}; screenArrows[p]=arrow; skeletonLines[p]={}
    for _,pair in ipairs(skeletonPairs) do
        local l=Drawing.new("Line"); l.Thickness=2; l.Color=col; l.Transparency=0.15; l.Visible=false
        table.insert(skeletonLines[p],{line=l,parts=pair})
    end
end

-- 
--  TAG LOGIC
-- 
local tagCooldown = false

local function doTag(tagged)
    if tagCooldown then return end
    if STATE.phase~="playing" then return end
    if STATE.itPlayer~=LP then return end  -- only IT tags
    tagCooldown=true
    STATE.itPlayer=tagged
    STATE.scores[tagged.Name]=(STATE.scores[tagged.Name] or 0)+1
    STATE.itWeights[tagged.Name]=(STATE.itWeights[tagged.Name] or 1)*2
    playSound(SFX.tag_them,4)
    toast("TAG  TAGGED "..tagged.Name.."!", C.safe, 2)
    if playRefs.itLbl then
        playRefs.itLbl.Text="[IT]  IT: "..tagged.Name
        playRefs.itLbl.TextColor3=C.gold
    end
    -- pure GUI flash - no SelectionBox on character (anti-cheat safe)
    local flashOverlay = Instance.new("Frame", gui)
    flashOverlay.Size = UDim2.new(1,0,1,0)
    flashOverlay.BackgroundColor3 = C.accent
    flashOverlay.BackgroundTransparency = 0.4
    flashOverlay.BorderSizePixel = 0
    flashOverlay.ZIndex = 40
    TweenService:Create(flashOverlay, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 1 }):Play()
    task.delay(0.6, function() flashOverlay:Destroy() end)
    if STATE.settings.rounds==1 then
        task.delay(0.8, function() endRound() end)
    else
        task.delay(0.8, function() startFreezePhase() end)
    end
    task.delay(CFG.TAG_COOLDOWN, function() tagCooldown=false end)
end

-- 
--  PLAY PHASE
-- 
local playActive = false

startPlayPhase = function()
    STATE.phase="playing"; playActive=true
    if playRefs.itLbl then
        playRefs.itLbl.Text = "[IT]  IT: "..(STATE.itPlayer and STATE.itPlayer.Name or "?")
        playRefs.roundLbl.Text = "ROUND "..STATE.roundNum.."/"..STATE.settings.rounds
        playRefs.timerBadge.Visible = STATE.settings.useTimer
    end

    -- scan loop
    task.spawn(function()
        while playActive do
            for i=CFG.SCAN_INTERVAL,1,-1 do
                if not playActive then break end
                if playRefs.scanLbl then
                    playRefs.scanLbl.Text="SCAN  "..i.."s"
                    playRefs.scanLbl.TextColor3=C.subtext
                end
                task.wait(1)
            end
            if not playActive then break end
            playSound(SFX.freeze,1)
            if playRefs.scanLbl then playRefs.scanLbl.Text="* SCANNING"; playRefs.scanLbl.TextColor3=C.safe end
            for _,p in pairs(STATE.party) do
                if p~=LP and p.Character then createESP(p) end  -- skip bot (no Character)
            end
            task.wait(CFG.SCAN_DURATION)
            destroyAllESP()
        end
    end)

    -- timer
    if STATE.settings.useTimer then
        task.spawn(function()
            local rem=STATE.settings.timerSecs
            while playActive and rem>0 do
                local m=math.floor(rem/60); local s=rem%60
                if playRefs.timerLbl then
                    playRefs.timerLbl.Text=string.format("%d:%02d",m,s)
                    playRefs.timerLbl.TextColor3=rem<=10 and C.danger or C.subtext
                end
                task.wait(1); rem=rem-1
            end
            if playActive then endRound() end
        end)
    end
end

-- 
--  END ROUND / GAME
-- 
endRound = function()
    playActive=false; STATE.phase="end"; destroyAllESP()
    STATE.roundNum=STATE.roundNum+1
    if STATE.roundNum<=STATE.settings.rounds then
        toast("Round "..(STATE.roundNum-1).." done!", C.accent, 2)
        task.delay(2, function() STATE.phase="playing"; startFreezePhase() end)
        return
    end
    showScreen("endscreen"); playSound(SFX.win,2)
    local winner,minT=nil,math.huge
    for _,p in pairs(STATE.party) do
        local t=STATE.scores[p.Name] or 0
        if t<minT then minT=t; winner=p end
    end
    if endRefs.winnerLbl then
        endRefs.winnerLbl.Text=winner and ("WIN  "..winner.Name.." WINS!") or "TIE!"
    end
    if endRefs.scoreBox then
        for _,c in pairs(endRefs.scoreBox:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
        local sorted={}
        for _,p in pairs(STATE.party) do table.insert(sorted,p) end
        table.sort(sorted,function(a,b) return (STATE.scores[a.Name] or 0)<(STATE.scores[b.Name] or 0) end)
        for rank,p in ipairs(sorted) do
            local isW=(p==winner)
            local row=frame(endRefs.scoreBox,UDim2.new(1,0,0,50),nil,C.card)
            corner(row,8); stroke(row,isW and C.gold or C.stroke,1.2,isW and 0.15 or 0); row.ZIndex=34
            local rl=lbl(row,tostring(rank),22,isW and C.gold or C.subtext,Enum.Font.GothamBlack)
            rl.Size=UDim2.new(0,40,1,0); rl.Position=UDim2.new(0,10,0,0); rl.TextXAlignment=Enum.TextXAlignment.Center; rl.ZIndex=35
            local nl=lbl(row,p.Name,14,isW and C.gold or C.text,Enum.Font.GothamBold)
            nl.Size=UDim2.new(0.5,0,1,0); nl.Position=UDim2.new(0,54,0,0); nl.ZIndex=35
            local sl=lbl(row,(STATE.scores[p.Name] or 0).." tags",13,C.subtext,Enum.Font.Gotham,Enum.TextXAlignment.Right)
            sl.Size=UDim2.new(0.3,-10,1,0); sl.Position=UDim2.new(0.7,0,0,0); sl.ZIndex=35
        end
    end
end

-- 
--  RENDER LOOP
-- 
RunService.RenderStepped:Connect(function()
    if STATE.phase~="playing" then return end
    local lpChar=LP.Character
    local lpRoot=lpChar and lpChar:FindFirstChild("HumanoidRootPart")
    local cam=workspace.CurrentCamera
    local vp=cam.ViewportSize
    local center=vp/2

    -- update IT hud
    if playRefs.itLbl and STATE.itPlayer then
        local isItMe=STATE.itPlayer==LP
        playRefs.itLbl.Text=isItMe and "!!  YOU ARE IT" or ("[IT]  IT: "..STATE.itPlayer.Name)
        playRefs.itLbl.TextColor3=isItMe and C.danger or C.gold
        local st=playRefs.itBadge and playRefs.itBadge:FindFirstChildOfClass("UIStroke")
        if st then st.Color=isItMe and C.danger or C.gold end
    end

    for player,data in pairs(activeESP) do
        local char=player.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if not(char and root and lpRoot) then continue end  -- skips bot mock naturally
        local dist=(lpRoot.Position-root.Position).Magnitude
        local col=espCol(player)
        data.label.TextColor3=col
        local st=data.bg:FindFirstChildOfClass("UIStroke")
        if st then st.Color=col end
        screenArrows[player].ImageColor3=col
        data.label.Text=player.Name..(player==STATE.itPlayer and "  [IT]" or "").."\n"..math.floor(dist).."m"
        -- tag
        if dist<=CFG.TAG_DISTANCE then doTag(player) end
        -- arrow
        local sp,onScreen=cam:WorldToViewportPoint(root.Position)
        local arrow=screenArrows[player]
        if not onScreen then
            arrow.Visible=true
            local dir=Vector2.new(sp.X,sp.Y)-center
            if sp.Z<0 then dir=-dir end
            local unit=dir.Unit
            arrow.Position=UDim2.new(0,center.X+unit.X*CFG.ARROW_RADIUS,0,center.Y+unit.Y*CFG.ARROW_RADIUS)
            arrow.Rotation=math.deg(math.atan2(unit.Y,unit.X))
        else arrow.Visible=false end
        -- skeleton
        for _,entry in pairs(skeletonLines[player]) do
            local p1=char:FindFirstChild(entry.parts[1])
            local p2=char:FindFirstChild(entry.parts[2])
            if p1 and p2 then
                local v1,vis1=cam:WorldToViewportPoint(p1.Position)
                local v2,vis2=cam:WorldToViewportPoint(p2.Position)
                entry.line.Visible=vis1 or vis2; entry.line.Color=col
                entry.line.From=Vector2.new(v1.X,v1.Y); entry.line.To=Vector2.new(v2.X,v2.Y)
            else entry.line.Visible=false end
        end
    end
end)

-- 
--  CLEANUP
-- 
Players.PlayerRemoving:Connect(function(p)
    destroyESP(p); bridge[p.Name]=nil
    for i,pm in ipairs(STATE.party) do if pm==p then table.remove(STATE.party,i); break end end
    if STATE.itPlayer==p then STATE.itPlayer=nil end
end)

-- 
--  INIT
-- 
bridge[LP.Name].status="lobby"
-- open the tab automatically on load
task.delay(0.1, function()
    setExpanded(true)
end)
print("[StrafeTag v2] ready - click the tab to open")
