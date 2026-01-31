--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local OceanTileManager = require(OceanSystem.Client.OceanTileManager)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)
local OceanConfig = require(OceanSystem.Shared.OceanConfig)

local TILE_SIZE = 1024
local MAX_UPDATE_DISTANCE = OceanConfig.MAX_UPDATE_DISTANCE

local TileTemplate = ReplicatedStorage:WaitForChild("OceanTile", 10) :: Model
if not TileTemplate then
	warn("[OceanClient] OceanTile template not found in ReplicatedStorage")
	return
end

if not TileTemplate.PrimaryPart then
	warn("[OceanClient] OceanTile has no PrimaryPart set")
	return
end

local Configuration = ReplicatedStorage:WaitForChild("OceanConfiguration", 10) :: Configuration
if not Configuration then
	warn("[OceanClient] OceanConfiguration not found in ReplicatedStorage")
	return
end

OceanSettings.Initialize(Configuration)

local Manager = OceanTileManager.new(TileTemplate, TILE_SIZE, MAX_UPDATE_DISTANCE)
Manager:Start()
Manager:SetWaveUpdateRate(60)
Manager:SetMeshSwapDistance(1500)
Manager:EnableTextures({
	FrameRate = 20,
	FolderName = "OceanMaterialVariants",
	DecalFolder = "WaterNormalMaps",
})