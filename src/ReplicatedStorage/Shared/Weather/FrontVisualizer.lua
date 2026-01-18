--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = Shared:WaitForChild("Weather")
local WeatherConfig = require(Weather:WaitForChild("WeatherConfig"))
local WeatherFronts = require(Weather:WaitForChild("WeatherFronts"))

local WeatherAssets = ReplicatedStorage:WaitForChild("WeatherAssets")
local CloudMeshesFolder = WeatherAssets:WaitForChild("CloudMeshes")
local SoundsFolder = WeatherAssets:WaitForChild("Sounds")

local FrontVisualizer = {}

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

type CloudData = {
	Mesh: MeshPart,
	FrontId: string,
	Zone: string,
	BaseColor: Color3,
}

type VisualFront = {
	Id: string,
	Type: string,
	PointA: Vector3,
	PointB: Vector3,
	Width: number,
	Velocity: Vector3,
	Intensity: number,
	Clouds: { CloudData },
	LightningTimer: number,
	NextLightningTime: number,
}

local FrontsFolder: Folder? = nil
local ActiveVisuals: { [string]: VisualFront } = {}
local DistantThunderSounds: { Sound } = {}

local CloudTemplateCache: { [string]: { MeshPart } } = {}

local IsInsideFront = false
local CurrentFrontId: string? = nil

local CLOUDS_PER_FRONT = 12
local CLOUD_LAYER_SPACING = 150
local CLOUD_SIZE_MULTIPLIER = 2.5
local ROTATION_VARIANCE = 8

local function LoadCloudTemplates(FolderName: string): { MeshPart }
	if CloudTemplateCache[FolderName] then
		return CloudTemplateCache[FolderName]
	end

	local Templates: { MeshPart } = {}
	local Folder = CloudMeshesFolder:FindFirstChild(FolderName)

	if Folder then
		for _, Child in ipairs(Folder:GetChildren()) do
			if Child:IsA("MeshPart") then
				table.insert(Templates, Child)
			end
		end
	end

	if #Templates == 0 then
		local LightFolder = CloudMeshesFolder:FindFirstChild("Light")
		if LightFolder then
			for _, Child in ipairs(LightFolder:GetChildren()) do
				if Child:IsA("MeshPart") then
					table.insert(Templates, Child)
				end
			end
		end
	end

	CloudTemplateCache[FolderName] = Templates
	return Templates
end

local function CreateCloudMesh(Template: MeshPart): MeshPart
	local Cloud = Template:Clone()
	Cloud.Anchored = true
	Cloud.CanCollide = false
	Cloud.CanQuery = false
	Cloud.CanTouch = false
	Cloud.CastShadow = false
	return Cloud
end

local function GetFrontDirection(PointA: Vector3, PointB: Vector3): Vector3
	local Dir = PointB - PointA
	if Dir.Magnitude < 0.001 then
		return Vector3.new(1, 0, 0)
	end
	return Dir.Unit
end

local function GetFrontCenter(PointA: Vector3, PointB: Vector3): Vector3
	return (PointA + PointB) / 2
end

local function ReadFrontFromInstance(Config: Configuration): VisualFront?
	local FrontType = Config:GetAttribute("Type")
	if not FrontType then
		return nil
	end

	return {
		Id = Config.Name,
		Type = FrontType,
		PointA = Vector3.new(
			Config:GetAttribute("PointAX") or 0,
			Config:GetAttribute("PointAY") or 0,
			Config:GetAttribute("PointAZ") or 0
		),
		PointB = Vector3.new(
			Config:GetAttribute("PointBX") or 0,
			Config:GetAttribute("PointBY") or 0,
			Config:GetAttribute("PointBZ") or 0
		),
		Width = Config:GetAttribute("Width") or 400,
		Velocity = Vector3.new(
			Config:GetAttribute("VelocityX") or 0,
			Config:GetAttribute("VelocityY") or 0,
			Config:GetAttribute("VelocityZ") or 0
		),
		Intensity = Config:GetAttribute("Intensity") or 0.5,
		Clouds = {},
		LightningTimer = 0,
		NextLightningTime = 5 + math.random() * 10,
	}
end

