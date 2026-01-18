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
	LocalOffsetX: number,
	LocalOffsetZ: number,
	Height: number,
	BaseColor: Color3,
	BaseScale: Vector3,
	Layer: number,
}

type VisualFront = {
	Id: string,
	Type: string,
	Center: Vector3,
	RadiusX: number,
	RadiusZ: number,
	Rotation: number,
	Velocity: Vector3,
	Intensity: number,
	NoiseSeed: number,
	Clouds: { CloudData },
	LightningTimer: number,
	NextLightningTime: number,
}

local FrontsFolder: Folder? = nil
local ActiveVisuals: { [string]: VisualFront } = {}
local DistantThunderSounds: { Sound } = {}

local CloudTemplates: { MeshPart } = {}
local CloudContainer: Folder? = nil

local CLOUD_UPDATE_THROTTLE = 0.1
local LastCloudUpdate = 0

local function LoadCloudTemplates()
	for _, Subfolder in ipairs(CloudMeshesFolder:GetChildren()) do
		if Subfolder:IsA("Folder") then
			for _, Child in ipairs(Subfolder:GetChildren()) do
				if Child:IsA("MeshPart") then
					table.insert(CloudTemplates, Child)
				end
			end
		end
	end

	if #CloudTemplates == 0 then
		warn("[FrontVisualizer] No cloud templates found in CloudMeshes folder")
	end
end

local function CreateCloudMesh(Template: MeshPart): MeshPart
	local Cloud = Template:Clone()
	Cloud.Anchored = true
	Cloud.CanCollide = false
	Cloud.CanQuery = false
	Cloud.CanTouch = false
	Cloud.CastShadow = true
	Cloud.Material = Enum.Material.SmoothPlastic
	return Cloud
end

