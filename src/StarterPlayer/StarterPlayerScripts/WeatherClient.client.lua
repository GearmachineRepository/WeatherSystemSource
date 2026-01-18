--!strict

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = Shared:WaitForChild("Weather")
local WeatherConfig = require(Weather:WaitForChild("WeatherConfig"))
local WeatherEffects = require(Weather:WaitForChild("WeatherEffects"))
local WeatherFronts = require(Weather:WaitForChild("WeatherFronts"))
local FrontVisualizer = require(Weather:WaitForChild("FrontVisualizer"))

local WeatherAssets = ReplicatedStorage:WaitForChild("WeatherAssets")
local ParticlesFolder = WeatherAssets:WaitForChild("Particles")
local SoundsFolder = WeatherAssets:WaitForChild("Sounds")

local LightningBolt = require(Shared:WaitForChild("Modules"):WaitForChild("LightningBolt"))

local LocalPlayer = Players.LocalPlayer :: Player
local ZonesFolder = workspace:WaitForChild("Zones")
local Terrain = workspace:WaitForChild("Terrain")
local Clouds = Terrain:WaitForChild("Clouds") :: Clouds
local Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") :: Atmosphere?

local Camera = workspace.CurrentCamera :: Camera

type EffectTargets = {
	CloudCover: number,
	CloudDensity: number,
	CloudColor: Color3,
	AtmosphereDensity: number,
	AtmosphereOffset: number,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	AtmosphereGlare: number,
	AtmosphereHaze: number,
	LightingAmbient: Color3,
	LightingBrightness: number,
	LightingExposure: number,
	RainEnabled: boolean,
	RainRate: number,
	SnowEnabled: boolean,
	SnowRate: number,
	RainVolume: number,
	ThunderVolume: number,
	WindBreezeVolume: number,
	WindGustyVolume: number,
	WindSpeedMin: number,
	WindSpeedMax: number,
}

type InterpolationData = {
	StartTime: number,
	Duration: number,
	From: EffectTargets,
	To: EffectTargets,
}

local CurrentZone: Instance? = nil
local CurrentBiome: string = WeatherConfig.DEFAULT_BIOME
local CurrentWeatherState: string = "Clear"
local CurrentTargets: EffectTargets? = nil
local Interpolation: InterpolationData? = nil

local CurrentFrontId: string? = nil
local CurrentFrontDepth: number = 0
local LastFrontType: string? = nil

local RainEmitter: ParticleEmitter? = nil
local SnowEmitter: ParticleEmitter? = nil
local ParticlePart: Part? = nil

local RainSound: Sound? = nil
local ThunderSounds: { Sound } = {}
local ThunderCloseSounds: { Sound } = {}
local WindBreezeSound: Sound? = nil
local WindGustySound: Sound? = nil

local LastZoneCheck = 0
local LastLightningTime = 0
local NextLightningInterval = 0
local BaseLightingBrightness = Lighting.Brightness

local CurrentWindSpeed = 0
local TargetWindSpeedMin = 2
local TargetWindSpeedMax = 6
local WindDirection = Vector3.new(1, 0, 0.3).Unit
local WindSeed = math.random(1, 10000)

local TargetWindBreezeVolume = 0.15
local TargetWindGustyVolume = 0

local OverlapParams = OverlapParams.new()

local function SetupOverlapParams()
	OverlapParams.FilterType = Enum.RaycastFilterType.Include
	OverlapParams.FilterDescendantsInstances = { ZonesFolder }
end

local function SetupParticles()
	ParticlePart = Instance.new("Part")
	ParticlePart.Name = "WeatherParticles"
	ParticlePart.Anchored = true
	ParticlePart.CanCollide = false
	ParticlePart.CanQuery = false
	ParticlePart.CanTouch = false
	ParticlePart.Transparency = 1
	ParticlePart.Size = Vector3.new(100, 1, 100)
	ParticlePart.Parent = Camera

	local RainTemplate = ParticlesFolder:FindFirstChild("Rain")
	if RainTemplate then
		local RainEmitterTemplate = RainTemplate:FindFirstChildOfClass("ParticleEmitter")
		if RainEmitterTemplate then
			RainEmitter = RainEmitterTemplate:Clone()
			RainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
			RainEmitter.Parent = ParticlePart
			RainEmitter.Enabled = false
			RainEmitter.Rate = 0
		end
	end

	local SnowTemplate = ParticlesFolder:FindFirstChild("Snow")
	if SnowTemplate then
		local SnowEmitterTemplate = SnowTemplate:FindFirstChildOfClass("ParticleEmitter")
		if SnowEmitterTemplate then
			SnowEmitter = SnowEmitterTemplate:Clone()
			SnowEmitter.Orientation = Enum.ParticleOrientation.FacingCamera
			SnowEmitter.Parent = ParticlePart
			SnowEmitter.Enabled = false
			SnowEmitter.Rate = 0
		end
	end
end

local function SetupSounds()
	local RainTemplate = SoundsFolder:FindFirstChild("RainAmbient")
	if RainTemplate and RainTemplate:IsA("Sound") then
		RainSound = RainTemplate:Clone()
		RainSound.Parent = Camera
		RainSound.Volume = 0
		RainSound.Looped = true
		RainSound:Play()
	end

	local BreezeTemplate = SoundsFolder:FindFirstChild("WindBreeze")
	if BreezeTemplate and BreezeTemplate:IsA("Sound") then
		WindBreezeSound = BreezeTemplate:Clone()
		WindBreezeSound.Parent = Camera
		WindBreezeSound.Volume = 0
		WindBreezeSound.Looped = true
		WindBreezeSound:Play()
	end

	local GustyTemplate = SoundsFolder:FindFirstChild("WindGusty")
	if GustyTemplate and GustyTemplate:IsA("Sound") then
		WindGustySound = GustyTemplate:Clone()
		WindGustySound.Parent = Camera
		WindGustySound.Volume = 0
		WindGustySound.Looped = true
		WindGustySound:Play()
	end

	for _, Child in ipairs(SoundsFolder:GetChildren()) do
		if Child:IsA("Sound") then
			if Child.Name:find("ThunderClose") then
				local CloseClone = Child:Clone()
				CloseClone.Parent = Camera
				CloseClone.Volume = 0
				table.insert(ThunderCloseSounds, CloseClone)
			elseif Child.Name:find("Thunder") then
				local ThunderClone = Child:Clone()
				ThunderClone.Parent = Camera
				ThunderClone.Volume = 0
				table.insert(ThunderSounds, ThunderClone)
			end
		end
	end
