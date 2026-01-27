--!strict
--[[
    OceanClientVisuals
    Client-side ocean visuals only - mesh animation and textures.
    Boat physics are handled server-side.

    Place in: StarterPlayer/StarterPlayerScripts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local OceanController = require(OceanSystem.Client.OceanController)
local OceanTexture = require(OceanSystem.Client.OceanTexture)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)
local WaveConfig = require(OceanSystem.Shared.WaveConfig)

local Ocean = workspace:WaitForChild("Ocean", 30)
if not Ocean then
	warn("[OceanClientVisuals] Ocean folder not found in workspace")
	return
end

local OceanMesh = Ocean:WaitForChild("Plane", 10)
if not OceanMesh then
	warn("[OceanClientVisuals] Plane not found in workspace/Ocean")
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

print("[OceanClientVisuals] Ocean visuals started")