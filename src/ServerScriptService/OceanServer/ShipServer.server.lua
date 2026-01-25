--[[
    BoatServer
    Server script for multiplayer Boats.
    Place in: ServerScriptService/Server as a Script

    Handles:
    - Server-side buoyancy (so all clients see same boat position)
    - Reads OceanSettings Attributes for wave intensity

    Player attachment is handled CLIENT-SIDE by BoatAttachmentClient.

    Setup:
    - Tag your Boats with "Boat" in CollectionService
    - OR place them in workspace.Boats folder
    - Boats need PrimaryPart set and a Buoys folder
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local OceanSystem = ReplicatedStorage:WaitForChild("OceanSystem")
local WaveConfig = require(OceanSystem.Shared.WaveConfig)
local GerstnerWave = require(OceanSystem.Shared.GerstnerWave)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)

-- Initialize OceanSettings so server reads Attributes
local Ocean = workspace:WaitForChild("Ocean")
local OceanMesh = Ocean:WaitForChild("Plane")
OceanSettings:Initialize(OceanMesh, WaveConfig)

-- Active Boats
local Boats = {} -- [BoatModel] = { Buoys, CurrentHeight, CurrentPitch, CurrentRoll }

-- Settings
local HEIGHT_OFFSET = -13.1
local SMOOTHING = 0.12

--============================================================================
-- WAVE HEIGHT (Server-side calculation using Gerstner formula)
--============================================================================

local function GetWaveHeight(X, Z)
	local Time = DateTime.now().UnixTimestampMillis / 1000 / WaveConfig.TimeModifier
	local TotalY = WaveConfig.BaseWaterHeight

	for _, Wave in ipairs(WaveConfig.Waves) do
		local K = (2 * math.pi) / Wave.Wavelength
		local A = Wave.Steepness / K
		local D = Wave.Direction.Unit
		local C = math.sqrt(Wave.Gravity / K)
		local F = K * D:Dot(Vector2.new(X, Z)) - C * Time

		TotalY = TotalY + A * math.sin(F)
	end

	return TotalY
end

--============================================================================
-- Boat BUOYANCY
--============================================================================

local function SetupBoat(BoatModel)
	if Boats[BoatModel] then return end
	if not BoatModel.PrimaryPart then
		warn("[BoatServer] Boat missing PrimaryPart:", BoatModel.Name)
		return
	end

	local BuoysFolder = BoatModel:FindFirstChild("Buoys")
	if not BuoysFolder then
		warn("[BoatServer] Boat missing Buoys folder:", BoatModel.Name)
		return
	end

	-- Gather buoys
	local AllBuoys = {}
	local Bow, Stern, Port, Starboard

	for _, Child in ipairs(BuoysFolder:GetChildren()) do
		if Child:IsA("BasePart") then
			table.insert(AllBuoys, Child)
			if Child.Name == "Bow" then Bow = Child
			elseif Child.Name == "Stern" then Stern = Child
			elseif Child.Name == "Port" then Port = Child
			elseif Child.Name == "Starboard" then Starboard = Child
			end
		end
	end

	if #AllBuoys == 0 then
		warn("[BoatServer] Boat has no buoys:", BoatModel.Name)
		return
	end

	-- Anchor the Boat (we control via CFrame)
	BoatModel.PrimaryPart.Anchored = true

	Boats[BoatModel] = {
		AllBuoys = AllBuoys,
		Bow = Bow,
		Stern = Stern,
		Port = Port,
		Starboard = Starboard,
		CurrentHeight = WaveConfig.BaseWaterHeight,
		CurrentPitch = 0,
		CurrentRoll = 0,
	}

	print("[BoatServer] Boat ready:", BoatModel.Name)
end

local function RemoveBoat(BoatModel)
	Boats[BoatModel] = nil
end

local function Lerp(A, B, T)
	return A + (B - A) * T
end

local function UpdateBoat(BoatModel, Data, DeltaTime)
	local PrimaryPart = BoatModel.PrimaryPart
	if not PrimaryPart then return end

	-- Calculate average height
	local TotalHeight = 0
	for _, Buoy in ipairs(Data.AllBuoys) do
		local Pos = Buoy.Position
		TotalHeight = TotalHeight + GetWaveHeight(Pos.X, Pos.Z)
	end
	local TargetHeight = (TotalHeight / #Data.AllBuoys) + HEIGHT_OFFSET

	-- Calculate pitch
	local TargetPitch = 0
	if Data.Bow and Data.Stern then
		local BowHeight = GetWaveHeight(Data.Bow.Position.X, Data.Bow.Position.Z)
		local SternHeight = GetWaveHeight(Data.Stern.Position.X, Data.Stern.Position.Z)
		local Dist = (Vector2.new(Data.Bow.Position.X, Data.Bow.Position.Z) -
			Vector2.new(Data.Stern.Position.X, Data.Stern.Position.Z)).Magnitude
		if Dist > 0.01 then
			TargetPitch = math.atan2(BowHeight - SternHeight, Dist)
		end
	end

	-- Calculate roll
	local TargetRoll = 0
	if Data.Port and Data.Starboard then
		local PortHeight = GetWaveHeight(Data.Port.Position.X, Data.Port.Position.Z)
		local StarboardHeight = GetWaveHeight(Data.Starboard.Position.X, Data.Starboard.Position.Z)
		local Dist = (Vector2.new(Data.Port.Position.X, Data.Port.Position.Z) -
			Vector2.new(Data.Starboard.Position.X, Data.Starboard.Position.Z)).Magnitude
		if Dist > 0.01 then
			TargetRoll = math.atan2(StarboardHeight - PortHeight, Dist)
		end
	end

	-- Smooth
	local SmoothFactor = math.min(SMOOTHING * DeltaTime * 60, 1)
	Data.CurrentHeight = Lerp(Data.CurrentHeight, TargetHeight, SmoothFactor)
	Data.CurrentPitch = Lerp(Data.CurrentPitch, TargetPitch, SmoothFactor)
	Data.CurrentRoll = Lerp(Data.CurrentRoll, TargetRoll, SmoothFactor)

	-- Build new CFrame
	local Pos = PrimaryPart.Position
	local LookVector = PrimaryPart.CFrame.LookVector
	local FlatLook = Vector3.new(LookVector.X, 0, LookVector.Z)
	if FlatLook.Magnitude < 0.01 then
		FlatLook = Vector3.new(0, 0, -1)
	else
		FlatLook = FlatLook.Unit
	end

	local NewPos = Vector3.new(Pos.X, Data.CurrentHeight, Pos.Z)
	local NewCFrame = CFrame.new(NewPos, NewPos + FlatLook)
	NewCFrame = NewCFrame * CFrame.Angles(Data.CurrentPitch, 0, Data.CurrentRoll)

	-- Apply
	BoatModel:PivotTo(NewCFrame)
end

--============================================================================
-- INITIALIZATION
--============================================================================

-- Find Boats tagged "Boat"
for _, Boat in ipairs(CollectionService:GetTagged("Boat")) do
	SetupBoat(Boat)
end

CollectionService:GetInstanceAddedSignal("Boat"):Connect(function(Boat)
	task.wait(0.1)
	SetupBoat(Boat)
end)

CollectionService:GetInstanceRemovedSignal("Boat"):Connect(RemoveBoat)

-- Find Boats in workspace.Boats
local BoatsFolder = workspace:FindFirstChild("Boats")
if BoatsFolder then
	for _, Boat in ipairs(BoatsFolder:GetChildren()) do
		if Boat:IsA("Model") then
			SetupBoat(Boat)
		end
	end

	BoatsFolder.ChildAdded:Connect(function(Boat)
		if Boat:IsA("Model") then
			task.wait(0.1)
			SetupBoat(Boat)
		end
	end)

	BoatsFolder.ChildRemoved:Connect(RemoveBoat)
end

-- Main loop
RunService.Heartbeat:Connect(function(DeltaTime)
	for BoatModel, Data in pairs(Boats) do
		UpdateBoat(BoatModel, Data, DeltaTime)
	end
end)

print("[BoatServer] Ready!")