end

local function GetZoneFromPart(Part: BasePart): Instance?
	local Parent = Part.Parent
	if Parent and Parent:IsA("Folder") and Parent.Parent == ZonesFolder then
		return Parent
	elseif Parent == ZonesFolder then
		return Part
	end
	return nil
end

local function GetZoneVolume(Zone: Instance): number
	local TotalVolume = 0

	if Zone:IsA("Folder") then
		for _, Child in ipairs(Zone:GetChildren()) do
			if Child:IsA("BasePart") then
				local Size = Child.Size
				TotalVolume = TotalVolume + Size.X * Size.Y * Size.Z
			end
		end
	elseif Zone:IsA("BasePart") then
		local Size = Zone.Size
		TotalVolume = Size.X * Size.Y * Size.Z
	end

	return TotalVolume
end

local function GetZonePriority(Zone: Instance): number
	return Zone:GetAttribute("Priority") or 0
end

local function GetZoneBiome(Zone: Instance): string
	return Zone:GetAttribute("Biome") or WeatherConfig.DEFAULT_BIOME
end

local function DetectCurrentZone(): Instance?
	local Character = LocalPlayer.Character
	if not Character then
		return nil
	end

	local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
	if not HumanoidRootPart or not HumanoidRootPart:IsA("BasePart") then
		return nil
	end

	local Position = HumanoidRootPart.Position
	local TouchingParts = workspace:GetPartBoundsInRadius(Position, 1, OverlapParams)

	if #TouchingParts == 0 then
		return nil
	end

	local CandidateZones: { Instance } = {}
	local SeenZones: { [Instance]: boolean } = {}

	for _, Part in ipairs(TouchingParts) do
		local Zone = GetZoneFromPart(Part)
		if Zone and not SeenZones[Zone] then
			SeenZones[Zone] = true
			table.insert(CandidateZones, Zone)
		end
	end

	if #CandidateZones == 0 then
		return nil
	end

	if #CandidateZones == 1 then
		return CandidateZones[1]
	end

	table.sort(CandidateZones, function(ZoneA, ZoneB)
		local PriorityA = GetZonePriority(ZoneA)
		local PriorityB = GetZonePriority(ZoneB)

		if PriorityA ~= PriorityB then
			return PriorityA > PriorityB
		end

		local VolumeA = GetZoneVolume(ZoneA)
		local VolumeB = GetZoneVolume(ZoneB)
		return VolumeA < VolumeB
	end)

	return CandidateZones[1]
end

local function GetWeatherStateFromFront(FrontType: string, FrontIntensity: number, Biome: string, Depth: number): string
	return WeatherFronts.GetWeatherForFront(FrontType, FrontIntensity, Biome, Depth)
end

local function GetEffectsForState(StateName: string): typeof(WeatherEffects.States.Clear)
	local Effects = WeatherEffects.States[StateName]
	if not Effects then
		Effects = WeatherEffects.States.Clear
	end
	return Effects
end

local function GetBiomeBaseline(BiomeName: string): EffectTargets
	local DefaultEffects = WeatherEffects.States.Clear
	local BiomeConfig = WeatherConfig.Biomes[BiomeName]

	local Baseline: EffectTargets = {
		CloudCover = DefaultEffects.Clouds.Cover,
		CloudDensity = DefaultEffects.Clouds.Density,
		CloudColor = DefaultEffects.Clouds.Color,
		AtmosphereDensity = DefaultEffects.Atmosphere.Density,
		AtmosphereOffset = DefaultEffects.Atmosphere.Offset,
		AtmosphereColor = DefaultEffects.Atmosphere.Color,
		AtmosphereDecay = DefaultEffects.Atmosphere.Decay,
		AtmosphereGlare = DefaultEffects.Atmosphere.Glare,
		AtmosphereHaze = DefaultEffects.Atmosphere.Haze,
		LightingAmbient = DefaultEffects.Lighting.Ambient,
		LightingBrightness = DefaultEffects.Lighting.Brightness,
		LightingExposure = DefaultEffects.Lighting.ExposureCompensation,
		RainEnabled = DefaultEffects.Particles.Rain.Enabled,
		RainRate = DefaultEffects.Particles.Rain.Rate or 0,
		SnowEnabled = DefaultEffects.Particles.Snow.Enabled,
		SnowRate = DefaultEffects.Particles.Snow.Rate or 0,
		RainVolume = DefaultEffects.Sounds.Rain.Volume,
		ThunderVolume = DefaultEffects.Sounds.Thunder.Volume,
		WindBreezeVolume = DefaultEffects.Sounds.WindBreeze.Volume,
		WindGustyVolume = DefaultEffects.Sounds.WindGusty.Volume,
		WindSpeedMin = DefaultEffects.Wind.SpeedMin,
		WindSpeedMax = DefaultEffects.Wind.SpeedMax,
	}

	if BiomeConfig then
		if BiomeConfig.Lighting then
			Baseline.LightingAmbient = BiomeConfig.Lighting.Ambient
			Baseline.LightingBrightness = BiomeConfig.Lighting.Brightness
			Baseline.LightingExposure = BiomeConfig.Lighting.ExposureCompensation
		end

		if BiomeConfig.Atmosphere then
			Baseline.AtmosphereDensity = BiomeConfig.Atmosphere.Density
			Baseline.AtmosphereOffset = BiomeConfig.Atmosphere.Offset
			Baseline.AtmosphereColor = BiomeConfig.Atmosphere.Color
			Baseline.AtmosphereDecay = BiomeConfig.Atmosphere.Decay
			Baseline.AtmosphereGlare = BiomeConfig.Atmosphere.Glare
			Baseline.AtmosphereHaze = BiomeConfig.Atmosphere.Haze
		end
	end

	return Baseline
