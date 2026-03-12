--
--  STRAFE TAG v3
--  PIN-based lobby: one player creates a room, shares the 4-digit PIN,
--  friend types it in to join. No _G scanning needed.
--

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local LP           = Players.LocalPlayer

--
--  PIN ROOM SYSTEM
--  _G.StrafeRooms[PIN] = { host, members, settings, state }
--  Any client can read/write rooms by PIN
--
_G.StrafeRooms = _G.StrafeRooms or {}
local Rooms = _G.StrafeRooms

local myRoom   = nil   -- PIN string of room we're in
local isHost   = false

local function getRoom() return myRoom and Rooms[myRoom] end

local function createRoom()
    local pin = tostring(math.random(1000, 9999))
    -- ensure unique
    while Rooms[pin] do pin = tostring(math.random(1000, 9999)) end
    Rooms[pin] = {
        host     = LP.Name,
        members  = { LP.Name },
        settings = { rounds=1, useTimer=false, timerSecs=120 },
        state    = "lobby",   -- lobby | playing | end
        itPlayer = nil,
        scores   = {},
        itWeights= {},
    }
    myRoom = pin
    isHost = true
    return pin
end

local function joinRoom(pin)
    local room = Rooms[pin]
    if not room then return false, "Room not found" end
    if room.state ~= "lobby" then return false, "Game already started" end
    if #room.members >= 8 then return false, "Room is full" end
    for _, n in pairs(room.members) do
        if n == LP.Name then return false, "Already in room" end
    end
    table.insert(room.members, LP.Name)
    myRoom = pin
    isHost = false
    return true
end

local function leaveRoom()
    local room = getRoom()
    if not room then return end
    for i, n in ipairs(room.members) do
        if n == LP.Name then table.remove(room.members, i); break end
    end
    if room.host == LP.Name then
        -- pass host or destroy
        if #room.members > 0 then
            room.host = room.members[1]
        else
            Rooms[myRoom] = nil
        end
    end
    myRoom = nil; isHost = false
end

local function getRoomPlayers()
    local room = getRoom()
    if not room then return {} end
    local out = {}
    for _, name in pairs(room.members) do
        local p = Players:FindFirstChild(name)
        if p then table.insert(out, p) end
    end
    return out
end

--
--  SOUNDS
--
local SFX = {
    click    = "876939830",
    join     = "4612378735",
    start    = "1369158752",
    tag      = "5522091500",
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
    SCAN_INTERVAL = 10,
    SCAN_DURATION = 5,
    ARROW_RADIUS  = 280,
}

--
--  GAME STATE  (local)
--
local STATE = {
    phase    = "home",
    itPlayer = nil,
    roundNum = 1,
    playActive = false,
}

local activeESP     = {}
local skeletonLines = {}
local screenArrows  = {}

--
--  COLOURS
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
gui.Name           = "StrafeTagV3"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder   = 999
gui.Parent         = LP:WaitForChild("PlayerGui")

--
--  UI HELPERS
--
local function corner(p, r)
    local c = Instance.new("UICorner", p)
    c.CornerRadius = UDim.new(0, r or 10)
    return c
end
local function stroke(p, col, thick, trans)
    local s = Instance.new("UIStroke", p)
    s.Color = col or C.stroke
    s.Thickness = thick or 1.2
    s.Transparency = trans or 0
    return s
end
local function pad(p, px)
    local u = UDim.new(0, px)
    local pp = Instance.new("UIPadding", p)
    pp.PaddingLeft=u; pp.PaddingRight=u; pp.PaddingTop=u; pp.PaddingBottom=u
end
local function listL(p, spacing)
    local l = Instance.new("UIListLayout", p)
    l.Padding = UDim.new(0, spacing or 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
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
    return l
end
local function makeBtn(parent, text, ac, onClick)
    ac = ac or C.accent
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1,0,0,46)
    btn.BackgroundColor3 = C.card
    btn.BorderSizePixel = 0
    btn.TextColor3 = ac
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.Text = text
    btn.AutoButtonColor = false
    corner(btn, 8); stroke(btn, ac, 1.2, 0.5)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3=ac, TextColor3=C.bg}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3=C.card, TextColor3=ac}):Play()
    end)
    btn.MouseButton1Click:Connect(function() playSound(SFX.click, 0.6); onClick() end)
    return btn
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
    local function ref() numL.Text=tostring(val); if onChange then onChange(val) end end
    plus.MouseButton1Click:Connect(function() if val<maxV then val=val+1; ref() end end)
    minus.MouseButton1Click:Connect(function() if val>minV then val=val-1; ref() end end)
    return row, function() return val end
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
    local function ref()
        pill.BackgroundColor3 = val and C.accent or C.muted
        pill.TextColor3 = val and C.bg or C.subtext
        pill.Text = val and "ON" or "OFF"
    end
    ref()
    pill.MouseButton1Click:Connect(function()
        val=not val; ref()
        if onChange then onChange(val) end
    end)
    return row, function() return val end
end

