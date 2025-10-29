-- LocalScript (StarterPlayerScripts)
-- NPC-as-Players targeting GUI + auto-attack (for NPCs disguised as real players)
-- USE ONLY FOR NPCs / TESTING. Do NOT use on real players.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ===== CONFIG =====
local RemoteName = "WeaponHitEvent"          -- remote in ReplicatedStorage (change if needed)
local MAX_RANGE_DEFAULT = 20                 -- max distance to allow attack
local ATTACK_INTERVAL_DEFAULT = 0.25         -- seconds between attacks
local BEHIND_DISTANCE_DEFAULT = 2            -- studs behind target to teleport to

-- Safety / detection:
-- If REQUIRE_ISNPC_FLAG = true, only targets players that have a BoolValue "IsNPC" = true.
-- If false, the script will allow targeting in Studio OR when the flag exists.
local REQUIRE_ISNPC_FLAG = false

-- If you truly want to force targeting (dangerous), set this to true.
local FORCE_ALLOW_REAL_PLAYERS = true
-- ===== END CONFIG =====

local WeaponHitEvent = ReplicatedStorage:FindFirstChild(RemoteName)
if not WeaponHitEvent then
    warn("[NPCKillaura] remote '"..RemoteName.."' not found in ReplicatedStorage. Remote calls will fail.")
end

-- Helper: detect whether a Player is allowed to be targeted (safe guard)
local function playerIsTargetable(player)
    -- Never target yourself
    if not player or player == LocalPlayer then
        return false
    end

    -- Force allow override (dangerous)
    if FORCE_ALLOW_REAL_PLAYERS then
        return true
    end

    -- Studio is allowed for testing
    if RunService:IsStudio() then
        return true
    end

    -- If requirement is enabled, require a BoolValue named "IsNPC" under the Player with value true
    if REQUIRE_ISNPC_FLAG then
        local flag = player:FindFirstChild("IsNPC")
        if flag and flag:IsA("BoolValue") and flag.Value == true then
            return true
        else
            return false
        end
    end

    -- Default allow only if IsNPC flag exists (fallback)
    local fallbackFlag = player:FindFirstChild("IsNPC")
    if fallbackFlag and fallbackFlag:IsA("BoolValue") and fallbackFlag.Value == true then
        return true
    end

    return false
end

-- Helper: get player's character HRP
local function getPlayerHRP(player)
    if not player then return nil end
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    return hrp
end

-- Helper: get local character hrp
local function getLocalHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- Build GUI
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DisguisedNPC_KillauraGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 420)
frame.Position = UDim2.new(0, 20, 0, 60)
frame.BackgroundTransparency = 0.12
frame.BackgroundColor3 = Color3.fromRGB(18,18,18)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 6)
title.BackgroundTransparency = 1
title.Text = "Disguised NPC Targeting (TEST ONLY)"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(220,220,220)
title.Parent = frame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -10, 0, 260)
scroll.Position = UDim2.new(0, 5, 0, 40)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 6
scroll.BackgroundTransparency = 0.12
scroll.BackgroundColor3 = Color3.fromRGB(25,25,25)
scroll.Parent = frame

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.Parent = scroll
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Padding = UDim.new(0, 6)

-- Controls
local controls = Instance.new("Frame")
controls.Size = UDim2.new(1, -10, 0, 100)
controls.Position = UDim2.new(0, 5, 0, 310)
controls.BackgroundTransparency = 1
controls.Parent = frame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.5, -6, 0, 34)
toggleBtn.Position = UDim2.new(0, 0, 0, 0)
toggleBtn.Text = "Auto-Attack: OFF"
toggleBtn.TextSize = 16
toggleBtn.Parent = controls

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0.5, -6, 0, 34)
refreshBtn.Position = UDim2.new(0.5, 6, 0, 0)
refreshBtn.Text = "Refresh List"
refreshBtn.TextSize = 16
refreshBtn.Parent = controls

local function makeLabelledBox(parent, x, y, labelText, defaultValue)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5, -6, 0, 20)
    lbl.Position = UDim2.new(x, 0, y, 36)
    lbl.Text = labelText
    lbl.TextSize = 13
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.5, -6, 0, 20)
    box.Position = UDim2.new(x + 0.5, 6, y, 36)
    box.Text = tostring(defaultValue)
    box.ClearTextOnFocus = false
    box.TextSize = 13
    box.Parent = parent
    return box
end

local rangeBox = makeLabelledBox(controls, 0, 0, "Max Range (studs):", MAX_RANGE_DEFAULT)
local intervalBox = makeLabelledBox(controls, 0, 0.25, "Attack Interval (s):", ATTACK_INTERVAL_DEFAULT)
local behindBox = makeLabelledBox(controls, 0, 0.5, "Behind Dist (studs):", BEHIND_DISTANCE_DEFAULT)

-- State
local selectedPlayer = nil
local playerButtons = {} -- map player -> button

