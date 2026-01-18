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
	BaseColor: Color3,
	RelativeX: number,
	RelativeZ: number,
	Height: number,
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
	FrontCenter: Vector3,
	FrontDirection: Vector3,
	MoveDirection: Vector3,
}

local FrontsFolder: Folder? = nil
local ActiveVisuals: { [string]: VisualFront } = {}
local DistantThunderSounds: { Sound } = {}

local CloudTemplateCache: { [string]: { MeshPart } } = {}
local CloudContainer: Folder? = nil

local IsInsideFront = false
local CurrentFrontId: string? = nil

local CLOUD_SCALE_MULTIPLIER = 2.0

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
	Cloud.CastShadow = true
	return Cloud
end

local function GetFrontDirection(PointA: Vector3, PointB: Vector3): Vector3
	local Dir = PointB - PointA
	if Dir.Magnitude < 0.001 then
		return Vector3.new(0, 0, 1)
	end
	return Dir.Unit
end

local function GetMoveDirection(Velocity: Vector3): Vector3
	if Velocity.Magnitude < 0.001 then
		return Vector3.new(1, 0, 0)
	end
	return Velocity.Unit
end

local function ApplyGrayNoise(BaseColor: Color3, Variance: number): Color3
	local Noise = (math.random() - 0.5) * 2 * Variance
	return Color3.new(
		math.clamp(BaseColor.R + Noise, 0, 1),
		math.clamp(BaseColor.G + Noise, 0, 1),
		math.clamp(BaseColor.B + Noise, 0, 1)
	)
end

local function CalculateCloudColor(
	TypeConfig: typeof(WeatherFronts.Types.Storm),
	NormalizedDistFromCenter: number
): Color3
	local BlendAlpha = math.clamp(NormalizedDistFromCenter, 0, 1)
	BlendAlpha = BlendAlpha * BlendAlpha

	local BaseColor = WeatherFronts.LerpColor3(TypeConfig.CoreColor, TypeConfig.EdgeColor, BlendAlpha)
	return ApplyGrayNoise(BaseColor, TypeConfig.ColorVariance)
end

local function ReadFrontFromInstance(Config: Configuration): VisualFront?
	local FrontType = Config:GetAttribute("Type")
	if not FrontType then
		return nil
	end

	local PointA = Vector3.new(
		Config:GetAttribute("PointAX") or 0,
		Config:GetAttribute("PointAY") or 0,
		Config:GetAttribute("PointAZ") or 0
	)
	local PointB = Vector3.new(
		Config:GetAttribute("PointBX") or 0,
		Config:GetAttribute("PointBY") or 0,
		Config:GetAttribute("PointBZ") or 0
	)
	local Velocity = Vector3.new(
		Config:GetAttribute("VelocityX") or 0,
		Config:GetAttribute("VelocityY") or 0,
		Config:GetAttribute("VelocityZ") or 0
	)

	return {
		Id = Config.Name,
		Type = FrontType,
		PointA = PointA,
		PointB = PointB,
		Width = Config:GetAttribute("Width") or 400,
		Velocity = Velocity,
		Intensity = Config:GetAttribute("Intensity") or 0.5,
		Clouds = {},
		LightningTimer = 0,
		NextLightningTime = 5 + math.random() * 10,
		FrontCenter = (PointA + PointB) / 2,
		FrontDirection = GetFrontDirection(PointA, PointB),
		MoveDirection = GetMoveDirection(Velocity),
	}
end

