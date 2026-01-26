--!strict
--[[
    OceanClient
    Client-side initialization script.

    This script:
    1. Waits for the ocean mesh to load
    2. Initializes the OceanController (wave animation)
    3. Initializes the OceanTexture (animated normal maps)
    4. Sets up boat buoyancy
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local OceanController = require(OceanSystem.Client.OceanController)
local OceanTexture = require(OceanSystem.Client.OceanTexture)
local BoatBuoyancy = require(OceanSystem.Client.BoatBuoyancy)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)
local WaveConfig = require(OceanSystem.Shared.WaveConfig)

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

OceanSettings:Initialize(OceanMesh, WaveConfig)

local Controller = OceanController.new(OceanMesh)
Controller:Start()

local TextureController = OceanTexture.new(OceanMesh, {
    FrameRate = 24,
    FolderName = "OceanMaterialVariants",
    DecalFolder = "WaterNormalMaps",
})
TextureController:Preload()
TextureController:Start()

local HeightSampler = Controller:GetHeightSampler()

local function SetupBoat(BoatModel: Model)
    if BoatModel:GetAttribute("BuoyancyEnabled") then
        return
    end

    if BoatModel:GetAttribute("ServerControlled") then
        print("[OceanClient] Skipping boat (server-controlled):", BoatModel.Name)
        return
    end

    local BuoyancyController = BoatBuoyancy.new(BoatModel, HeightSampler)
    BuoyancyController:SetHeightOffset(1)
    BuoyancyController:SetSmoothing(0.1)
    BuoyancyController:Start()

    BoatModel:SetAttribute("BuoyancyEnabled", true)
end

for _, Boat in pairs(CollectionService:GetTagged("Boat")) do
    SetupBoat(Boat)
end

CollectionService:GetInstanceAddedSignal("Boat"):Connect(function(Boat)
    SetupBoat(Boat :: Model)
end)

local BoatsFolder = workspace:FindFirstChild("Boats")
if BoatsFolder then
    for _, Boat in pairs(BoatsFolder:GetChildren()) do
        if Boat:IsA("Model") and Boat.PrimaryPart then
            SetupBoat(Boat)
        end
    end

    BoatsFolder.ChildAdded:Connect(function(Boat: Model)
        if Boat:IsA("Model") then
            task.wait(0.1)
            if Boat.PrimaryPart then
                SetupBoat(Boat)
            end
        end
    end)
end