end

local function GetZoneOverrides(Zone: Instance, Baseline: EffectTargets): EffectTargets
	local Overrides = Baseline

	local AmbientR = Zone:GetAttribute("AmbientR")
	local AmbientG = Zone:GetAttribute("AmbientG")
	local AmbientB = Zone:GetAttribute("AmbientB")
	if AmbientR and AmbientG and AmbientB then
		Overrides.LightingAmbient = Color3.new(AmbientR, AmbientG, AmbientB)
	end

	local Brightness = Zone:GetAttribute("Brightness")
	if Brightness then
		Overrides.LightingBrightness = Brightness
	end

	local Exposure = Zone:GetAttribute("ExposureCompensation")
	if Exposure then
		Overrides.LightingExposure = Exposure
	end

	local AtmoDensity = Zone:GetAttribute("AtmosphereDensity")
	if AtmoDensity then
		Overrides.AtmosphereDensity = AtmoDensity
	end

	local AtmoOffset = Zone:GetAttribute("AtmosphereOffset")
	if AtmoOffset then
		Overrides.AtmosphereOffset = AtmoOffset
	end

	local AtmoColorR = Zone:GetAttribute("AtmosphereColorR")
	local AtmoColorG = Zone:GetAttribute("AtmosphereColorG")
	local AtmoColorB = Zone:GetAttribute("AtmosphereColorB")
	if AtmoColorR and AtmoColorG and AtmoColorB then
		Overrides.AtmosphereColor = Color3.new(AtmoColorR, AtmoColorG, AtmoColorB)
	end

	local AtmoDecayR = Zone:GetAttribute("AtmosphereDecayR")
	local AtmoDecayG = Zone:GetAttribute("AtmosphereDecayG")
	local AtmoDecayB = Zone:GetAttribute("AtmosphereDecayB")
	if AtmoDecayR and AtmoDecayG and AtmoDecayB then
		Overrides.AtmosphereDecay = Color3.new(AtmoDecayR, AtmoDecayG, AtmoDecayB)
	end

	local AtmoGlare = Zone:GetAttribute("AtmosphereGlare")
	if AtmoGlare then
		Overrides.AtmosphereGlare = AtmoGlare
	end

	local AtmoHaze = Zone:GetAttribute("AtmosphereHaze")
	if AtmoHaze then
		Overrides.AtmosphereHaze = AtmoHaze
	end

	return Overrides
end

local function GetDefaultTargets(): EffectTargets
	local Baseline = GetBiomeBaseline(CurrentBiome)

	if CurrentZone then
		Baseline = GetZoneOverrides(CurrentZone, Baseline)
	end

	return Baseline
end

local function GetTargetsFromEffects(Effects: typeof(WeatherEffects.States.Clear)): EffectTargets
	return {
		CloudCover = Effects.Clouds.Cover,
		CloudDensity = Effects.Clouds.Density,
		CloudColor = Effects.Clouds.Color,
		AtmosphereDensity = Effects.Atmosphere.Density,
		AtmosphereOffset = Effects.Atmosphere.Offset,
		AtmosphereColor = Effects.Atmosphere.Color,
		AtmosphereDecay = Effects.Atmosphere.Decay,
		AtmosphereGlare = Effects.Atmosphere.Glare,
		AtmosphereHaze = Effects.Atmosphere.Haze,
		LightingAmbient = Effects.Lighting.Ambient,
		LightingBrightness = Effects.Lighting.Brightness,
		LightingExposure = Effects.Lighting.ExposureCompensation,
		RainEnabled = Effects.Particles.Rain.Enabled,
		RainRate = Effects.Particles.Rain.Rate or 0,
		SnowEnabled = Effects.Particles.Snow.Enabled,
		SnowRate = Effects.Particles.Snow.Rate or 0,
		RainVolume = Effects.Sounds.Rain.Volume,
		ThunderVolume = Effects.Sounds.Thunder.Volume,
		WindBreezeVolume = Effects.Sounds.WindBreeze.Volume,
		WindGustyVolume = Effects.Sounds.WindGusty.Volume,
		WindSpeedMin = Effects.Wind.SpeedMin,
		WindSpeedMax = Effects.Wind.SpeedMax,
	}
end

local function GetCurrentAppliedTargets(): EffectTargets
	return {
		CloudCover = Clouds.Cover,
		CloudDensity = Clouds.Density,
		CloudColor = Clouds.Color,
		AtmosphereDensity = Atmosphere and Atmosphere.Density or 0.3,
		AtmosphereOffset = Atmosphere and Atmosphere.Offset or 0.1,
		AtmosphereColor = Atmosphere and Atmosphere.Color or Color3.new(0.78, 0.78, 0.78),
		AtmosphereDecay = Atmosphere and Atmosphere.Decay or Color3.new(0.36, 0.47, 0.59),
		AtmosphereGlare = Atmosphere and Atmosphere.Glare or 0.5,
		AtmosphereHaze = Atmosphere and Atmosphere.Haze or 1.5,
		LightingAmbient = Lighting.Ambient,
		LightingBrightness = Lighting.Brightness,
		LightingExposure = Lighting.ExposureCompensation,
		RainEnabled = RainEmitter and RainEmitter.Enabled or false,
		RainRate = RainEmitter and RainEmitter.Rate or 0,
		SnowEnabled = SnowEmitter and SnowEmitter.Enabled or false,
		SnowRate = SnowEmitter and SnowEmitter.Rate or 0,
		RainVolume = RainSound and RainSound.Volume or 0,
		ThunderVolume = 0,
		WindBreezeVolume = WindBreezeSound and WindBreezeSound.Volume or 0.15,
		WindGustyVolume = WindGustySound and WindGustySound.Volume or 0,
		WindSpeedMin = TargetWindSpeedMin,
		WindSpeedMax = TargetWindSpeedMax,
	}