local function GenerateCloudsForFront(Visual: VisualFront)
	local TypeConfig = WeatherFronts.Types[Visual.Type]
	if not TypeConfig then
		return
	end

	local CloudFolderName = "Light"
	if Visual.Type == "Storm" then
		CloudFolderName = "Storm"
	elseif Visual.Type == "Rain" then
		CloudFolderName = "Rain"
	end

	local Templates = LoadCloudTemplates(CloudFolderName)
	if #Templates == 0 then
		return
	end

	local FrontLength = (Visual.PointB - Visual.PointA).Magnitude
	local HalfWidth = Visual.Width / 2
	local HalfLength = FrontLength / 2

	local BaseRotation = math.deg(math.atan2(Visual.MoveDirection.X, Visual.MoveDirection.Z))
	local CloudCount = TypeConfig.CloudCount

	for _CloudIndex = 1, CloudCount do
		local Template = Templates[math.random(1, #Templates)]
		local Cloud = CreateCloudMesh(Template)

		local RelativeX = (math.random() - 0.5) * 2 * HalfWidth * 0.85
		local RelativeZ = (math.random() - 0.5) * 2 * HalfLength * 0.9

		local DistFromCenterX = math.abs(RelativeX) / HalfWidth
		local DistFromCenterZ = math.abs(RelativeZ) / HalfLength
		local NormalizedDist = math.sqrt(DistFromCenterX^2 + DistFromCenterZ^2) / math.sqrt(2)

		local Height = TypeConfig.BaseCloudHeight + (math.random() - 0.5) * 2 * TypeConfig.CloudHeightVariance

		if NormalizedDist < 0.3 then
			Height = Height + 50 + math.random() * 30
		end

		local WorldPosition = Visual.FrontCenter
			+ Visual.MoveDirection * RelativeX
			+ Visual.FrontDirection * RelativeZ
			+ Vector3.new(0, Height, 0)

		local ScaleVariance = 1 + (math.random() - 0.5) * 2 * TypeConfig.CloudScaleVariance
		local BaseScale = TypeConfig.BaseCloudScale * CLOUD_SCALE_MULTIPLIER * ScaleVariance

		if NormalizedDist < 0.35 then
			BaseScale = BaseScale * (1.2 + math.random() * 0.3)
		end

		Cloud.Size = BaseScale
		Cloud.Position = WorldPosition

		local CloudRotation = BaseRotation + (math.random() - 0.5) * 30
		Cloud.Orientation = Vector3.new(0, CloudRotation, 0)

		local CloudColor = CalculateCloudColor(TypeConfig, NormalizedDist)
		Cloud.Color = CloudColor
		Cloud.Transparency = 0
		Cloud.Material = Enum.Material.SmoothPlastic

		if CloudContainer then
			Cloud.Parent = CloudContainer
		else
			Cloud.Parent = Workspace
		end

		local CloudInfo: CloudData = {
			Mesh = Cloud,
			FrontId = Visual.Id,
			BaseColor = CloudColor,
			RelativeX = RelativeX,
			RelativeZ = RelativeZ,
			Height = Height,
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
	Visual.FrontCenter = Visual.FrontCenter + Movement

	for _, CloudInfo in ipairs(Visual.Clouds) do
		CloudInfo.Mesh.Position = CloudInfo.Mesh.Position + Movement
	end
end

local function UpdateCloudVisibility(Visual: VisualFront, PlayerPos: Vector3)
	local Config = WeatherConfig.Fronts
	local MaxRender = Config.MaxRenderDistance

	for _, CloudInfo in ipairs(Visual.Clouds) do
		local CloudPos = CloudInfo.Mesh.Position
		local CloudDistance = (Vector3.new(CloudPos.X, 0, CloudPos.Z) - Vector3.new(PlayerPos.X, 0, PlayerPos.Z)).Magnitude

		if CloudDistance > MaxRender then
			CloudInfo.Mesh.Transparency = 1
			continue
		end

		local DistanceFade = 1
		local FadeStartDistance = MaxRender * 0.8
		if CloudDistance > FadeStartDistance then
			DistanceFade = 1 - (CloudDistance - FadeStartDistance) / (MaxRender - FadeStartDistance)
		end

		local FinalTransparency = 1 - DistanceFade
		CloudInfo.Mesh.Transparency = math.clamp(FinalTransparency, 0, 0.95)
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

	local FlashCount = math.random(1, math.min(4, #Visual.Clouds))
	local SelectedIndices: { [number]: boolean } = {}

	for _ = 1, FlashCount do
		local RandomIndex: number
		local Attempts = 0
		repeat
			RandomIndex = math.random(1, #Visual.Clouds)
			Attempts = Attempts + 1
		until not SelectedIndices[RandomIndex] or Attempts > 10

		if Attempts <= 10 then
			SelectedIndices[RandomIndex] = true

			local CloudInfo = Visual.Clouds[RandomIndex]
			local OrigColor = CloudInfo.Mesh.Color
			local OrigTransparency = CloudInfo.Mesh.Transparency

			CloudInfo.Mesh.Color = Color3.fromRGB(255, 255, 255)
			CloudInfo.Mesh.Transparency = math.max(0, OrigTransparency - 0.4)

			task.delay(0.08 + math.random() * 0.06, function()
				if CloudInfo.Mesh and CloudInfo.Mesh.Parent then
					CloudInfo.Mesh.Color = OrigColor
					CloudInfo.Mesh.Transparency = OrigTransparency
				end
			end)
		end
	end

	local FlashStrength = math.clamp(1 - Distance / Config.DistantLightningMaxDistance, 0.08, 0.45)
	local OrigBrightness = Lighting.Brightness
	Lighting.Brightness = OrigBrightness + FlashStrength

	task.delay(0.1, function()
		Lighting.Brightness = OrigBrightness
	end)

	local InsideFront = WeatherFronts.IsInsideFront(PlayerPos, Visual.PointA, Visual.PointB, Visual.Width)

	if not InsideFront and Distance <= Config.DistantThunderMaxDistance and #DistantThunderSounds > 0 then
		local ThunderDelay = Distance * Config.ThunderDelayPerStud
		local VolumeScale = math.clamp(1 - Distance / Config.DistantThunderMaxDistance, 0.15, 0.6)

		task.delay(ThunderDelay, function()
			local Sound = DistantThunderSounds[math.random(1, #DistantThunderSounds)]
			Sound.Volume = VolumeScale * 0.5
			Sound:Play()
		end)
	end
end

local function UpdateFrontLightning(Visual: VisualFront, PlayerPos: Vector3, DeltaTime: number)
	Visual.LightningTimer = Visual.LightningTimer + DeltaTime

	if Visual.LightningTimer >= Visual.NextLightningTime then
		TriggerDistantLightning(Visual, PlayerPos)
		Visual.LightningTimer = 0
		Visual.NextLightningTime = 4 + math.random() * 12
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

	Visual.MoveDirection = GetMoveDirection(Visual.Velocity)
	Visual.FrontDirection = GetFrontDirection(Visual.PointA, Visual.PointB)
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

	CloudContainer = Instance.new("Folder")
	CloudContainer.Name = "WeatherClouds"
	CloudContainer.Parent = Workspace

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