local function GetRandomCloudTemplate(): MeshPart?
	if #CloudTemplates == 0 then
		return nil
	end
	return CloudTemplates[math.random(1, #CloudTemplates)]
end

local function ApplyGrayNoise(BaseColor: Color3, Variance: number): Color3
	local Noise = (math.random() - 0.5) * 2 * Variance
	return Color3.new(
		math.clamp(BaseColor.R + Noise, 0, 1),
		math.clamp(BaseColor.G + Noise, 0, 1),
		math.clamp(BaseColor.B + Noise, 0, 1)
	)
end

local function SampleNoise3D(PosX: number, PosZ: number, Seed: number, Scale: number): number
	local NoiseValue = math.noise(PosX * Scale, PosZ * Scale, Seed * 0.01)
	return (NoiseValue + 0.5)
end

local function CalculateCloudDensityAtPoint(
	NormalizedX: number,
	NormalizedZ: number,
	Formation: WeatherFronts.CloudFormation,
	NoiseSeed: number
): number
	local DistanceFromCenter = math.sqrt(NormalizedX * NormalizedX + NormalizedZ * NormalizedZ)

	local BaseDensity = Formation.CoreDensity + (Formation.EdgeDensity - Formation.CoreDensity) * DistanceFromCenter
	BaseDensity = math.clamp(BaseDensity, 0, 1)

	local NoiseValue = SampleNoise3D(NormalizedX * 5, NormalizedZ * 5, NoiseSeed, Formation.NoiseScale * 100)

	if NoiseValue < Formation.NoiseThreshold then
		BaseDensity = BaseDensity * (NoiseValue / Formation.NoiseThreshold) * 0.3
	end

	local EdgeFalloff = 1 - WeatherFronts.SmoothStep(0.7, 1.0, DistanceFromCenter)
	BaseDensity = BaseDensity * EdgeFalloff

	return BaseDensity
end

local function GenerateCloudsForFront(Visual: VisualFront)
	local TypeConfig = WeatherFronts.Types[Visual.Type]
	if not TypeConfig then
		return
	end

	local Formation = TypeConfig.Formation
	local CloudCount = Formation.MinClouds + math.random() * (Formation.MaxClouds - Formation.MinClouds)
	CloudCount = math.floor(CloudCount)

	local PlacedPositions: { { X: number, Y: number, Z: number, Radius: number } } = {}

	local function CheckOverlap(X: number, Y: number, Z: number, Radius: number): boolean
		local MinSeparation = 0.6
		for _, Placed in ipairs(PlacedPositions) do
			local DeltaX = X - Placed.X
			local DeltaY = Y - Placed.Y
			local DeltaZ = Z - Placed.Z
			local Distance = math.sqrt(DeltaX * DeltaX + DeltaY * DeltaY + DeltaZ * DeltaZ)
			local RequiredDistance = (Radius + Placed.Radius) * MinSeparation
			if Distance < RequiredDistance then
				return true
			end
		end
		return false
	end

	local GeneratedCount = 0
	local MaxAttempts = CloudCount * 6

	for Attempt = 1, MaxAttempts do
		if GeneratedCount >= CloudCount then
			break
		end

		local Angle = math.random() * math.pi * 2
		local RadiusFactor = math.sqrt(math.random())

		local NormalizedX = math.cos(Angle) * RadiusFactor
		local NormalizedZ = math.sin(Angle) * RadiusFactor

		local Density = CalculateCloudDensityAtPoint(NormalizedX, NormalizedZ, Formation, Visual.NoiseSeed)

		local SpawnThreshold = 0.15 + (1 - Visual.Intensity) * 0.2
		if math.random() > Density + SpawnThreshold then
			continue
		end

		local Template = GetRandomCloudTemplate()
		if not Template then
			continue
		end

		local Cloud = CreateCloudMesh(Template)

		local LocalOffsetX = NormalizedX * Visual.RadiusX
		local LocalOffsetZ = NormalizedZ * Visual.RadiusZ

		local DistFromCenter = math.sqrt(NormalizedX * NormalizedX + NormalizedZ * NormalizedZ)

		local Layer = math.random(1, Formation.LayerCount)
		local LayerOffset = (Layer - 1) * (Formation.VerticalSpread / Formation.LayerCount)

		local HeightVariance = (math.random() - 0.5) * TypeConfig.CloudHeightVariance
		local Height = TypeConfig.BaseCloudHeight + LayerOffset + HeightVariance

		local LayerRatio = Layer / Formation.LayerCount
		local CoreBonus = 0
		local SizeLift = 0

		if DistFromCenter < 0.15 then
			if LayerRatio > 0.7 then
				CoreBonus = 300 + math.random() * 200
			elseif LayerRatio > 0.5 then
				CoreBonus = 150 + math.random() * 100
			elseif LayerRatio > 0.3 then
				CoreBonus = 50 + math.random() * 50
				SizeLift = 80
			else
				SizeLift = 120
			end
		elseif DistFromCenter < 0.3 then
			if LayerRatio > 0.6 then
				CoreBonus = 180 + math.random() * 120
			elseif LayerRatio > 0.4 then
				CoreBonus = 80 + math.random() * 60
			else
				SizeLift = 60
			end
		elseif DistFromCenter < 0.5 then
			if LayerRatio > 0.5 then
				CoreBonus = 60 + math.random() * 50
			else
				SizeLift = 30
			end
		elseif DistFromCenter < 0.7 then
			if LayerRatio > 0.6 then
				CoreBonus = 20 + math.random() * 30
			end
		end

		Height = Height + CoreBonus + SizeLift

		local ScaleVariance = 1 + (math.random() - 0.5) * 2 * TypeConfig.CloudScaleVariance
		local BaseScale = TypeConfig.BaseCloudScale * ScaleVariance

		if DistFromCenter < 0.15 then
			if LayerRatio > 0.6 then
				local CoreMultiplier = 1.6 + math.random() * 0.4
				BaseScale = BaseScale * CoreMultiplier
				BaseScale = Vector3.new(BaseScale.X, BaseScale.Y * (1.5 + math.random() * 0.4), BaseScale.Z)
			elseif LayerRatio > 0.3 then
				local CoreMultiplier = 1.4 + math.random() * 0.3
				BaseScale = BaseScale * CoreMultiplier
			else
				local CoreMultiplier = 1.2 + math.random() * 0.2
				BaseScale = BaseScale * CoreMultiplier
			end
		elseif DistFromCenter < 0.3 then
			if LayerRatio > 0.5 then
				local CoreMultiplier = 1.4 + math.random() * 0.3
				BaseScale = BaseScale * CoreMultiplier
				BaseScale = Vector3.new(BaseScale.X, BaseScale.Y * (1.3 + math.random() * 0.3), BaseScale.Z)
			else
				local CoreMultiplier = 1.2 + math.random() * 0.2
				BaseScale = BaseScale * CoreMultiplier
			end
		elseif DistFromCenter < 0.5 then
			BaseScale = BaseScale * (1.15 + math.random() * 0.15)
		elseif DistFromCenter > 0.85 then
			BaseScale = BaseScale * (0.55 + math.random() * 0.2)
		end

		local CloudFloor = 180
		local MinimumCloudHeight = CloudFloor + (BaseScale.Y / 2)
		Height = math.max(Height, MinimumCloudHeight)

		local WorldPosition = Visual.Center
			+ Vector3.new(LocalOffsetX, Height, LocalOffsetZ)

		local AverageRadius = (BaseScale.X + BaseScale.Z) / 4

		if CheckOverlap(WorldPosition.X, WorldPosition.Y, WorldPosition.Z, AverageRadius) then
			Cloud:Destroy()
			continue
		end

		table.insert(PlacedPositions, {
			X = WorldPosition.X,
			Y = WorldPosition.Y,
			Z = WorldPosition.Z,
			Radius = AverageRadius,
		})

		Cloud.Size = BaseScale
		Cloud.Position = WorldPosition

		local CloudRotationY = math.random() * 360
		local CloudRotationX = (math.random() - 0.5) * 20
		local CloudRotationZ = (math.random() - 0.5) * 20
		Cloud.Orientation = Vector3.new(CloudRotationX, CloudRotationY, CloudRotationZ)

		local ColorBlend = DistFromCenter * DistFromCenter
		local CloudColor = WeatherFronts.LerpColor3(TypeConfig.CoreColor, TypeConfig.EdgeColor, ColorBlend)
		CloudColor = ApplyGrayNoise(CloudColor, TypeConfig.ColorVariance)

		Cloud.Color = CloudColor
		Cloud.Transparency = 0

		if CloudContainer then
			Cloud.Parent = CloudContainer
		else
			Cloud.Parent = Workspace
		end

		local CloudInfo: CloudData = {
			Mesh = Cloud,
			FrontId = Visual.Id,
			LocalOffsetX = LocalOffsetX,
			LocalOffsetZ = LocalOffsetZ,
			Height = Height,
			BaseColor = CloudColor,
			BaseScale = BaseScale,
			Layer = Layer,
		}

		table.insert(Visual.Clouds, CloudInfo)
		GeneratedCount = GeneratedCount + 1
	end
end

local function DestroyCloudsForFront(Visual: VisualFront)
	for _, CloudInfo in ipairs(Visual.Clouds) do
		if CloudInfo.Mesh and CloudInfo.Mesh.Parent then
			CloudInfo.Mesh:Destroy()
		end
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
	Visual.Center = Visual.Center + Movement

	for _, CloudInfo in ipairs(Visual.Clouds) do
		local NewPosition = Visual.Center + Vector3.new(CloudInfo.LocalOffsetX, CloudInfo.Height, CloudInfo.LocalOffsetZ)
		CloudInfo.Mesh.Position = NewPosition
	end
end

local function UpdateCloudVisibility(Visual: VisualFront, PlayerPos: Vector3)
	local Config = WeatherConfig.Fronts
	local MaxRender = Config.MaxRenderDistance
	local FadeDistance = Config.CloudFadeDistance

	for _, CloudInfo in ipairs(Visual.Clouds) do
		local CloudPos = CloudInfo.Mesh.Position
		local HorizontalDistance = (Vector3.new(CloudPos.X, 0, CloudPos.Z) - Vector3.new(PlayerPos.X, 0, PlayerPos.Z)).Magnitude

		if HorizontalDistance > MaxRender then
			CloudInfo.Mesh.Transparency = 1
			continue
		end

		local DistanceFade = 1
		local FadeStart = MaxRender - FadeDistance
		if HorizontalDistance > FadeStart then
			DistanceFade = 1 - (HorizontalDistance - FadeStart) / FadeDistance
		end

		local FinalTransparency = 1 - DistanceFade
		CloudInfo.Mesh.Transparency = math.clamp(FinalTransparency, 0, 0.98)
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
	local DistanceToEdge = WeatherFronts.GetDistanceToFrontEdge(
		PlayerPos,
		Visual.Center,
		Visual.RadiusX,
		Visual.RadiusZ,
		Visual.Rotation
	)

	local DistanceToCenter = (PlayerPos - Visual.Center).Magnitude
	if DistanceToCenter > Config.DistantLightningMaxDistance then
		return
	end

	local IsInside = WeatherFronts.IsInsideFront(PlayerPos, Visual.Center, Visual.RadiusX, Visual.RadiusZ, Visual.Rotation)

	local FlashCount = math.random(1, math.min(5, #Visual.Clouds))
	local SelectedIndices: { [number]: boolean } = {}

	for _ = 1, FlashCount do
		local RandomIndex: number
		local Attempts = 0
		repeat
			RandomIndex = math.random(1, #Visual.Clouds)
			Attempts = Attempts + 1
		until not SelectedIndices[RandomIndex] or Attempts > 15

		if Attempts <= 15 then
			SelectedIndices[RandomIndex] = true

			local CloudInfo = Visual.Clouds[RandomIndex]
			local OrigColor = CloudInfo.Mesh.Color
			local OrigTransparency = CloudInfo.Mesh.Transparency

			CloudInfo.Mesh.Color = Color3.fromRGB(255, 255, 255)
			CloudInfo.Mesh.Transparency = math.max(0, OrigTransparency - 0.5)

			task.delay(0.06 + math.random() * 0.08, function()
				if CloudInfo.Mesh and CloudInfo.Mesh.Parent then
					CloudInfo.Mesh.Color = OrigColor
					CloudInfo.Mesh.Transparency = OrigTransparency
				end
			end)
		end
	end

	local DistanceNormalized = math.clamp(DistanceToCenter / Config.DistantLightningMaxDistance, 0, 1)
	local FlashStrength = (1 - DistanceNormalized) * 0.5

	if not IsInside then
		FlashStrength = FlashStrength * 0.6
	end

	local OrigBrightness = Lighting.Brightness
	Lighting.Brightness = OrigBrightness + FlashStrength

	task.delay(0.08, function()
		Lighting.Brightness = OrigBrightness
	end)

	if not IsInside and DistanceToCenter <= Config.DistantThunderMaxDistance and #DistantThunderSounds > 0 then
		local ThunderDelay = DistanceToCenter * Config.ThunderDelayPerStud
		local VolumeScale = math.clamp(1 - DistanceToCenter / Config.DistantThunderMaxDistance, 0.1, 0.55)

		task.delay(ThunderDelay, function()
			local Sound = DistantThunderSounds[math.random(1, #DistantThunderSounds)]
			Sound.Volume = VolumeScale * 0.45
			Sound:Play()
		end)
	end
end

local function UpdateFrontLightning(Visual: VisualFront, PlayerPos: Vector3, DeltaTime: number)
	Visual.LightningTimer = Visual.LightningTimer + DeltaTime

	if Visual.LightningTimer >= Visual.NextLightningTime then
		TriggerDistantLightning(Visual, PlayerPos)
		Visual.LightningTimer = 0
		Visual.NextLightningTime = 5 + math.random() * 15
	end
end

local function ReadFrontFromInstance(Config: Configuration): VisualFront?
	local FrontType = Config:GetAttribute("Type")
	if not FrontType then
		return nil
	end

	local Center = Vector3.new(
		Config:GetAttribute("CenterX") or 0,
		Config:GetAttribute("CenterY") or 0,
		Config:GetAttribute("CenterZ") or 0
	)

	local Velocity = Vector3.new(
		Config:GetAttribute("VelocityX") or 0,
		Config:GetAttribute("VelocityY") or 0,
		Config:GetAttribute("VelocityZ") or 0
	)

	return {
		Id = Config.Name,
		Type = FrontType,
		Center = Center,
		RadiusX = Config:GetAttribute("RadiusX") or 400,
		RadiusZ = Config:GetAttribute("RadiusZ") or 350,
		Rotation = Config:GetAttribute("Rotation") or 0,
		Velocity = Velocity,
		Intensity = Config:GetAttribute("Intensity") or 0.5,
		NoiseSeed = Config:GetAttribute("NoiseSeed") or math.random(1, 100000),
		Clouds = {},
		LightningTimer = 0,
		NextLightningTime = 3 + math.random() * 8,
	}
end

local function SyncFrontData(Visual: VisualFront, Config: Configuration)
	Visual.Center = Vector3.new(
		Config:GetAttribute("CenterX") or Visual.Center.X,
		Config:GetAttribute("CenterY") or Visual.Center.Y,
		Config:GetAttribute("CenterZ") or Visual.Center.Z
	)

	Visual.Velocity = Vector3.new(
		Config:GetAttribute("VelocityX") or Visual.Velocity.X,
		Config:GetAttribute("VelocityY") or Visual.Velocity.Y,
		Config:GetAttribute("VelocityZ") or Visual.Velocity.Z
	)

	Visual.Intensity = Config:GetAttribute("Intensity") or Visual.Intensity
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
	FrontsFolder = ReplicatedStorage:WaitForChild("WeatherFronts", 15)

	CloudContainer = Instance.new("Folder")
	CloudContainer.Name = "WeatherClouds"
	CloudContainer.Parent = Workspace

	LoadCloudTemplates()

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

	local CurrentTime = os.clock()
	local ShouldUpdateVisibility = (CurrentTime - LastCloudUpdate) >= CLOUD_UPDATE_THROTTLE

	if ShouldUpdateVisibility then
		LastCloudUpdate = CurrentTime
	end

	for _, Visual in pairs(ActiveVisuals) do
		UpdateCloudPositions(Visual, DeltaTime)

		if ShouldUpdateVisibility then
			UpdateCloudVisibility(Visual, PlayerPos)
		end

		UpdateFrontLightning(Visual, PlayerPos, DeltaTime)
	end
end

function FrontVisualizer.GetFrontAffectingPlayer(): (string?, string?, number?, number?)
	local PlayerPos = GetPlayerPosition()
	if not PlayerPos then
		return nil, nil, nil, nil
	end

	local BestFront: VisualFront? = nil
	local BestDepth = 0

	for _, Visual in pairs(ActiveVisuals) do
		local Depth = WeatherFronts.GetNormalizedDepth(
			PlayerPos,
			Visual.Center,
			Visual.RadiusX,
			Visual.RadiusZ,
			Visual.Rotation
		)

		if Depth > BestDepth then
			BestDepth = Depth
			BestFront = Visual
		end
	end

	if BestFront and BestDepth > 0 then
		return BestFront.Id, BestFront.Type, BestFront.Intensity, BestDepth
	end

	return nil, nil, nil, nil
end

function FrontVisualizer.IsPlayerUnderFront(): boolean
	local _, _, _, Depth = FrontVisualizer.GetFrontAffectingPlayer()
	return Depth ~= nil and Depth > 0
end

function FrontVisualizer.GetCurrentFrontType(): string?
	local _, FrontType, _, _ = FrontVisualizer.GetFrontAffectingPlayer()
	return FrontType
end

function FrontVisualizer.GetCurrentFrontIntensity(): number
	local _, _, Intensity, _ = FrontVisualizer.GetFrontAffectingPlayer()
	return Intensity or 0
end

function FrontVisualizer.GetPlayerDepthInFront(): number
	local _, _, _, Depth = FrontVisualizer.GetFrontAffectingPlayer()
	return Depth or 0
end

function FrontVisualizer.GetActiveFronts(): { [string]: VisualFront }
	return ActiveVisuals
end

return FrontVisualizer