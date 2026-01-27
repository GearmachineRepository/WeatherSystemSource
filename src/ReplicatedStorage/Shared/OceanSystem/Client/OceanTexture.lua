--!strict

local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local DEFAULT_FRAME_RATE = 24
local DEFAULT_FOLDER_NAME = "OceanMaterialVariants"
local DEFAULT_DECAL_FOLDER = "WaterNormalMaps"

export type OceanTextureConfig = {
	FrameRate: number?,
	FolderName: string?,
	DecalFolder: string?,
}

local OceanTexture = {}
OceanTexture.__index = OceanTexture

export type OceanTexture = typeof(setmetatable({} :: {
    OceanMesh: MeshPart,
    Variants: {MaterialVariant},
    VariantNames: {string},
    CurrentFrameIndex: number,
    FrameRate: number,
    StartTime: number,
    Running: boolean,
    _DecalFolderName: string,
    _Trove: typeof(Trove.new()),
}, OceanTexture))

function OceanTexture.new(OceanMesh: MeshPart, Config: OceanTextureConfig?): OceanTexture
	local ResolvedConfig = Config or {} :: OceanTextureConfig

	local self = setmetatable({}, OceanTexture) :: any

	self.OceanMesh = OceanMesh
	self.Variants = {}
	self.VariantNames = {}
	self.CurrentFrameIndex = 1
	self.FrameRate = ResolvedConfig.FrameRate or DEFAULT_FRAME_RATE
	self.StartTime = 0
	self.Running = false
	self._Trove = Trove.new()

	local FolderName = ResolvedConfig.FolderName or DEFAULT_FOLDER_NAME
	local DecalFolderName = ResolvedConfig.DecalFolder or DEFAULT_DECAL_FOLDER

	self._DecalFolderName = DecalFolderName
	self:_LoadVariantNames(FolderName)

	return self
end

function OceanTexture._LoadVariantNames(self: OceanTexture, FolderName: string): ()
	local VariantFolder = MaterialService:FindFirstChild(FolderName)

	if not VariantFolder then
		warn("[OceanTexture] MaterialVariant folder not found: MaterialService/" .. FolderName)
		return
	end

	local Variants: {MaterialVariant} = {}
	for _, Child in VariantFolder:GetChildren() do
		if Child:IsA("MaterialVariant") then
			table.insert(Variants, Child)
		end
	end

	table.sort(Variants, function(VariantA, VariantB)
		local NumberA = tonumber(VariantA.Name) or 0
		local NumberB = tonumber(VariantB.Name) or 0
		return NumberA < NumberB
	end)

	for _, Variant in Variants do
		table.insert(self.Variants, Variant)
		table.insert(self.VariantNames, Variant.Name)
	end
end

function OceanTexture.Preload(self: OceanTexture): ()
	local DecalFolder = ReplicatedStorage:FindFirstChild(self._DecalFolderName)
	if not DecalFolder then
		return
	end

	local AssetsToPreload: {Instance} = {}
	for _, Decal in DecalFolder:GetChildren() do
		if Decal:IsA("Decal") or Decal:IsA("Texture") then
			table.insert(AssetsToPreload, Decal)
		end
	end

	if #AssetsToPreload > 0 then
		ContentProvider:PreloadAsync(AssetsToPreload)
	end
end

function OceanTexture._Update(self: OceanTexture): ()
	if #self.Variants == 0 then
		return
	end

	local Elapsed = os.clock() - self.StartTime
	local FrameIndex = math.floor(Elapsed * self.FrameRate) % #self.Variants + 1

	if FrameIndex ~= self.CurrentFrameIndex then
		self.CurrentFrameIndex = FrameIndex
		local VariantName = self.VariantNames[FrameIndex]
		if VariantName then
			self.OceanMesh.MaterialVariant = VariantName
		end
	end
end

function OceanTexture.Start(self: OceanTexture): ()
	if self.Running then
		warn("[OceanTexture] Already running")
		return
	end

	if #self.Variants == 0 then
		warn("[OceanTexture] No variants loaded, cannot start")
		return
	end

	self.Running = true
	self.StartTime = os.clock()

	self._Trove:Connect(RunService.RenderStepped, function()
		self:_Update()
	end)
end

function OceanTexture.Stop(self: OceanTexture): ()
	if not self.Running then
		return
	end

	self.Running = false
	self._Trove:Clean()
end

function OceanTexture.SetFrameRate(self: OceanTexture, FrameRate: number): ()
	self.FrameRate = math.max(1, FrameRate)
end

function OceanTexture.Destroy(self: OceanTexture): ()
	self:Stop()
	self._Trove:Destroy()
	self.Variants = {}
	self.VariantNames = {}
end

return OceanTexture