local function toast(msg, col, dur)
    col = col or C.accent
    local f = frame(gui, UDim2.new(0,0,0,50), UDim2.new(0.5,0,0.88,0), C.card)
    f.AnchorPoint=Vector2.new(0.5,0.5); f.ClipsDescendants=true; f.ZIndex=60
    corner(f,10); stroke(f,col,1.5)
    local l2 = Instance.new("TextLabel", f)
    l2.Size=UDim2.new(1,-24,1,0); l2.Position=UDim2.new(0,12,0,0)
    l2.BackgroundTransparency=1; l2.TextColor3=col
    l2.Font=Enum.Font.GothamBold; l2.TextSize=15; l2.Text=msg; l2.ZIndex=61
    local w = math.clamp(#msg*11+40, 180, 520)
    TweenService:Create(f, TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
        {Size=UDim2.new(0,w,0,50)}):Play()
    task.delay(dur or 2.5, function()
        TweenService:Create(f,TweenInfo.new(0.25),{Size=UDim2.new(0,w,0,0)}):Play()
        TweenService:Create(l2,TweenInfo.new(0.2),{TextTransparency=1}):Play()
        task.delay(0.3, function() f:Destroy() end)
    end)
end

--
--  DRAGGABLE TAB PILL
--
local TAB_W, TAB_H = 180, 36
local tabExpanded  = false

local tabPill = Instance.new("TextButton", gui)
tabPill.Size             = UDim2.new(0, TAB_W, 0, TAB_H)
tabPill.Position         = UDim2.new(0, 16, 0, 16)
tabPill.BackgroundColor3 = C.card
tabPill.BorderSizePixel  = 0
tabPill.Text             = ""
tabPill.AutoButtonColor  = false
tabPill.ZIndex           = 100
corner(tabPill, 10)
stroke(tabPill, C.accent, 1.4, 0.3)

local tabBar = Instance.new("Frame", tabPill)
tabBar.Size=UDim2.new(0,3,1,-12); tabBar.Position=UDim2.new(0,8,0,6)
tabBar.BackgroundColor3=C.accent; tabBar.BorderSizePixel=0; tabBar.ZIndex=101
corner(tabBar,2)

local tabTitle = Instance.new("TextLabel", tabPill)
tabTitle.Size=UDim2.new(1,-44,1,0); tabTitle.Position=UDim2.new(0,18,0,0)
tabTitle.BackgroundTransparency=1; tabTitle.TextColor3=C.accent
tabTitle.Font=Enum.Font.GothamBold; tabTitle.TextSize=13
tabTitle.Text="STRAFE TAG"; tabTitle.TextXAlignment=Enum.TextXAlignment.Left
tabTitle.ZIndex=102

local tabChev = Instance.new("TextLabel", tabPill)
tabChev.Size=UDim2.new(0,28,1,0); tabChev.AnchorPoint=Vector2.new(1,0.5)
tabChev.Position=UDim2.new(1,-6,0.5,0); tabChev.BackgroundTransparency=1
tabChev.TextColor3=C.subtext; tabChev.Font=Enum.Font.GothamBold
tabChev.TextSize=14; tabChev.Text="v"; tabChev.TextXAlignment=Enum.TextXAlignment.Center
tabChev.ZIndex=102

-- drag
local dragging, dragStart, startPos = false, nil, nil
tabPill.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=inp.Position; startPos=tabPill.Position
    end
end)
tabPill.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        dragging=false
    end
end)
UIS.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch) then
        local d=inp.Position-dragStart
        tabPill.Position=UDim2.new(0,startPos.X.Offset+d.X,0,startPos.Y.Offset+d.Y)
    end
end)

-- lobby container
local lobbyContainer = Instance.new("Frame", gui)
lobbyContainer.Size=UDim2.new(0,500,0,580); lobbyContainer.BackgroundTransparency=1
lobbyContainer.BorderSizePixel=0; lobbyContainer.Visible=false; lobbyContainer.ZIndex=99

local function repositionContainer()
    local px=tabPill.Position.X.Offset; local py=tabPill.Position.Y.Offset
    local vp=workspace.CurrentCamera.ViewportSize
    lobbyContainer.Position=UDim2.new(0,
        math.clamp(px,0,vp.X-505), 0,
        math.clamp(py+TAB_H+6,0,vp.Y-585))
end