end

local function LerpNumber(From: number, To: number, Alpha: number): number
	return From + (To - From) * Alpha
end

local function LerpColor3(From: Color3, To: Color3, Alpha: number): Color3
	return Color3.new(
		LerpNumber(From.R, To.R, Alpha),
		LerpNumber(From.G, To.G, Alpha),
		LerpNumber(From.B, To.B, Alpha)
	)
end

local function SmoothStepAlpha(Alpha: number): number
	return Alpha * Alpha * (3 - 2 * Alpha)
end

local function CloudCoverAlpha(Depth: number): number
	local Boosted = math.min(1, Depth * 1.8)
	return Boosted * Boosted * (3 - 2 * Boosted)
end

local function ApplyTargetsWithDepth(
	ClearTargets: EffectTargets,
	WeatherTargets: EffectTargets,
	DepthAlpha: number
)
	local SmoothedDepth = SmoothStepAlpha(DepthAlpha)
	local CloudDepth = CloudCoverAlpha(DepthAlpha)

	Clouds.Cover = LerpNumber(ClearTargets.CloudCover, WeatherTargets.CloudCover, CloudDepth)
	Clouds.Density = LerpNumber(ClearTargets.CloudDensity, WeatherTargets.CloudDensity, CloudDepth)
	Clouds.Color = LerpColor3(ClearTargets.CloudColor, WeatherTargets.CloudColor, CloudDepth)

	if Atmosphere then
		Atmosphere.Density = LerpNumber(ClearTargets.AtmosphereDensity, WeatherTargets.AtmosphereDensity, SmoothedDepth)
		Atmosphere.Offset = LerpNumber(ClearTargets.AtmosphereOffset, WeatherTargets.AtmosphereOffset, SmoothedDepth)
		Atmosphere.Color = LerpColor3(ClearTargets.AtmosphereColor, WeatherTargets.AtmosphereColor, SmoothedDepth)
		Atmosphere.Decay = LerpColor3(ClearTargets.AtmosphereDecay, WeatherTargets.AtmosphereDecay, SmoothedDepth)
		Atmosphere.Glare = LerpNumber(ClearTargets.AtmosphereGlare, WeatherTargets.AtmosphereGlare, SmoothedDepth)
		Atmosphere.Haze = LerpNumber(ClearTargets.AtmosphereHaze, WeatherTargets.AtmosphereHaze, SmoothedDepth)
	end

	Lighting.Ambient = LerpColor3(ClearTargets.LightingAmbient, WeatherTargets.LightingAmbient, SmoothedDepth)
	BaseLightingBrightness = LerpNumber(ClearTargets.LightingBrightness, WeatherTargets.LightingBrightness, SmoothedDepth)
	Lighting.Brightness = BaseLightingBrightness
	Lighting.ExposureCompensation = LerpNumber(ClearTargets.LightingExposure, WeatherTargets.LightingExposure, SmoothedDepth)

	if RainEmitter then
		local RainRate = LerpNumber(ClearTargets.RainRate, WeatherTargets.RainRate, SmoothedDepth)
		RainEmitter.Enabled = RainRate > 0
		RainEmitter.Rate = RainRate
	end

	if SnowEmitter then
		local SnowRate = LerpNumber(ClearTargets.SnowRate, WeatherTargets.SnowRate, SmoothedDepth)
		SnowEmitter.Enabled = SnowRate > 0
		SnowEmitter.Rate = SnowRate
	end

	if RainSound then
		RainSound.Volume = LerpNumber(ClearTargets.RainVolume, WeatherTargets.RainVolume, SmoothedDepth)
	end

	TargetWindSpeedMin = LerpNumber(ClearTargets.WindSpeedMin, WeatherTargets.WindSpeedMin, SmoothedDepth)
	TargetWindSpeedMax = LerpNumber(ClearTargets.WindSpeedMax, WeatherTargets.WindSpeedMax, SmoothedDepth)
	TargetWindBreezeVolume = LerpNumber(ClearTargets.WindBreezeVolume, WeatherTargets.WindBreezeVolume, SmoothedDepth)
	TargetWindGustyVolume = LerpNumber(ClearTargets.WindGustyVolume, WeatherTargets.WindGustyVolume, SmoothedDepth)
end