local function GenerateCloudsForFront(Visual: VisualFront)
	local TypeConfig = WeatherFronts.Types[Visual.Type]
	if not TypeConfig then
		return
	end

	local Templates = LoadCloudTemplates(TypeConfig.CloudFolder)
	if #Templates == 0 then
		return
	end

	local FrontDir = GetFrontDirection(Visual.PointA, Visual.PointB)
	local FrontLength = (Visual.PointB - Visual.PointA).Magnitude
	local MoveDir = Visual.Velocity.Unit

	if MoveDir.Magnitude < 0.001 then
		MoveDir = Vector3.new(1, 0, 0)
	end

	local BaseRotation = math.deg(math.atan2(MoveDir.X, MoveDir.Z))

	local BaseHeight = TypeConfig.CloudHeight + 150
	local HeightVariance = TypeConfig.CloudHeightVariance
	local BaseScale = TypeConfig.CloudScale * CLOUD_SIZE_MULTIPLIER
	local ScaleVariance = TypeConfig.CloudScaleVariance

	for Index = 1, CLOUDS_PER_FRONT do
		local Template = Templates[math.random(1, #Templates)]
		local Cloud = CreateCloudMesh(Template)

		local LinePercent = (Index - 1) / math.max(1, CLOUDS_PER_FRONT - 1)
		LinePercent = LinePercent + (math.random() - 0.5) * 0.15

		local BasePos = Visual.PointA:Lerp(Visual.PointB, math.clamp(LinePercent, 0, 1))

		local Zone: string
		local DepthOffset: number
		local CloudColor: Color3

		local Roll = math.random()
		if Roll < 0.2 then
			Zone = "Leading"
			DepthOffset = -(Visual.Width * 0.4 + math.random() * Visual.Width * 0.3)
			CloudColor = TypeConfig.LeadingColor
		elseif Roll < 0.7 then
			Zone = "Core"
			DepthOffset = (math.random() - 0.5) * Visual.Width * 0.5
			CloudColor = TypeConfig.CoreColor
		else
			Zone = "Trailing"
			DepthOffset = Visual.Width * 0.35 + math.random() * Visual.Width * 0.25
			CloudColor = TypeConfig.TrailingColor
		end

		local LateralOffset = (math.random() - 0.5) * CLOUD_LAYER_SPACING
		local Height = BaseHeight + (math.random() - 0.5) * 2 * HeightVariance

		local Position = BasePos
			+ MoveDir * DepthOffset
			+ FrontDir * LateralOffset
			+ Vector3.new(0, Height, 0)

		local ScaleMult = 1 + (math.random() - 0.5) * 2 * ScaleVariance
		local ScaleX = BaseScale.X * ScaleMult * (0.85 + math.random() * 0.3)
		local ScaleY = BaseScale.Y * ScaleMult * (0.7 + math.random() * 0.4)
		local ScaleZ = BaseScale.Z * ScaleMult * (0.85 + math.random() * 0.3)

		Cloud.Size = Vector3.new(ScaleX, ScaleY, ScaleZ)
		Cloud.Position = Position

		local CloudRotation = BaseRotation + (math.random() - 0.5) * 2 * ROTATION_VARIANCE
		Cloud.Orientation = Vector3.new(0, CloudRotation, 0)

		Cloud.Color = CloudColor
		Cloud.Transparency = 0
		Cloud.Material = Enum.Material.SmoothPlastic
		Cloud.Parent = Workspace

		local CloudInfo: CloudData = {
			Mesh = Cloud,
			FrontId = Visual.Id,
			Zone = Zone,
			BaseColor = CloudColor,
		}

		table.insert(Visual.Clouds, CloudInfo)
	end
end

local function DestroyCloudsForFront(Visual: VisualFront)
	for _, CloudInfo in ipairs(Visual.Clouds) do
		CloudInfo.Mesh:Destroy()
	end
	Visual.Clouds = {}
end

local function GetPlayerPosition(): Vector3?
	local Character = LocalPlayer.Character
	if not Character then
		return nil
	end

	local Root = Character:FindFirstChild("HumanoidRootPart")
	if not Root or not Root:IsA("BasePart") then
		return nil
	end

	return Root.Position
end

local function UpdateCloudPositions(Visual: VisualFront, DeltaTime: number)
	local Movement = Visual.Velocity * DeltaTime

	for _, CloudInfo in ipairs(Visual.Clouds) do
		CloudInfo.Mesh.Position = CloudInfo.Mesh.Position + Movement
	end
end

local function UpdateCloudVisibility(Visual: VisualFront, PlayerPos: Vector3)
	local Config = WeatherConfig.Fronts
	local MaxRender = Config.MaxRenderDistance

	local DistanceToFront = WeatherFronts.GetDistanceToFront(PlayerPos, Visual.PointA, Visual.PointB)
	local HalfWidth = Visual.Width / 2
	local InsideFront = DistanceToFront <= HalfWidth

	for _, CloudInfo in ipairs(Visual.Clouds) do
		local CloudPos = CloudInfo.Mesh.Position
		local CloudDistance = (Vector3.new(CloudPos.X, 0, CloudPos.Z) - Vector3.new(PlayerPos.X, 0, PlayerPos.Z)).Magnitude

		if CloudDistance > MaxRender then
			CloudInfo.Mesh.Transparency = 1
			continue
		end

		local DistanceFade = 1
		if CloudDistance > MaxRender * 0.9 then
			local FadeStart = MaxRender * 0.9
			DistanceFade = 1 - (CloudDistance - FadeStart) / (MaxRender - FadeStart)
		end

		local InsideFade = 1
		if InsideFront then
			InsideFade = 0
		end

		local FinalTransparency = 1 - (DistanceFade * InsideFade)
		CloudInfo.Mesh.Transparency = math.clamp(FinalTransparency, 0, 1)
	end
end

local function TriggerDistantLightning(Visual: VisualFront, PlayerPos: Vector3)
	local TypeConfig = WeatherFronts.Types[Visual.Type]
	if not TypeConfig or not TypeConfig.HasLightning then
		return
	end

	local Threshold = TypeConfig.LightningThreshold or 0.6
	if Visual.Intensity < Threshold then
		return
	end

	local Config = WeatherConfig.Fronts
	local Distance = WeatherFronts.GetDistanceToFront(PlayerPos, Visual.PointA, Visual.PointB)

	if Distance > Config.DistantLightningMaxDistance then
		return
	end

	if Distance < Visual.Width / 2 then
		return
	end

	for _, CloudInfo in ipairs(Visual.Clouds) do
		if CloudInfo.Zone == "Core" and math.random() < 0.5 then
			local OrigColor = CloudInfo.Mesh.Color
			local OrigTransparency = CloudInfo.Mesh.Transparency

			CloudInfo.Mesh.Color = Color3.fromRGB(255, 255, 255)
			CloudInfo.Mesh.Transparency = math.max(0, OrigTransparency - 0.3)

			task.delay(0.06 + math.random() * 0.04, function()
				if CloudInfo.Mesh and CloudInfo.Mesh.Parent then
					CloudInfo.Mesh.Color = OrigColor
					CloudInfo.Mesh.Transparency = OrigTransparency
				end
			end)
		end
	end

	local FlashStrength = math.clamp(1 - Distance / Config.DistantLightningMaxDistance, 0.05, 0.35)
	local OrigBrightness = Lighting.Brightness
	Lighting.Brightness = OrigBrightness + FlashStrength

	task.delay(0.08, function()
		Lighting.Brightness = OrigBrightness
	end)

	if Distance <= Config.DistantThunderMaxDistance and #DistantThunderSounds > 0 then
		local ThunderDelay = Distance * Config.ThunderDelayPerStud
		local VolumeScale = math.clamp(1 - Distance / Config.DistantThunderMaxDistance, 0.1, 0.5)

		task.delay(ThunderDelay, function()
			local Sound = DistantThunderSounds[math.random(1, #DistantThunderSounds)]
			Sound.Volume = VolumeScale * 0.4
			Sound:Play()
		end)
	end
end

local function UpdateFrontLightning(Visual: VisualFront, PlayerPos: Vector3, DeltaTime: number)
	Visual.LightningTimer = Visual.LightningTimer + DeltaTime

	if Visual.LightningTimer >= Visual.NextLightningTime then
		TriggerDistantLightning(Visual, PlayerPos)
		Visual.LightningTimer = 0
		Visual.NextLightningTime = 3 + math.random() * 8
	end
end

local function SyncFrontData(Visual: VisualFront, Config: Configuration)
	Visual.PointA = Vector3.new(
		Config:GetAttribute("PointAX") or Visual.PointA.X,
		Config:GetAttribute("PointAY") or Visual.PointA.Y,
		Config:GetAttribute("PointAZ") or Visual.PointA.Z
	)

	Visual.PointB = Vector3.new(
		Config:GetAttribute("PointBX") or Visual.PointB.X,
		Config:GetAttribute("PointBY") or Visual.PointB.Y,
		Config:GetAttribute("PointBZ") or Visual.PointB.Z
	)

	Visual.Velocity = Vector3.new(
		Config:GetAttribute("VelocityX") or Visual.Velocity.X,
		Config:GetAttribute("VelocityY") or Visual.Velocity.Y,
		Config:GetAttribute("VelocityZ") or Visual.Velocity.Z
	)
end

local function OnFrontAdded(Config: Configuration)
	if ActiveVisuals[Config.Name] then
		return
	end

	local Visual = ReadFrontFromInstance(Config)
	if not Visual then
		return
	end

	GenerateCloudsForFront(Visual)
	ActiveVisuals[Visual.Id] = Visual

	Config.AttributeChanged:Connect(function()
		local ExistingVisual = ActiveVisuals[Config.Name]
		if ExistingVisual then
			SyncFrontData(ExistingVisual, Config)
		end
	end)
end

local function OnFrontRemoved(Config: Configuration)
	local Visual = ActiveVisuals[Config.Name]
	if not Visual then
		return
	end

	DestroyCloudsForFront(Visual)
	ActiveVisuals[Config.Name] = nil
end

function FrontVisualizer.Initialize()
	FrontsFolder = ReplicatedStorage:WaitForChild("WeatherFronts", 10)

	for _, Child in ipairs(SoundsFolder:GetChildren()) do
		if Child:IsA("Sound") and Child.Name:find("Thunder") and not Child.Name:find("Close") then
			local Clone = Child:Clone()
			Clone.Parent = Camera
			Clone.Volume = 0
			table.insert(DistantThunderSounds, Clone)
		end
	end

	if FrontsFolder then
		for _, Child in ipairs(FrontsFolder:GetChildren()) do
			if Child:IsA("Configuration") then
				OnFrontAdded(Child)
			end
		end

		FrontsFolder.ChildAdded:Connect(function(Child)
			if Child:IsA("Configuration") then
				OnFrontAdded(Child)
			end
		end)

		FrontsFolder.ChildRemoved:Connect(function(Child)
			if Child:IsA("Configuration") then
				OnFrontRemoved(Child)
			end
		end)
	end
end

function FrontVisualizer.Update(DeltaTime: number)
	local PlayerPos = GetPlayerPosition()
	if not PlayerPos then
		return
	end

	IsInsideFront = false
	CurrentFrontId = nil

	for _, Visual in pairs(ActiveVisuals) do
		UpdateCloudPositions(Visual, DeltaTime)
		UpdateCloudVisibility(Visual, PlayerPos)
		UpdateFrontLightning(Visual, PlayerPos, DeltaTime)

		local Distance = WeatherFronts.GetDistanceToFront(PlayerPos, Visual.PointA, Visual.PointB)
		if Distance <= Visual.Width / 2 then
			IsInsideFront = true
			CurrentFrontId = Visual.Id
		end
	end
end

function FrontVisualizer.IsPlayerInsideFront(): boolean
	return IsInsideFront
end

function FrontVisualizer.GetCurrentFrontId(): string?
	return CurrentFrontId
end

function FrontVisualizer.GetFrontAffectingPlayer(): (string?, string?, number?)
	if not IsInsideFront or not CurrentFrontId then
		return nil, nil, nil
	end

	local Visual = ActiveVisuals[CurrentFrontId]
	if not Visual then
		return nil, nil, nil
	end

	return Visual.Id, Visual.Type, Visual.Intensity
end

function FrontVisualizer.IsPlayerUnderFront(): boolean
	return IsInsideFront
end

function FrontVisualizer.GetCurrentFrontType(): string?
	if not IsInsideFront or not CurrentFrontId then
		return nil
	end

	local Visual = ActiveVisuals[CurrentFrontId]
	if Visual then
		return Visual.Type
	end

	return nil
end

function FrontVisualizer.GetCurrentFrontIntensity(): number
	if not IsInsideFront or not CurrentFrontId then
		return 0
	end

	local Visual = ActiveVisuals[CurrentFrontId]
	if Visual then
		return Visual.Intensity
	end

	return 0
end

return FrontVisualizer