local function setExpanded(v)
    tabExpanded=v; tabChev.Text=v and "^" or "v"
    if v then
        repositionContainer()
        lobbyContainer.Visible=true; lobbyContainer.Size=UDim2.new(0,0,0,0)
        TweenService:Create(lobbyContainer,TweenInfo.new(0.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
            {Size=UDim2.new(0,500,0,580)}):Play()
    else
        TweenService:Create(lobbyContainer,TweenInfo.new(0.15,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
            {Size=UDim2.new(0,0,0,0)}):Play()
        task.delay(0.18,function() lobbyContainer.Visible=false end)
    end
end

RunService.Heartbeat:Connect(function() if tabExpanded then repositionContainer() end end)

local mouseDownPos=nil
tabPill.MouseButton1Down:Connect(function() mouseDownPos=UIS:GetMouseLocation() end)
tabPill.MouseButton1Up:Connect(function()
    local cur=UIS:GetMouseLocation()
    if mouseDownPos and (cur-mouseDownPos).Magnitude < 5 then
        setExpanded(not tabExpanded)
    end
end)

--
--  SCREENS
--
local screens = {}

local function showScreen(name)
    for sname,s in pairs(screens) do
        if sname~="lobby" and s and s.Parent then s.Visible=false end
    end
    if name=="lobby" then
        setExpanded(true)
        tabTitle.Text="STRAFE TAG"; tabBar.BackgroundColor3=C.accent
    else
        setExpanded(false)
        if screens[name] then screens[name].Visible=true end
        tabTitle.Text=name:upper(); tabBar.BackgroundColor3=C.muted
    end
end

-- forward declares
local startGame, endRound, startPlayPhase

--
-- =====================================================
--    HOME SCREEN  (Create Room / Join Room)
-- =====================================================
--
do
    local S = lobbyContainer
    screens.lobby = S

    local card = frame(S, UDim2.new(1,0,1,0), nil, C.panel)
    card.ZIndex=4; corner(card,16); stroke(card,C.accent,1.5,0.4)
    card.ClipsDescendants=true

    -- header
    local hdr = frame(card, UDim2.new(1,0,0,72), nil, C.card)
    hdr.ZIndex=5; corner(hdr,16); stroke(hdr,C.accent,1.5,0.5)
    local htitle = Instance.new("TextLabel",hdr)
    htitle.Size=UDim2.new(1,-24,0,40); htitle.Position=UDim2.new(0,20,0,6)
    htitle.BackgroundTransparency=1; htitle.TextColor3=C.accent
    htitle.Font=Enum.Font.GothamBlack; htitle.TextSize=26
    htitle.Text="STRAFE  TAG"; htitle.TextXAlignment=Enum.TextXAlignment.Left; htitle.ZIndex=6
    local hsub = Instance.new("TextLabel",hdr)
    hsub.Size=UDim2.new(1,-24,0,18); hsub.Position=UDim2.new(0,20,0,48)
    hsub.BackgroundTransparency=1; hsub.TextColor3=C.subtext
    hsub.Font=Enum.Font.Gotham; hsub.TextSize=11
    hsub.Text="v3 . pin-based rooms"; hsub.TextXAlignment=Enum.TextXAlignment.Left; hsub.ZIndex=6

    -- body scroll
    local body = Instance.new("ScrollingFrame", card)
    body.Position=UDim2.new(0,0,0,74); body.Size=UDim2.new(1,0,1,-74)
    body.BackgroundTransparency=1; body.BorderSizePixel=0
    body.ScrollBarThickness=3; body.ScrollBarImageColor3=C.muted
    body.CanvasSize=UDim2.new(0,0,0,0); body.ZIndex=5
    pad(body,18)
    local bodyL = listL(body,12)

    -- ── CREATE ROOM ──────────────────────────────────────
    local createSec = lbl(body,"CREATE A ROOM",11,C.subtext,Enum.Font.GothamBold)
    createSec.ZIndex=6

    local createBtn = makeBtn(body,"CREATE ROOM",C.accent,function() end)
    createBtn.ZIndex=6

    -- PIN display (hidden until room created)
    local pinDisplay = frame(body,UDim2.new(1,0,0,70),nil,C.card)
    pinDisplay.ZIndex=6; corner(pinDisplay,12); stroke(pinDisplay,C.accent,1.5,0.3)
    pinDisplay.Visible=false

    local pinTopLbl = Instance.new("TextLabel",pinDisplay)
    pinTopLbl.Size=UDim2.new(1,0,0,22); pinTopLbl.Position=UDim2.new(0,0,0,6)
    pinTopLbl.BackgroundTransparency=1; pinTopLbl.TextColor3=C.subtext
    pinTopLbl.Font=Enum.Font.Gotham; pinTopLbl.TextSize=11
    pinTopLbl.Text="SHARE THIS PIN WITH YOUR FRIEND"; pinTopLbl.TextXAlignment=Enum.TextXAlignment.Center

    local pinNumLbl = Instance.new("TextLabel",pinDisplay)
    pinNumLbl.Size=UDim2.new(1,0,0,40); pinNumLbl.Position=UDim2.new(0,0,0,24)
    pinNumLbl.BackgroundTransparency=1; pinNumLbl.TextColor3=C.accent
    pinNumLbl.Font=Enum.Font.GothamBlack; pinNumLbl.TextSize=36
    pinNumLbl.Text="----"; pinNumLbl.TextXAlignment=Enum.TextXAlignment.Center

    -- divider
    local divider = frame(body,UDim2.new(1,0,0,1),nil,C.stroke)
    divider.ZIndex=6

    -- ── JOIN ROOM ─────────────────────────────────────────
    local joinSec = lbl(body,"JOIN A ROOM",11,C.subtext,Enum.Font.GothamBold)
    joinSec.ZIndex=6

    -- PIN input row
    local inputRow = frame(body,UDim2.new(1,0,0,48),nil,C.card)
    inputRow.ZIndex=6; corner(inputRow,10); stroke(inputRow,C.stroke,1.2)

    local pinInput = Instance.new("TextBox",inputRow)
    pinInput.Size=UDim2.new(1,-110,1,0); pinInput.Position=UDim2.new(0,14,0,0)
    pinInput.BackgroundTransparency=1; pinInput.TextColor3=C.text
    pinInput.Font=Enum.Font.GothamBold; pinInput.TextSize=22
    pinInput.PlaceholderText="enter PIN"; pinInput.PlaceholderColor3=C.muted
    pinInput.Text=""; pinInput.ClearTextOnFocus=true
    pinInput.MaxVisibleGraphemes=4; pinInput.ZIndex=7

    local joinBtn = Instance.new("TextButton",inputRow)
    joinBtn.Size=UDim2.new(0,90,0,34); joinBtn.AnchorPoint=Vector2.new(1,0.5)
    joinBtn.Position=UDim2.new(1,-8,0.5,0); joinBtn.BackgroundColor3=C.accent
    joinBtn.BorderSizePixel=0; joinBtn.TextColor3=C.bg
    joinBtn.Font=Enum.Font.GothamBold; joinBtn.TextSize=13; joinBtn.Text="JOIN"
    joinBtn.AutoButtonColor=false; corner(joinBtn,8); joinBtn.ZIndex=7

    joinBtn.MouseEnter:Connect(function()
        TweenService:Create(joinBtn,TweenInfo.new(0.1),{BackgroundColor3=C.text}):Play()
    end)
    joinBtn.MouseLeave:Connect(function()
        TweenService:Create(joinBtn,TweenInfo.new(0.1),{BackgroundColor3=C.accent}):Play()
    end)

    -- ── ROOM LOBBY (shown after create/join) ─────────────
    local roomSec = frame(body,UDim2.new(1,0,0,0),nil,Color3.new(0,0,0))
    roomSec.BackgroundTransparency=1; roomSec.ZIndex=6
    roomSec.Visible=false
    local roomSecL = listL(roomSec,8)

    local roomHeader = lbl(roomSec,"ROOM  ----",13,C.accent,Enum.Font.GothamBlack,Enum.TextXAlignment.Center)
    roomHeader.ZIndex=7

    local memberBox = frame(roomSec,UDim2.new(1,0,0,0),nil,Color3.new(0,0,0))
    memberBox.BackgroundTransparency=1; memberBox.ZIndex=7
    local memberL = listL(memberBox,6)

    -- settings (host only)
    local settingsSec = frame(roomSec,UDim2.new(1,0,0,0),nil,Color3.new(0,0,0))
    settingsSec.BackgroundTransparency=1; settingsSec.ZIndex=7
    local settingsL = listL(settingsSec,6)

    local settingsHdr = lbl(settingsSec,"SETTINGS  (host only)",11,C.subtext,Enum.Font.GothamBold)
    settingsHdr.ZIndex=8

    local roundsRow,  getRounds  = makeStepper(settingsSec,"Rounds",1,10,1,function(v)
        local r=getRoom(); if r and isHost then r.settings.rounds=v end
    end)
    roundsRow.ZIndex=8

    local timerRow, getTimer = makeToggle(settingsSec,"Match Timer",false,function(v)
        local r=getRoom(); if r and isHost then r.settings.useTimer=v end
    end)
    timerRow.ZIndex=8

    local timerDurRow, getTimerDur = makeStepper(settingsSec,"Timer (s)",30,300,120,function(v)
        local r=getRoom(); if r and isHost then r.settings.timerSecs=v end
    end)
    timerDurRow.ZIndex=8

    local startBtn = makeBtn(roomSec,"START GAME",C.accent,function() end)
    startBtn.ZIndex=7

    local leaveBtn = makeBtn(roomSec,"LEAVE ROOM",C.danger,function()
        leaveRoom()
        roomSec.Visible=false
        pinDisplay.Visible=false
        createBtn.Text="CREATE ROOM"
        createBtn.TextColor3=C.accent
        local st=createBtn:FindFirstChildOfClass("UIStroke")
        if st then st.Color=C.accent end
        pinInput.Text=""
        bodyL:ApplyLayout()
        body.CanvasSize=UDim2.new(0,0,0,bodyL.AbsoluteContentSize.Y+24)
    end)
    leaveBtn.ZIndex=7

    local function rebuildMembers()
        for _,c in pairs(memberBox:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local room=getRoom()
        if not room then return end
        for _,name in pairs(room.members) do
            local isMe = name==LP.Name
            local isH  = name==room.host
            local mrow = frame(memberBox,UDim2.new(1,0,0,40),nil,C.card)
            mrow.ZIndex=8; corner(mrow,8)
            stroke(mrow, isMe and C.accent or (isH and C.gold or C.stroke), 1.2, 0.3)
            local ml=Instance.new("TextLabel",mrow)
            ml.Size=UDim2.new(1,-12,1,0); ml.Position=UDim2.new(0,12,0,0)
            ml.BackgroundTransparency=1
            ml.TextColor3=isMe and C.accent or (isH and C.gold or C.text)
            ml.Font=Enum.Font.GothamBold; ml.TextSize=13
            ml.Text=name..(isMe and "  (you)" or "")..(isH and "  [host]" or "")
            ml.TextXAlignment=Enum.TextXAlignment.Left; ml.ZIndex=9
        end
        memberBox.Size=UDim2.new(1,0,0,memberL.AbsoluteContentSize.Y+4)
        -- show/hide settings based on host
        settingsSec.Visible=isHost
        -- show/hide start based on host and min players
        startBtn.Visible=isHost
        startBtn.Text=#room.members<2
            and "NEED AT LEAST 2 PLAYERS"
            or ("START  ("..#room.members.." players)")
        roomHeader.Text="ROOM  "..myRoom
        roomSec.Size=UDim2.new(1,0,0,roomSecL.AbsoluteContentSize.Y+4)
        bodyL:ApplyLayout()
        body.CanvasSize=UDim2.new(0,0,0,bodyL.AbsoluteContentSize.Y+24)
    end

    local function enterRoom()
        roomSec.Visible=true
        rebuildMembers()
    end

    -- CREATE
    createBtn.MouseButton1Click:Connect(function()
        if myRoom then toast("Already in a room! Leave first.",C.danger); return end
        local pin=createRoom()
        pinNumLbl.Text=pin
        pinDisplay.Visible=true
        createBtn.Text="ROOM CREATED"
        createBtn.TextColor3=C.safe
        local st=createBtn:FindFirstChildOfClass("UIStroke")
        if st then st.Color=C.safe end
        playSound(SFX.join,1)
        toast("Room "..pin.." created! Share the PIN.",C.accent,3)
        enterRoom()
    end)

    -- JOIN
    local function tryJoin()
        local pin=pinInput.Text:match("^%d+$") and pinInput.Text or ""
        if #pin~=4 then toast("Enter a 4-digit PIN",C.danger,2); return end
        if myRoom then toast("Leave your current room first",C.danger,2); return end
        local ok,err=joinRoom(pin)
        if not ok then toast("Error: "..(err or "?"),C.danger,2); return end
        playSound(SFX.join,1)
        toast("Joined room "..pin.."!",C.safe,2)
        enterRoom()
    end

    joinBtn.MouseButton1Click:Connect(tryJoin)
    pinInput.FocusLost:Connect(function(entered) if entered then tryJoin() end end)

    -- START
    startBtn.MouseButton1Click:Connect(function()
        local room=getRoom()
        if not room then return end
        if #room.members<2 then toast("Need at least 2 players!",C.danger); return end
        room.settings.rounds   = getRounds()
        room.settings.useTimer = getTimer()
        room.settings.timerSecs= getTimerDur()
        room.state="playing"
        -- init weights and scores
        for _,name in pairs(room.members) do
            room.itWeights[name] = room.itWeights[name] or 1.0
            room.scores[name]    = room.scores[name] or 0
        end
        startGame()
    end)

    -- poll loop: refresh member list and detect game start
    task.spawn(function()
        while true do
            task.wait(1)
            if not myRoom then continue end
            local room=getRoom()
            if not room then myRoom=nil; isHost=false; continue end

            -- non-host: detect when host starts the game
            if not isHost and room.state=="playing" and STATE.phase=="lobby" then
                startGame()
            end

            if tabExpanded then
                rebuildMembers()
            end
        end
    end)
end  -- HOME SCREEN

--
-- =====================================================
--    PLAYING HUD
-- =====================================================
--
local playRefs = {}
do
    local S = frame(gui,UDim2.new(1,0,0,0),nil,Color3.new(0,0,0))
    S.BackgroundTransparency=1; S.ZIndex=5; S.Visible=false
    screens.playing=S

    local itBadge=frame(S,UDim2.new(0,280,0,48),UDim2.new(0.5,-140,0,12),C.card)
    itBadge.ZIndex=6; corner(itBadge,10); stroke(itBadge,C.gold,1.5,0.25)
    local itHud=lbl(itBadge,"IT: ...",17,C.gold,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    itHud.Size=UDim2.new(1,0,1,0); itHud.ZIndex=7

    local rndBadge=frame(S,UDim2.new(0,150,0,42),UDim2.new(0,12,0,12),C.card)
    rndBadge.ZIndex=6; corner(rndBadge,10); stroke(rndBadge,C.muted,1)
    local rndHud=lbl(rndBadge,"ROUND 1/1",13,C.subtext,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    rndHud.Size=UDim2.new(1,0,1,0); rndHud.ZIndex=7

    local tmrBadge=frame(S,UDim2.new(0,120,0,42),UDim2.new(1,-134,0,12),C.card)
    tmrBadge.ZIndex=6; corner(tmrBadge,10); stroke(tmrBadge,C.muted,1); tmrBadge.Visible=false
    local tmrHud=lbl(tmrBadge,"2:00",18,C.subtext,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    tmrHud.Size=UDim2.new(1,0,1,0); tmrHud.ZIndex=7

    local scnBadge=frame(S,UDim2.new(0,140,0,38),UDim2.new(1,-154,0,66),C.card)
    scnBadge.ZIndex=6; corner(scnBadge,10); stroke(scnBadge,C.muted,1)
    local scnHud=lbl(scnBadge,"SCAN 10s",12,C.subtext,Enum.Font.GothamBold,Enum.TextXAlignment.Center)
    scnHud.Size=UDim2.new(1,0,1,0); scnHud.ZIndex=7

    playRefs={itLbl=itHud,itBadge=itBadge,roundLbl=rndHud,
              timerLbl=tmrHud,timerBadge=tmrBadge,scanLbl=scnHud}
end

--
-- =====================================================
--    END / SCOREBOARD SCREEN
-- =====================================================
--
local endRefs = {}
do
    local S=frame(gui,UDim2.new(1,0,1,0),nil,C.bg)
    S.ZIndex=30; S.Visible=false
    screens.endscreen=S

    local card=frame(S,UDim2.new(0,460,0,500),UDim2.new(0.5,-230,0.5,-250),C.panel)
    card.ZIndex=31; corner(card,16); stroke(card,C.accent,1.5,0.35); pad(card,24)

    local eTitle=Instance.new("TextLabel",card)
    eTitle.Size=UDim2.new(1,0,0,40); eTitle.BackgroundTransparency=1
    eTitle.TextColor3=C.accent; eTitle.Font=Enum.Font.GothamBlack
    eTitle.TextSize=28; eTitle.Text="GAME OVER"
    eTitle.TextXAlignment=Enum.TextXAlignment.Center; eTitle.ZIndex=32

    local winL=Instance.new("TextLabel",card)
    winL.Size=UDim2.new(1,0,0,28); winL.BackgroundTransparency=1
    winL.TextColor3=C.gold; winL.Font=Enum.Font.GothamBold
    winL.TextSize=18; winL.Text=""
    winL.TextXAlignment=Enum.TextXAlignment.Center; winL.ZIndex=32

    local scoreBox=frame(card,UDim2.new(1,0,0,290),nil,Color3.new(0,0,0))
    scoreBox.BackgroundTransparency=1; scoreBox.ZIndex=32
    listL(scoreBox,8)

    local paBtn=makeBtn(card,"PLAY AGAIN",C.accent,function()
        local room=getRoom()
        if room then
            STATE.roundNum=1; STATE.itPlayer=nil
            for k in pairs(room.scores) do room.scores[k]=0 end
            for k in pairs(room.itWeights) do room.itWeights[k]=1.0 end
            room.state="playing"
            startGame()
        end
    end)
    paBtn.TextSize=14; paBtn.ZIndex=32

    local mmBtn=makeBtn(card,"MAIN MENU",C.muted,function()
        leaveRoom()
        showScreen("lobby")
    end)
    mmBtn.ZIndex=32

    endRefs={winnerLbl=winL, scoreBox=scoreBox}
end

--
-- =====================================================
--    ESP ENGINE
-- =====================================================
--
local skeletonPairs={
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local function espCol(p)
    return (STATE.itPlayer and p==STATE.itPlayer) and C.gold or C.danger
end

local function destroyESP(p)
    if activeESP[p] then pcall(function() activeESP[p].bb:Destroy() end); activeESP[p]=nil end
    if screenArrows[p] then pcall(function() screenArrows[p]:Destroy() end); screenArrows[p]=nil end
    if skeletonLines[p] then
        for _,e in pairs(skeletonLines[p]) do pcall(function() e.line:Remove() end) end
        skeletonLines[p]=nil
    end
end

local function destroyAllESP()
    for p in pairs(activeESP) do destroyESP(p) end
end

local function createESP(p)
    if activeESP[p] then return end
    if not p.Character then return end
    local root=p.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local col=espCol(p)

    local bb=Instance.new("BillboardGui",root)
    bb.Size=UDim2.new(0,160,0,52); bb.AlwaysOnTop=true
    bb.StudsOffset=Vector3.new(0,3.5,0); bb.LightInfluence=0; bb.ZIndex=8

    local bg=frame(bb,UDim2.new(1,0,1,0),nil,Color3.fromHex("#080808"))
    bg.BackgroundTransparency=0.2; corner(bg,6); stroke(bg,col,1.4,0.1)

    local bl=Instance.new("TextLabel",bg)
    bl.Size=UDim2.new(1,-8,1,0); bl.Position=UDim2.new(0,4,0,0)
    bl.BackgroundTransparency=1; bl.TextColor3=col
    bl.Font=Enum.Font.GothamBold; bl.TextSize=13
    bl.TextXAlignment=Enum.TextXAlignment.Left; bl.ZIndex=9

    local arrow=Instance.new("ImageLabel",gui)
    arrow.Size=UDim2.new(0,28,0,28); arrow.AnchorPoint=Vector2.new(0.5,0.5)
    arrow.BackgroundTransparency=1; arrow.Image="rbxassetid://6034818372"
    arrow.ImageColor3=col; arrow.Visible=false; arrow.ZIndex=8

    activeESP[p]={bb=bb,bg=bg,label=bl}
    screenArrows[p]=arrow
    skeletonLines[p]={}

    for _,pair in ipairs(skeletonPairs) do
        local l=Drawing.new("Line")
        l.Thickness=2; l.Color=col; l.Transparency=0.15; l.Visible=false
        table.insert(skeletonLines[p],{line=l,parts=pair})
    end
end

--
-- =====================================================
--    TAG LOGIC
-- =====================================================
--
local tagCooldown=false

local function doTag(tagged)
    if tagCooldown then return end
    if STATE.phase~="playing" then return end
    if STATE.itPlayer~=LP then return end
    tagCooldown=true

    local room=getRoom()
    if not room then return end

    STATE.itPlayer=tagged
    room.itPlayer=tagged.Name
    room.scores[tagged.Name]=(room.scores[tagged.Name] or 0)+1
    room.itWeights[tagged.Name]=(room.itWeights[tagged.Name] or 1)*2

    playSound(SFX.tag,4)
    toast("TAGGED "..tagged.Name.."!",C.safe,2)

    if playRefs.itLbl then
        playRefs.itLbl.Text="IT: "..tagged.Name
        playRefs.itLbl.TextColor3=C.gold
    end

    local flash=Instance.new("Frame",gui)
    flash.Size=UDim2.new(1,0,1,0); flash.BackgroundColor3=C.accent
    flash.BackgroundTransparency=0.4; flash.BorderSizePixel=0; flash.ZIndex=40
    TweenService:Create(flash,TweenInfo.new(0.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
        {BackgroundTransparency=1}):Play()
    task.delay(0.6,function() flash:Destroy() end)

    if room.settings.rounds==1 then
        task.delay(0.8,function() endRound() end)
    else
        task.delay(0.8,function() startPlayPhase() end)
    end

    task.delay(CFG.TAG_COOLDOWN,function() tagCooldown=false end)
end

--
-- =====================================================
--    GAME START / PLAY PHASE / END
-- =====================================================
--
local function pickIT()
    local room=getRoom()
    if not room then return end
    local party=getRoomPlayers()
    if #party==0 then return end

    local totalW=0
    for _,p in pairs(party) do
        totalW=totalW+(1/(room.itWeights[p.Name] or 1))
    end
    local roll=math.random()*totalW
    local cum=0
    for _,p in pairs(party) do
        cum=cum+(1/(room.itWeights[p.Name] or 1))
        if roll<=cum then
            STATE.itPlayer=p
            room.itPlayer=p.Name
            room.itWeights[p.Name]=(room.itWeights[p.Name] or 1)*2
            return
        end
    end
    -- fallback
    STATE.itPlayer=party[1]
    room.itPlayer=party[1].Name
end

startGame=function()
    local room=getRoom()
    if not room then return end

    STATE.phase="playing"
    STATE.roundNum=STATE.roundNum or 1

    pickIT()

    local itName=STATE.itPlayer and STATE.itPlayer.Name or "?"
    local isItMe=STATE.itPlayer==LP
    playSound(SFX.start,2)
    toast(isItMe and "YOU ARE IT!" or (itName.." is IT!"),
          isItMe and C.danger or C.gold, 3)

    showScreen("playing")
    startPlayPhase()
end

startPlayPhase=function()
    local room=getRoom()
    STATE.playActive=true

    -- sync itPlayer from room in case we're the guest
    if room and room.itPlayer then
        local p=Players:FindFirstChild(room.itPlayer)
        if p then STATE.itPlayer=p end
    end

    if playRefs.itLbl then
        local isItMe=STATE.itPlayer==LP
        playRefs.itLbl.Text=isItMe and "!! YOU ARE IT" or ("IT: "..(STATE.itPlayer and STATE.itPlayer.Name or "?"))
        playRefs.itLbl.TextColor3=isItMe and C.danger or C.gold
        local room2=getRoom()
        playRefs.roundLbl.Text="ROUND "..STATE.roundNum.."/"..(room2 and room2.settings.rounds or 1)
        if room2 then playRefs.timerBadge.Visible=room2.settings.useTimer end
    end

    -- scan loop
    task.spawn(function()
        while STATE.playActive do
            for i=CFG.SCAN_INTERVAL,1,-1 do
                if not STATE.playActive then break end
                if playRefs.scanLbl then
                    playRefs.scanLbl.Text="SCAN  "..i.."s"
                    playRefs.scanLbl.TextColor3=C.subtext
                end
                task.wait(1)
            end
            if not STATE.playActive then break end
            if playRefs.scanLbl then
                playRefs.scanLbl.Text="* SCANNING"
                playRefs.scanLbl.TextColor3=C.safe
            end
            for _,p in pairs(getRoomPlayers()) do
                if p~=LP then createESP(p) end
            end
            task.wait(CFG.SCAN_DURATION)
            destroyAllESP()
        end
    end)

    -- timer
    local room2=getRoom()
    if room2 and room2.settings.useTimer then
        task.spawn(function()
            local rem=room2.settings.timerSecs
            while STATE.playActive and rem>0 do
                local m=math.floor(rem/60); local s=rem%60
                if playRefs.timerLbl then
                    playRefs.timerLbl.Text=string.format("%d:%02d",m,s)
                    playRefs.timerLbl.TextColor3=rem<=10 and C.danger or C.subtext
                end
                task.wait(1); rem=rem-1
            end
            if STATE.playActive then endRound() end
        end)
    end

    -- poll for IT changes from other clients tagging
    task.spawn(function()
        while STATE.playActive do
            task.wait(0.5)
            local room3=getRoom()
            if not room3 then break end
            if room3.itPlayer then
                local p=Players:FindFirstChild(room3.itPlayer)
                if p and p~=STATE.itPlayer then
                    STATE.itPlayer=p
                    local isItMe=p==LP
                    if playRefs.itLbl then
                        playRefs.itLbl.Text=isItMe and "!! YOU ARE IT" or ("IT: "..p.Name)
                        playRefs.itLbl.TextColor3=isItMe and C.danger or C.gold
                    end
                    if isItMe then
                        toast("YOU ARE NOW IT!",C.danger,2)
                        playSound(SFX.tag,3)
                    end
                end
            end
            -- detect round/game end triggered by host
            if room3.state=="end" and STATE.phase=="playing" then
                endRound()
            end
        end
    end)
end

endRound=function()
    STATE.playActive=false; STATE.phase="end"; destroyAllESP()
    local room=getRoom()
    if not room then return end

    STATE.roundNum=STATE.roundNum+1
    if STATE.roundNum<=(room.settings.rounds or 1) then
        toast("Round "..(STATE.roundNum-1).." done!",C.accent,2)
        task.delay(2,function()
            STATE.phase="playing"
            if isHost then pickIT() end
            startPlayPhase()
        end)
        return
    end

    -- game over
    room.state="end"
    showScreen("endscreen"); playSound(SFX.win,2)

    local winner,minT=nil,math.huge
    for name,t in pairs(room.scores) do
        if t<minT then minT=t; winner=name end
    end
    if endRefs.winnerLbl then
        endRefs.winnerLbl.Text=winner and (winner.." WINS!") or "TIE!"
    end
    if endRefs.scoreBox then
        for _,c in pairs(endRefs.scoreBox:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local sorted={}
        for name,t in pairs(room.scores) do table.insert(sorted,{name=name,tags=t}) end
        table.sort(sorted,function(a,b) return a.tags<b.tags end)
        for rank,entry in ipairs(sorted) do
            local isW=(entry.name==winner)
            local row=frame(endRefs.scoreBox,UDim2.new(1,0,0,48),nil,C.card)
            corner(row,8); stroke(row,isW and C.gold or C.stroke,1.2,isW and 0.1 or 0)
            row.ZIndex=34
            local rl=lbl(row,tostring(rank),20,isW and C.gold or C.subtext,Enum.Font.GothamBlack)
            rl.Size=UDim2.new(0,36,1,0); rl.Position=UDim2.new(0,10,0,0)
            rl.TextXAlignment=Enum.TextXAlignment.Center; rl.ZIndex=35
            local nl=lbl(row,entry.name,14,isW and C.gold or C.text,Enum.Font.GothamBold)
            nl.Size=UDim2.new(0.55,0,1,0); nl.Position=UDim2.new(0,50,0,0); nl.ZIndex=35
            local sl=lbl(row,entry.tags.." tags",12,C.subtext,Enum.Font.Gotham,Enum.TextXAlignment.Right)
            sl.Size=UDim2.new(0.3,-8,1,0); sl.Position=UDim2.new(0.7,0,0,0); sl.ZIndex=35
        end
    end
end

--
-- =====================================================
--    RENDER LOOP
-- =====================================================
--
RunService.RenderStepped:Connect(function()
    if STATE.phase~="playing" then return end
    local lpChar=LP.Character
    local lpRoot=lpChar and lpChar:FindFirstChild("HumanoidRootPart")
    if not lpRoot then return end
    local cam=workspace.CurrentCamera
    local vp=cam.ViewportSize
    local center=vp/2

    -- sync IT hud every frame
    if playRefs.itLbl and STATE.itPlayer then
        local isItMe=STATE.itPlayer==LP
        playRefs.itLbl.Text=isItMe and "!! YOU ARE IT" or ("IT: "..STATE.itPlayer.Name)
        playRefs.itLbl.TextColor3=isItMe and C.danger or C.gold
        local st=playRefs.itBadge:FindFirstChildOfClass("UIStroke")
        if st then st.Color=isItMe and C.danger or C.gold end
    end

    for player,data in pairs(activeESP) do
        local char=player.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if not(char and root) then continue end

        local dist=(lpRoot.Position-root.Position).Magnitude
        local col=espCol(player)

        data.label.TextColor3=col
        local st=data.bg:FindFirstChildOfClass("UIStroke")
        if st then st.Color=col end
        screenArrows[player].ImageColor3=col
        data.label.Text=player.Name..(player==STATE.itPlayer and " [IT]" or "").."\n"..math.floor(dist).."m"

        if dist<=CFG.TAG_DISTANCE then doTag(player) end

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
    destroyESP(p)
    if myRoom and Rooms[myRoom] then
        local members=Rooms[myRoom].members
        for i,name in ipairs(members) do
            if name==p.Name then table.remove(members,i); break end
        end
    end
    if STATE.itPlayer==p then STATE.itPlayer=nil end
end)

--
--  INIT
--
STATE.phase="lobby"
task.delay(0.1,function() setExpanded(true) end)
print("[StrafeTag v3] loaded - create or join a room")