local function ApplyTargets(Targets: EffectTargets, Alpha: number, From: EffectTargets)
	Clouds.Cover = LerpNumber(From.CloudCover, Targets.CloudCover, Alpha)
	Clouds.Density = LerpNumber(From.CloudDensity, Targets.CloudDensity, Alpha)
	Clouds.Color = LerpColor3(From.CloudColor, Targets.CloudColor, Alpha)

	if Atmosphere then
		Atmosphere.Density = LerpNumber(From.AtmosphereDensity, Targets.AtmosphereDensity, Alpha)
		Atmosphere.Offset = LerpNumber(From.AtmosphereOffset, Targets.AtmosphereOffset, Alpha)
		Atmosphere.Color = LerpColor3(From.AtmosphereColor, Targets.AtmosphereColor, Alpha)
		Atmosphere.Decay = LerpColor3(From.AtmosphereDecay, Targets.AtmosphereDecay, Alpha)
		Atmosphere.Glare = LerpNumber(From.AtmosphereGlare, Targets.AtmosphereGlare, Alpha)
		Atmosphere.Haze = LerpNumber(From.AtmosphereHaze, Targets.AtmosphereHaze, Alpha)
	end

	Lighting.Ambient = LerpColor3(From.LightingAmbient, Targets.LightingAmbient, Alpha)
	BaseLightingBrightness = LerpNumber(From.LightingBrightness, Targets.LightingBrightness, Alpha)
	Lighting.Brightness = BaseLightingBrightness
	Lighting.ExposureCompensation = LerpNumber(From.LightingExposure, Targets.LightingExposure, Alpha)

	if RainEmitter then
		local RainRate = LerpNumber(From.RainRate, Targets.RainRate, Alpha)
		RainEmitter.Enabled = RainRate > 0
		RainEmitter.Rate = RainRate
	end

	if SnowEmitter then
		local SnowRate = LerpNumber(From.SnowRate, Targets.SnowRate, Alpha)
		SnowEmitter.Enabled = SnowRate > 0
		SnowEmitter.Rate = SnowRate
	end

	if RainSound then
		RainSound.Volume = LerpNumber(From.RainVolume, Targets.RainVolume, Alpha)
	end

	TargetWindSpeedMin = LerpNumber(From.WindSpeedMin, Targets.WindSpeedMin, Alpha)
	TargetWindSpeedMax = LerpNumber(From.WindSpeedMax, Targets.WindSpeedMax, Alpha)
	TargetWindBreezeVolume = LerpNumber(From.WindBreezeVolume, Targets.WindBreezeVolume, Alpha)
	TargetWindGustyVolume = LerpNumber(From.WindGustyVolume, Targets.WindGustyVolume, Alpha)
end

local function StartInterpolation(NewTargets: EffectTargets, Duration: number)
	local CurrentApplied = GetCurrentAppliedTargets()

	Interpolation = {
		StartTime = os.clock(),
		Duration = Duration,
		From = CurrentApplied,
		To = NewTargets,
	}
end

local function OnZoneChanged(NewZone: Instance?)
	local OldBiome = CurrentBiome

	if NewZone then
		CurrentBiome = GetZoneBiome(NewZone)
	else
		CurrentBiome = WeatherConfig.DEFAULT_BIOME
	end

	local BiomeChanged = OldBiome ~= CurrentBiome

	if BiomeChanged and CurrentFrontDepth <= 0 then
		local NewBaseline = GetDefaultTargets()
		StartInterpolation(NewBaseline, WeatherEffects.ZONE_CHANGE_TIME)
	end
end

local RaycastParamsForLightning: RaycastParams = RaycastParams.new()
RaycastParamsForLightning.FilterType = Enum.RaycastFilterType.Exclude

local function GetGroundHitPosition(StartPosition: Vector3, ExcludeInstances: { Instance }): Vector3
	RaycastParamsForLightning.FilterDescendantsInstances = ExcludeInstances

	local RayDirection: Vector3 = Vector3.new(0, -1, 0) * 8000
	local RayResult: RaycastResult? = workspace:Raycast(StartPosition, RayDirection, RaycastParamsForLightning)

	if RayResult then
		return RayResult.Position
	end

	return StartPosition + Vector3.new(0, -8000, 0)
end

local function GetPerpendicularUnitVector(DirectionUnit: Vector3): Vector3
	local UpVector: Vector3 = Vector3.new(0, 1, 0)
	local Perpendicular: Vector3 = DirectionUnit:Cross(UpVector)

	if Perpendicular.Magnitude < 0.001 then
		Perpendicular = DirectionUnit:Cross(Vector3.new(1, 0, 0))
	end

	return Perpendicular.Unit
end

local function CreateBolt(
	AttachmentStart: { WorldPosition: Vector3, WorldAxis: Vector3 },
	AttachmentEnd: { WorldPosition: Vector3, WorldAxis: Vector3 },
	PartCount: number,
	Thickness: number,
	MinRadius: number,
	MaxRadius: number,
	BoltColor: Color3,
	CurveSize0: number,
	CurveSize1: number
): any
	local BoltInstance = LightningBolt.new(AttachmentStart, AttachmentEnd, PartCount)

	BoltInstance.Thickness = Thickness
	BoltInstance.MinRadius = MinRadius
	BoltInstance.MaxRadius = MaxRadius
	BoltInstance.Frequency = 0.8
	BoltInstance.AnimationSpeed = 0
	BoltInstance.Color = BoltColor
	BoltInstance.MinTransparency = 0
	BoltInstance.MaxTransparency = 0
	BoltInstance.ContractFrom = 2
	BoltInstance.CurveSize0 = CurveSize0
	BoltInstance.CurveSize1 = CurveSize1

	return BoltInstance
end