-- Populate player list (players from Players:GetPlayers())
local function refreshPlayerList()
    -- Clear existing
    for p, btn in pairs(playerButtons) do
        if btn and btn.Parent then btn:Destroy() end
    end
    playerButtons = {}

    local players = Players:GetPlayers()
    -- sort by name for stable order
    table.sort(players, function(a,b) return tostring(a.Name) < tostring(b.Name) end)

    local count = 0
    for _, pl in ipairs(players) do
        if pl ~= LocalPlayer then
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -8, 0, 30)
            btn.Position = UDim2.new(0, 4, 0, count * 36)
            btn.Text = pl.Name
            btn.Font = Enum.Font.SourceSans
            btn.TextSize = 14
            btn.BackgroundColor3 = Color3.fromRGB(40,40,40)
            btn.Parent = scroll

            btn.MouseButton1Click:Connect(function()
                -- only select if targetable (safety)
                if playerIsTargetable(pl) then
                    selectedPlayer = pl
                    -- highlight selection
                    for p, b in pairs(playerButtons) do
                        if b then b.BackgroundColor3 = Color3.fromRGB(40,40,40) end
                    end
                    btn.BackgroundColor3 = Color3.fromRGB(60,90,60)
                else
                    -- visually indicate not allowed
                    btn.BackgroundColor3 = Color3.fromRGB(90,50,50)
                    warn("[NPCKillaura] Player '"..pl.Name.."' is not targetable (no IsNPC flag and not in Studio).")
                    wait(0.35)
                    btn.BackgroundColor3 = Color3.fromRGB(40,40,40)
                end
            end)

            playerButtons[pl] = btn
            count = count + 1
        end
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, math.max(0, count * 36))
end

-- initial populate and keep updated when players join/leave
refreshPlayerList()
Players.PlayerAdded:Connect(function() refreshPlayerList() end)
Players.PlayerRemoving:Connect(function() 
    if selectedPlayer and not Players:FindFirstChild(selectedPlayer.Name) then
        selectedPlayer = nil
    end
    refreshPlayerList()
end)

-- Controls
local autoAttack = false
toggleBtn.MouseButton1Click:Connect(function()
    autoAttack = not autoAttack
    toggleBtn.Text = "Auto-Attack: " .. (autoAttack and "ON" or "OFF")
end)

refreshBtn.MouseButton1Click:Connect(refreshPlayerList)

local function parsePositiveNumber(txt, fallback)
    local n = tonumber(txt)
    if n and n > 0 then return n end
    return fallback
end

-- Main attack loop
spawn(function()
    local lastAttack = 0
    while true do
        RunService.Heartbeat:Wait()

        if not autoAttack or not selectedPlayer then
            wait(0.05)
            continue
        end

        -- validate selected player still exists and is targetable
        if not Players:FindFirstChild(selectedPlayer.Name) then
            selectedPlayer = nil
            for p, b in pairs(playerButtons) do if b then b.BackgroundColor3 = Color3.fromRGB(40,40,40) end end
            wait(0.1)
            continue
        end

        if not playerIsTargetable(selectedPlayer) then
            -- safety: deselect
            selectedPlayer = nil
            for p, b in pairs(playerButtons) do if b then b.BackgroundColor3 = Color3.fromRGB(40,40,40) end end
            warn("[NPCKillaura] Selected player is no longer targetable.")
            wait(0.1)
            continue
        end

        local localHRP = getLocalHRP()
        if not localHRP then
            wait(0.2)
            continue
        end

        local targetHRP = getPlayerHRP(selectedPlayer)
        if not targetHRP then
            wait(0.05)
            continue
        end

        -- Live settings
        local maxRange = parsePositiveNumber(rangeBox.Text, MAX_RANGE_DEFAULT)
        local attackInterval = parsePositiveNumber(intervalBox.Text, ATTACK_INTERVAL_DEFAULT)
        local behindDist = parsePositiveNumber(behindBox.Text, BEHIND_DISTANCE_DEFAULT)

        local dist = (localHRP.Position - targetHRP.Position).Magnitude
        if dist > maxRange then
            -- optionally move closer; for now just skip until in range
            wait(0.05)
            continue
        end

        local now = tick()
        if now - lastAttack < attackInterval then
            wait(0.01)
            continue
        end
        lastAttack = now

        -- Teleport behind the target (local only)
        local targetCFrame = targetHRP.CFrame
        local behindCFrame = targetCFrame * CFrame.new(0, 0, - (behindDist + 1))
        local safePos = behindCFrame.Position + Vector3.new(0, 2, 0) -- small upward offset
        local lookAt = CFrame.new(safePos, targetHRP.Position)

        pcall(function()
            localHRP.CFrame = lookAt
        end)

        -- Fire remote (adjust args to match your remote signature)
        if WeaponHitEvent then
            pcall(function()
                WeaponHitEvent:FireServer(targetHRP)
            end)
        end
    end
end)

-- cleanup toggle off on death
LocalPlayer.CharacterRemoving:Connect(function()
    autoAttack = false
    toggleBtn.Text = "Auto-Attack: OFF"
end)

print("[NPCKillaura] GUI ready. Select a player (NPC) from the list and toggle Auto-Attack.")
