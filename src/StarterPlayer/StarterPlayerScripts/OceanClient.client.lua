--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local OceanController = require(OceanSystem.Client.OceanController)
local OceanTexture = require(OceanSystem.Client.OceanTexture)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)

local Ocean = workspace:WaitForChild("Ocean", 30)
if not Ocean then
	warn("[OceanClient] Ocean folder not found in workspace")
	return
end

local OceanMesh = Ocean:WaitForChild("Plane", 10) :: MeshPart
if not OceanMesh then
	warn("[OceanClient] Plane not found in workspace/Ocean")
	return
end

OceanSettings.Initialize(OceanMesh)

local Controller = OceanController.new(OceanMesh)
Controller:Start()

local TextureController = OceanTexture.new(OceanMesh, {
	FrameRate = 24,
	FolderName = "OceanMaterialVariants",
	DecalFolder = "WaterNormalMaps",
})
TextureController:Preload()
TextureController:Start()