local function TriggerLightningStrike()
	local Character: Model? = LocalPlayer.Character
	if not Character then
		return
	end

	local HumanoidRootPart: BasePart? = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not HumanoidRootPart then
		return
	end

	local TypeConfig = WeatherFronts.Types[LastFrontType or "Storm"]
	local DepthThreshold = TypeConfig and TypeConfig.LightningDepthThreshold or 0.35

	if CurrentFrontDepth < DepthThreshold then
		return
	end

	local LightningConfig = WeatherEffects.Lightning
	local PlayerPosition: Vector3 = HumanoidRootPart.Position
	local ExcludeInstances: { Instance } = { Character, Camera, ZonesFolder }

	local FarStrikeChance: number = LightningConfig.FarStrikeChance or 0.75
	local IsFarStrike: boolean = math.random() < FarStrikeChance

	local StrikeRadiusBase: number = LightningConfig.StrikeRadius
	local StrikeHeightMinBase: number = LightningConfig.StrikeHeightMin
	local StrikeHeightMaxBase: number = LightningConfig.StrikeHeightMax

	local StrikeRadius: number = StrikeRadiusBase
	local StrikeHeightMin: number = StrikeHeightMinBase
	local StrikeHeightMax: number = StrikeHeightMaxBase

	if IsFarStrike then
		StrikeRadius = StrikeRadiusBase * (LightningConfig.FarStrikeRadiusMultiplier or 3)
		StrikeHeightMin = StrikeHeightMinBase * (LightningConfig.FarStrikeHeightMultiplier or 2)
		StrikeHeightMax = StrikeHeightMaxBase * (LightningConfig.FarStrikeHeightMultiplier or 2)
	end

	local MinimumStrikeDistance: number = LightningConfig.MinimumStrikeDistance or 0
	MinimumStrikeDistance = math.clamp(MinimumStrikeDistance, 0, StrikeRadius * 0.9)

	local RandomAngle: number = math.random() * math.pi * 2
	local DistanceAlpha: number = math.random()

	if LightningConfig.PreferDistantStrikes then
		DistanceAlpha = DistanceAlpha * DistanceAlpha
	end

	local RandomDistance: number = MinimumStrikeDistance + DistanceAlpha * (StrikeRadius - MinimumStrikeDistance)

	local StrikeX: number = PlayerPosition.X + math.cos(RandomAngle) * RandomDistance
	local StrikeZ: number = PlayerPosition.Z + math.sin(RandomAngle) * RandomDistance
	local StrikeHeight: number = math.random(StrikeHeightMin, StrikeHeightMax)

	local StartPosition: Vector3 = Vector3.new(StrikeX, StrikeHeight, StrikeZ)
	local EndPosition: Vector3 = GetGroundHitPosition(StartPosition, ExcludeInstances)

	local MainDirection: Vector3 = EndPosition - StartPosition
	if MainDirection.Magnitude < 10 then
		return
	end

	local MainDirectionUnit: Vector3 = MainDirection.Unit
	local SideUnit: Vector3 = GetPerpendicularUnitVector(MainDirectionUnit)

	local BoltColor: Color3 = Color3.fromRGB(210, 210, 255)

	local MainAttachment0 = { WorldPosition = StartPosition, WorldAxis = -MainDirectionUnit }
	local MainAttachment1 = { WorldPosition = EndPosition, WorldAxis = MainDirectionUnit }

	local MainPartCount: number = IsFarStrike and 75 or 50
	local MainThickness: number = IsFarStrike and 1.2 or 2.0
	local MainMaxRadius: number = IsFarStrike and 14 or 7

	local MainCurveSize0: number = (IsFarStrike and 90 or 45) + math.random() * 40
	local MainCurveSize1: number = (IsFarStrike and 70 or 35) + math.random() * 30

	local MainBolt = CreateBolt(
		MainAttachment0,
		MainAttachment1,
		MainPartCount,
		MainThickness,
		0,
		MainMaxRadius,
		BoltColor,
		MainCurveSize0,
		MainCurveSize1
	)

	local BranchCountMin: number = LightningConfig.BranchCountMin or 2
	local BranchCountMax: number = LightningConfig.BranchCountMax or 6
	local BranchCount: number = math.random(BranchCountMin, BranchCountMax)

	local BranchBolts: { any } = {}

	for _ = 1, BranchCount do
		local PercentAlongTrunk: number = 0.22 + math.random() * 0.58
		local TrunkPoint: Vector3 = StartPosition:Lerp(EndPosition, PercentAlongTrunk)

		local BranchStartSideOffset: number = (math.random() - 0.5) * (IsFarStrike and 55 or 30)
		local BranchStartForwardOffset: number = (math.random() - 0.5) * (IsFarStrike and 30 or 18)

		local BranchStartPosition: Vector3 = TrunkPoint + SideUnit * BranchStartSideOffset + MainDirectionUnit * BranchStartForwardOffset

		local RemainingDistance: number = (EndPosition - TrunkPoint).Magnitude
		local BranchLength: number = math.clamp(RemainingDistance * (0.25 + math.random() * 0.35), 60, IsFarStrike and 650 or 300)

		local BranchSideDrift: number = (math.random() - 0.5) * (IsFarStrike and 260 or 140)
		local BranchForwardDrift: number = (math.random() - 0.5) * (IsFarStrike and 140 or 90)

		local BranchEndGuess: Vector3 = BranchStartPosition + MainDirectionUnit * BranchLength + SideUnit * BranchSideDrift + Vector3.new(0, -BranchLength * 0.55, 0) + MainDirectionUnit * BranchForwardDrift

		local BranchEndsInAir: boolean = math.random() < 0.35
		local BranchEndPosition: Vector3

		if BranchEndsInAir then
			BranchEndPosition = BranchEndGuess
		else
			BranchEndPosition = GetGroundHitPosition(BranchEndGuess + Vector3.new(0, 300, 0), ExcludeInstances)
		end

		local BranchDirection: Vector3 = BranchEndPosition - BranchStartPosition
		if BranchDirection.Magnitude < 20 then
			continue
		end

		local BranchDirectionUnit: Vector3 = BranchDirection.Unit
		local BranchAttachment0 = { WorldPosition = BranchStartPosition, WorldAxis = -BranchDirectionUnit }
		local BranchAttachment1 = { WorldPosition = BranchEndPosition, WorldAxis = BranchDirectionUnit }

		local BranchThickness: number = (IsFarStrike and 0.55 or 0.85) * (0.7 + math.random() * 0.5)
		local BranchMaxRadius: number = IsFarStrike and 9 or 6

		local BranchBolt = CreateBolt(BranchAttachment0, BranchAttachment1, math.random(18, 34), BranchThickness, 0, BranchMaxRadius, BoltColor, math.random(10, 40), math.random(10, 40))

		table.insert(BranchBolts, BranchBolt)
	end

	task.delay(LightningConfig.BoltDuration, function()
		MainBolt:Destroy()
		for _, BranchBolt in ipairs(BranchBolts) do
			BranchBolt:Destroy()
		end
	end)

	local OriginalBrightness: number = Lighting.Brightness
	local OriginalExposure: number = Lighting.ExposureCompensation

	local FlashBrightnessMultiplier: number = LightningConfig.FlashBrightnessMultiplier or 2
	local FlashBrightness: number = (LightningConfig.FlashBrightness * FlashBrightnessMultiplier)
	local FlashExposureAdd: number = LightningConfig.FlashExposureAdd or 2.2

	if IsFarStrike then
		FlashBrightness = FlashBrightness * 0.7
		FlashExposureAdd = FlashExposureAdd * 0.7
	end

	Lighting.Brightness = OriginalBrightness + FlashBrightness
	Lighting.ExposureCompensation = OriginalExposure + FlashExposureAdd

	task.delay(LightningConfig.FlashDuration, function()
		local FadeTime: number = LightningConfig.FlashFadeTime or 0.15
		local FadeStartTime: number = os.clock()

		local FadeConnection: RBXScriptConnection?
		FadeConnection = RunService.RenderStepped:Connect(function()
			local Elapsed: number = os.clock() - FadeStartTime
			local FadeAlpha: number = math.clamp(Elapsed / FadeTime, 0, 1)

			Lighting.Brightness = (OriginalBrightness + FlashBrightness) + (BaseLightingBrightness - (OriginalBrightness + FlashBrightness)) * FadeAlpha
			Lighting.ExposureCompensation = (OriginalExposure + FlashExposureAdd) + (OriginalExposure - (OriginalExposure + FlashExposureAdd)) * FadeAlpha

			if FadeAlpha >= 1 then
				if FadeConnection then
					FadeConnection:Disconnect()
					FadeConnection = nil
				end
			end
		end)
	end)

	local StrikeDistance: number = (PlayerPosition - EndPosition).Magnitude

	local ThunderDelay: number = math.random() * (LightningConfig.ThunderDelayMax - LightningConfig.ThunderDelayMin) + LightningConfig.ThunderDelayMin

	if IsFarStrike then
		ThunderDelay = ThunderDelay + math.random() * 1.5
	end

	task.delay(ThunderDelay, function()
		if #ThunderSounds > 0 then
			local ThunderSound: Sound = ThunderSounds[math.random(1, #ThunderSounds)]
			local ThunderVolume: number = CurrentTargets and CurrentTargets.ThunderVolume or 0.5
			local FarMultiplier: number = LightningConfig.FarThunderVolumeMultiplier or 1
			ThunderSound.Volume = ThunderVolume * FarMultiplier
			ThunderSound:Play()
		end
	end)

	local CloseEnabled: boolean = LightningConfig.CloseThunderEnabled == true
	local CloseRadius: number = LightningConfig.CloseThunderRadius or 0

	if CloseEnabled and CloseRadius > 0 and StrikeDistance <= CloseRadius and #ThunderCloseSounds > 0 then
		local CloseDelay: number = math.random() * ((LightningConfig.CloseThunderDelayMax or 0.35) - (LightningConfig.CloseThunderDelayMin or 0.05)) + (LightningConfig.CloseThunderDelayMin or 0.05)

		task.delay(CloseDelay, function()
			local CloseSound: Sound = ThunderCloseSounds[math.random(1, #ThunderCloseSounds)]
			local ThunderVolume: number = CurrentTargets and CurrentTargets.ThunderVolume or 0.5
			local CloseMultiplier: number = LightningConfig.CloseThunderVolumeMultiplier or 1.8
			local Normalized: number = 1 - math.clamp(StrikeDistance / CloseRadius, 0, 1)
			local DistanceBoost: number = 1 + Normalized * 0.6
			CloseSound.Volume = ThunderVolume * CloseMultiplier * DistanceBoost
			CloseSound:Play()
		end)
	end
end

local function UpdateLightning(DeltaTime: number)
	if not WeatherEffects.Lightning.Enabled then
		return
	end

	local TypeConfig = LastFrontType and WeatherFronts.Types[LastFrontType]
	if not TypeConfig or not TypeConfig.HasLightning then
		return
	end

	local IntensityThreshold = TypeConfig.LightningThreshold or 0.55
	local FrontIntensity = FrontVisualizer.GetCurrentFrontIntensity()

	if FrontIntensity < IntensityThreshold then
		return
	end

	local Config = WeatherEffects.Lightning
	local CurrentTime = os.clock()

	if CurrentTime - LastLightningTime >= NextLightningInterval then
		TriggerLightningStrike()
		LastLightningTime = CurrentTime
		NextLightningInterval = math.random() * (Config.IntervalMax - Config.IntervalMin) + Config.IntervalMin
	end
end

local function UpdateParticlePosition()
	if not ParticlePart or not Camera then
		return
	end

	local CameraPosition = Camera.CFrame.Position
	ParticlePart.Position = CameraPosition + Vector3.new(0, 30, 0)
end

local function UpdateInterpolation()
	if not Interpolation then
		return
	end

	local CurrentTime = os.clock()
	local Elapsed = CurrentTime - Interpolation.StartTime
	local Alpha = math.clamp(Elapsed / Interpolation.Duration, 0, 1)

	Alpha = SmoothStepAlpha(Alpha)

	ApplyTargets(Interpolation.To, Alpha, Interpolation.From)

	if Alpha >= 1 then
		Interpolation = nil
	end
end

local function CalculateWindDirection(TimeElapsed: number): Vector3
	local Config = WeatherConfig.Wind
	local BaseDirection = Config.BaseDirection

	local NoiseX = math.noise(TimeElapsed * Config.NoiseTimeScale, 0, WindSeed)
	local NoiseZ = math.noise(TimeElapsed * Config.NoiseTimeScale, 100, WindSeed)

	local Variance = Config.DirectionVariance
	local VariedDirection = Vector3.new(BaseDirection.X + NoiseX * Variance, 0, BaseDirection.Z + NoiseZ * Variance).Unit

	return VariedDirection
end

local function CalculateWindSpeed(TimeElapsed: number, SpeedMin: number, SpeedMax: number): number
	local Config = WeatherConfig.Wind

	local BaseSpeed = (SpeedMin + SpeedMax) / 2
	local SpeedRange = (SpeedMax - SpeedMin) / 2

	local SlowNoise = math.noise(TimeElapsed * Config.NoiseTimeScale, 200, WindSeed)
	local GustNoise = math.noise(TimeElapsed * Config.GustNoiseScale, 300, WindSeed)

	local GustFactor = math.max(0, GustNoise) * Config.GustIntensity

	local Speed = BaseSpeed + SlowNoise * SpeedRange + GustFactor * SpeedRange

	return math.clamp(Speed, SpeedMin * 0.5, SpeedMax * 1.5)
end

local function UpdateWind(DeltaTime: number)
	local TimeElapsed = os.clock()

	WindDirection = CalculateWindDirection(TimeElapsed)
	local TargetSpeed = CalculateWindSpeed(TimeElapsed, TargetWindSpeedMin, TargetWindSpeedMax)

	CurrentWindSpeed = CurrentWindSpeed + (TargetSpeed - CurrentWindSpeed) * math.min(1, DeltaTime * 2)

	workspace.GlobalWind = WindDirection * CurrentWindSpeed

	local Thresholds = WeatherConfig.WindSoundThresholds
	local BreezeVolume = 0
	local GustyVolume = 0

	if CurrentWindSpeed <= Thresholds.BreezeMax then
		BreezeVolume = math.clamp(CurrentWindSpeed / Thresholds.BreezeMax, 0, 1) * TargetWindBreezeVolume
	end

	if CurrentWindSpeed >= Thresholds.GustyMin then
		local GustyRange = 35 - Thresholds.GustyMin
		GustyVolume = math.clamp((CurrentWindSpeed - Thresholds.GustyMin) / GustyRange, 0, 1) * TargetWindGustyVolume
	end

	if CurrentWindSpeed > Thresholds.GustyMin and CurrentWindSpeed < Thresholds.BreezeMax then
		local OverlapStart = Thresholds.GustyMin
		local OverlapEnd = Thresholds.BreezeMax
		local OverlapMid = (OverlapStart + OverlapEnd) / 2

		if CurrentWindSpeed < OverlapMid then
			local Factor = (CurrentWindSpeed - OverlapStart) / (OverlapMid - OverlapStart)
			BreezeVolume = (1 - Factor * 0.5) * TargetWindBreezeVolume
			GustyVolume = (Factor * 0.5) * TargetWindGustyVolume
		else
			local Factor = (CurrentWindSpeed - OverlapMid) / (OverlapEnd - OverlapMid)
			BreezeVolume = (0.5 - Factor * 0.5) * TargetWindBreezeVolume
			GustyVolume = (0.5 + Factor * 0.5) * TargetWindGustyVolume
		end
	end

	if WindBreezeSound then
		WindBreezeSound.Volume = BreezeVolume
	end

	if WindGustySound then
		WindGustySound.Volume = GustyVolume
	end
end

local function CheckZone()
	local CurrentTime = os.clock()

	if CurrentTime - LastZoneCheck < WeatherConfig.ZONE_CHECK_INTERVAL then
		return
	end

	LastZoneCheck = CurrentTime

	local DetectedZone = DetectCurrentZone()

	if DetectedZone ~= CurrentZone then
		CurrentZone = DetectedZone
		OnZoneChanged(DetectedZone)
	end
end

local LastWeatherDebugTime = 0

local function UpdateWeatherFromFronts()
	local FrontId, FrontType, FrontIntensity, Depth = FrontVisualizer.GetFrontAffectingPlayer()

	local DepthChanged = math.abs((Depth or 0) - CurrentFrontDepth) > 0.02
	local FrontChanged = FrontId ~= CurrentFrontId

	CurrentFrontId = FrontId
	CurrentFrontDepth = Depth or 0

	if FrontType then
		LastFrontType = FrontType
	end

	local ClearTargets = GetDefaultTargets()

	if FrontId and FrontType and Depth and Depth > 0 then
		local WeatherState = GetWeatherStateFromFront(FrontType, FrontIntensity or 0.5, CurrentBiome, Depth)
		CurrentWeatherState = WeatherState

		local CurrentTime = os.clock()
		if CurrentTime - LastWeatherDebugTime > 3 then
			LastWeatherDebugTime = CurrentTime
			local EffectiveIntensity = (FrontIntensity or 0.5) + Depth * WeatherConfig.Fronts.DepthIntensityInfluence
		end

		local WeatherEffectsData = GetEffectsForState(WeatherState)
		local WeatherTargets = GetTargetsFromEffects(WeatherEffectsData)

		CurrentTargets = WeatherTargets

		ApplyTargetsWithDepth(ClearTargets, WeatherTargets, Depth)
	else
		CurrentWeatherState = "Clear"
		CurrentTargets = ClearTargets

		if FrontChanged or DepthChanged then
			StartInterpolation(ClearTargets, WeatherEffects.ZONE_CHANGE_TIME)
		end
	end
end

local function OnRenderStep(DeltaTime: number)
	CheckZone()
	FrontVisualizer.Update(DeltaTime)
	UpdateWeatherFromFronts()

	if CurrentFrontDepth <= 0 then
		UpdateInterpolation()
	end

	UpdateParticlePosition()
	UpdateWind(DeltaTime)
	UpdateLightning(DeltaTime)
end

local function Initialize()
	if not Atmosphere then
		Atmosphere = Instance.new("Atmosphere")
		Atmosphere.Parent = Lighting
	end

	SetupOverlapParams()
	SetupParticles()
	SetupSounds()

	NextLightningInterval = WeatherEffects.Lightning.IntervalMin

	FrontVisualizer.Initialize()

	RunService.RenderStepped:Connect(OnRenderStep)
end

Initialize()