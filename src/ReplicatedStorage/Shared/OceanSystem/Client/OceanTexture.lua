--!strict
--[[
    OceanTexture
    Cycles through pre-made MaterialVariants for animated ocean textures.

    Setup:
    1. Run the CreateOceanMaterialVariants command bar script first
    2. Set your ocean mesh's Material to Water (or your BaseMaterial)
    3. Call OceanTexture.new(OceanMesh, Config)
]]

local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFAULT_FRAME_RATE = 24
local DEFAULT_FOLDER_NAME = "OceanMaterialVariants"

local OceanTexture = {}
OceanTexture.__index = OceanTexture

export type OceanTextureConfig = {
    FrameRate: number?,
    FolderName: string?,
    DecalFolder: string?,
}

export type OceanTexture = {
    OceanMesh: MeshPart,
    Variants: {MaterialVariant},
    VariantNames: {string},
    CurrentFrameIndex: number,
    FrameRate: number,
    StartTime: number,
    Running: boolean,
    Connection: RBXScriptConnection?,
    _DecalFolderName: string,
}

type _OceanTexture = typeof(setmetatable({}, OceanTexture))

--[[
    Create a new OceanTexture controller.

    Parameters:
        OceanMesh: MeshPart - The ocean plane mesh
        Config: OceanTextureConfig? - Optional configuration

    Returns:
        OceanTexture instance
]]
function OceanTexture.new(OceanMesh: MeshPart, Config: OceanTextureConfig?): _OceanTexture
    local ResolvedConfig = Config or {} :: OceanTextureConfig

    local self = setmetatable({}, OceanTexture) :: _OceanTexture

    self.OceanMesh = OceanMesh
    self.Variants = {}
    self.VariantNames = {}
    self.CurrentFrameIndex = 1
    self.FrameRate = ResolvedConfig.FrameRate or DEFAULT_FRAME_RATE
    self.StartTime = 0
    self.Running = false
    self.Connection = nil

    local FolderName = ResolvedConfig.FolderName or DEFAULT_FOLDER_NAME
    local DecalFolderName = ResolvedConfig.DecalFolder or "WaterNormalMaps"

    self._DecalFolderName = DecalFolderName
    self:_LoadVariantNames(FolderName)

    return self
end

--[[
    Load variant names from the MaterialService folder.
]]
function OceanTexture:_LoadVariantNames(FolderName: string)
    local VariantFolder = MaterialService:FindFirstChild(FolderName)

    if not VariantFolder then
        warn("[OceanTexture] MaterialVariant folder not found: MaterialService/" .. FolderName)
        return
    end

    local Variants = {}
    for _, Child in pairs(VariantFolder:GetChildren()) do
        if Child:IsA("MaterialVariant") then
            table.insert(Variants, Child)
        end
    end

    table.sort(Variants, function(A, B)
        local NumA = tonumber(A.Name) or 0
        local NumB = tonumber(B.Name) or 0
        return NumA < NumB
    end)

    for _, Variant in ipairs(Variants) do
        table.insert(self.Variants, Variant)
        table.insert(self.VariantNames, Variant.Name)
    end
end

--[[
    Preload all textures from the decal folder.
    Call this before Start() to avoid hitching during animation.
]]
function OceanTexture:Preload()
    local DecalFolder = ReplicatedStorage:FindFirstChild(self._DecalFolderName)

    if not DecalFolder then
        warn("[OceanTexture] Decal folder not found: ReplicatedStorage/" .. self._DecalFolderName)
        return
    end

    local Decals = DecalFolder:GetChildren()

    ContentProvider:PreloadAsync(Decals)
end

--[[
    Main update loop.
    Uses absolute time to calculate frame index, avoiding floating-point accumulation drift.
]]
function OceanTexture:_Update()
    local VariantCount = #self.VariantNames
    if VariantCount == 0 then
        return
    end

    local Elapsed = os.clock() - self.StartTime
    local FrameIndex = math.floor(Elapsed * self.FrameRate) % VariantCount + 1

    if FrameIndex ~= self.CurrentFrameIndex then
        self.CurrentFrameIndex = FrameIndex
        self.OceanMesh.MaterialVariant = self.VariantNames[FrameIndex]
    end
end

--[[
    Start the animation.
]]
function OceanTexture:Start()
    if self.Running then
        warn("[OceanTexture] Already running")
        return
    end

    if #self.VariantNames == 0 then
        warn("[OceanTexture] No MaterialVariants loaded, animation disabled")
        return
    end

    self.Running = true
    self.StartTime = os.clock()
    self.CurrentFrameIndex = 1
    self.OceanMesh.MaterialVariant = self.VariantNames[1]

    self.Connection = RunService.RenderStepped:Connect(function()
        self:_Update()
    end)
end

--[[
    Stop the animation.
]]
function OceanTexture:Stop()
    if not self.Running then
        return
    end

    self.Running = false

    local Connection = self.Connection :: RBXScriptConnection?

    if Connection then
        Connection:Disconnect()
        self.Connection = nil
    end
end

--[[
    Set the animation frame rate.

    Parameters:
        NewFrameRate: number
]]
function OceanTexture:SetFrameRate(NewFrameRate: number)
    self.FrameRate = math.clamp(NewFrameRate, 1, 120)
end

--[[
    Clean up.
]]
function OceanTexture:Destroy()
    self:Stop()
end

return OceanTexture