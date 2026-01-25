--[[
    OceanClient
    Client-side initialization script.
    Place in: StarterPlayerScripts/OceanClient (as a LocalScript)

    This script:
    1. Waits for the ocean mesh to load
    2. Initializes the OceanController
    3. Starts the wave animation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for modules to load
local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local OceanController = require(OceanSystem.Client.OceanController)
local BoatBuoyancy = require(OceanSystem.Client.BoatBuoyancy)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)
local WaveConfig = require(OceanSystem.Shared.WaveConfig)

-- Wait for the ocean mesh (workspace/Ocean/Plane)
local Ocean = workspace:WaitForChild("Ocean", 30)
if not Ocean then
	warn("[OceanClient] Ocean folder not found in workspace")
	return
end

local OceanMesh = Ocean:WaitForChild("Plane", 10)
if not OceanMesh then
	warn("[OceanClient] Plane not found in workspace/Ocean")
	return
end

-- Initialize dynamic ocean settings (reads Attributes from the Plane)
OceanSettings:Initialize(OceanMesh, WaveConfig)

-- Initialize the ocean controller
local Controller = OceanController.new(OceanMesh)
Controller:Start()

print("[OceanClient] Ocean waves initialized")

-- Get the height sampler for boats
local HeightSampler = Controller:GetHeightSampler()

-- Function to set up buoyancy for a boat
local function SetupBoat(BoatModel)
	-- Skip if already set up
	if BoatModel:GetAttribute("BuoyancyEnabled") then
		return
	end

	-- Skip if server is controlling this boat (multiplayer mode)
	if BoatModel:GetAttribute("ServerControlled") then
		print("[OceanClient] Skipping boat (server-controlled):", BoatModel.Name)
		return
	end

	local BuoyancyController = BoatBuoyancy.new(BoatModel, HeightSampler)
	BuoyancyController:SetHeightOffset(1) -- Float 1 stud above surface
	BuoyancyController:SetSmoothing(0.1)  -- Smooth movement
	BuoyancyController:Start()

	BoatModel:SetAttribute("BuoyancyEnabled", true)

	print("[OceanClient] Boat buoyancy enabled for:", BoatModel.Name)
end

-- Auto-setup boats tagged with "Boat" in CollectionService
local CollectionService = game:GetService("CollectionService")

for _, Boat in pairs(CollectionService:GetTagged("Boat")) do
	SetupBoat(Boat)
end

CollectionService:GetInstanceAddedSignal("Boat"):Connect(function(Boat)
	SetupBoat(Boat)
end)

-- Also look for boats in a Boats folder
local BoatsFolder = workspace:FindFirstChild("Boats")
if BoatsFolder then
	for _, Boat in pairs(BoatsFolder:GetChildren()) do
		if Boat:IsA("Model") and Boat.PrimaryPart then
			SetupBoat(Boat)
		end
	end

	BoatsFolder.ChildAdded:Connect(function(Boat)
		if Boat:IsA("Model") then
			task.wait(0.1) -- Wait for model to fully load
			if Boat.PrimaryPart then
				SetupBoat(Boat)
			end
		end
	end)
end

print("[OceanClient] Ready")