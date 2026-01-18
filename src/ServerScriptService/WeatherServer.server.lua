--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = Shared:WaitForChild("Weather")
local WeatherConfig = require(Weather:WaitForChild("WeatherConfig"))
local WeatherEffects = require(Weather:WaitForChild("WeatherEffects"))
local WeatherFronts = require(Weather:WaitForChild("WeatherFronts"))
local FrontManager = require(Weather:WaitForChild("FrontManager"))

local ZonesFolder = workspace:WaitForChild("Zones")

type ZoneData = {
	Name: string,
	Biome: string,
	Parts: { BasePart },
	Priority: number,
	Volume: number,
	Center: Vector3,
	CurrentState: string,
	PreviousState: string,
	TimeInState: number,
	AffectingFrontId: string?,
}

local Zones: { [string]: ZoneData } = {}
local LastTickTime = 0

local function CalculateVolume(Part: BasePart): number
	local Size = Part.Size
	return Size.X * Size.Y * Size.Z
end

local function CalculateZoneCenter(Parts: { BasePart }): Vector3
	if #Parts == 0 then
		return Vector3.zero
	end

	local TotalPosition = Vector3.zero
	local TotalVolume = 0

	for _, Part in ipairs(Parts) do
		local Volume = CalculateVolume(Part)
		TotalPosition = TotalPosition + Part.Position * Volume
		TotalVolume = TotalVolume + Volume
	end

	if TotalVolume > 0 then
		return TotalPosition / TotalVolume
	end

	return Parts[1].Position
end

local function InitializeZone(ZoneInstance: Instance): ZoneData?
	local ZoneName = ZoneInstance.Name
	local Biome: string
	local Parts: { BasePart } = {}
	local Priority = 0
	local TotalVolume = 0

	if ZoneInstance:IsA("Folder") then
		Biome = ZoneInstance:GetAttribute("Biome") or WeatherConfig.DEFAULT_BIOME
		Priority = ZoneInstance:GetAttribute("Priority") or 0

		for _, Child in ipairs(ZoneInstance:GetChildren()) do
			if Child:IsA("BasePart") then
				table.insert(Parts, Child)
				TotalVolume = TotalVolume + CalculateVolume(Child)
			end
		end
	elseif ZoneInstance:IsA("BasePart") then
		Biome = ZoneInstance:GetAttribute("Biome") or WeatherConfig.DEFAULT_BIOME
		Priority = ZoneInstance:GetAttribute("Priority") or 0
		table.insert(Parts, ZoneInstance)
		TotalVolume = CalculateVolume(ZoneInstance)
	else
		return nil
	end

	if #Parts == 0 then
		return nil
	end

	local Center = CalculateZoneCenter(Parts)
	local InitialState = WeatherFronts.GetCalmWeather(Biome)

	return {
		Name = ZoneName,
		Biome = Biome,
		Parts = Parts,
		Priority = Priority,
		Volume = TotalVolume,
		Center = Center,
		CurrentState = InitialState,
		PreviousState = InitialState,
		TimeInState = 0,
		AffectingFrontId = nil,
	}
end

local function SetZoneAttributes(ZoneInstance: Instance, ZoneData: ZoneData, Effects: typeof(WeatherEffects.States.Clear))
	ZoneInstance:SetAttribute("WeatherState", ZoneData.CurrentState)
	ZoneInstance:SetAttribute("CloudCover", Effects.Clouds.Cover)
	ZoneInstance:SetAttribute("CloudDensity", Effects.Clouds.Density)
	ZoneInstance:SetAttribute("CloudColorR", Effects.Clouds.Color.R)
	ZoneInstance:SetAttribute("CloudColorG", Effects.Clouds.Color.G)
	ZoneInstance:SetAttribute("CloudColorB", Effects.Clouds.Color.B)
	ZoneInstance:SetAttribute("AtmosphereDensity", Effects.Atmosphere.Density)
	ZoneInstance:SetAttribute("AtmosphereOffset", Effects.Atmosphere.Offset)
	ZoneInstance:SetAttribute("AtmosphereColorR", Effects.Atmosphere.Color.R)
	ZoneInstance:SetAttribute("AtmosphereColorG", Effects.Atmosphere.Color.G)
	ZoneInstance:SetAttribute("AtmosphereColorB", Effects.Atmosphere.Color.B)
	ZoneInstance:SetAttribute("AtmosphereDecayR", Effects.Atmosphere.Decay.R)
	ZoneInstance:SetAttribute("AtmosphereDecayG", Effects.Atmosphere.Decay.G)
	ZoneInstance:SetAttribute("AtmosphereDecayB", Effects.Atmosphere.Decay.B)
	ZoneInstance:SetAttribute("AtmosphereGlare", Effects.Atmosphere.Glare)
	ZoneInstance:SetAttribute("AtmosphereHaze", Effects.Atmosphere.Haze)
	ZoneInstance:SetAttribute("LightingAmbientR", Effects.Lighting.Ambient.R)
	ZoneInstance:SetAttribute("LightingAmbientG", Effects.Lighting.Ambient.G)
	ZoneInstance:SetAttribute("LightingAmbientB", Effects.Lighting.Ambient.B)
	ZoneInstance:SetAttribute("LightingBrightness", Effects.Lighting.Brightness)
	ZoneInstance:SetAttribute("LightingExposure", Effects.Lighting.ExposureCompensation)
	ZoneInstance:SetAttribute("RainEnabled", Effects.Particles.Rain.Enabled)
	ZoneInstance:SetAttribute("RainRate", Effects.Particles.Rain.Rate or 0)
	ZoneInstance:SetAttribute("SnowEnabled", Effects.Particles.Snow.Enabled)
	ZoneInstance:SetAttribute("SnowRate", Effects.Particles.Snow.Rate or 0)
	ZoneInstance:SetAttribute("RainVolume", Effects.Sounds.Rain.Volume)
	ZoneInstance:SetAttribute("ThunderVolume", Effects.Sounds.Thunder.Volume)
	ZoneInstance:SetAttribute("WindBreezeVolume", Effects.Sounds.WindBreeze.Volume)
	ZoneInstance:SetAttribute("WindGustyVolume", Effects.Sounds.WindGusty.Volume)
	ZoneInstance:SetAttribute("WindSpeedMin", Effects.Wind.SpeedMin)
	ZoneInstance:SetAttribute("WindSpeedMax", Effects.Wind.SpeedMax)
end

local function GetZoneInstance(ZoneName: string): Instance?
	return ZonesFolder:FindFirstChild(ZoneName)
end

local function UpdateZone(ZoneData: ZoneData, DeltaTime: number)
	local ZoneInstance = GetZoneInstance(ZoneData.Name)

	local ForcedState = ZoneInstance and ZoneInstance:GetAttribute("DebugForceState")
	if ForcedState and WeatherEffects.States[ForcedState] then
		if ZoneData.CurrentState ~= ForcedState then
			ZoneData.PreviousState = ZoneData.CurrentState
			ZoneData.CurrentState = ForcedState
			ZoneData.TimeInState = 0
		end

		local Effects = WeatherEffects.States[ForcedState]
		if ZoneInstance then
			SetZoneAttributes(ZoneInstance, ZoneData, Effects)
		end
		return
	end

	ZoneData.TimeInState = ZoneData.TimeInState + DeltaTime

	local AffectingFront = FrontManager.GetFrontAtPosition(ZoneData.Center)
	local NewState: string

	if AffectingFront then
		NewState = WeatherFronts.GetWeatherForFront(AffectingFront.Type, AffectingFront.Intensity, ZoneData.Biome)
		ZoneData.AffectingFrontId = AffectingFront.Id
	else
		ZoneData.AffectingFrontId = nil

		local MinDuration = 45
		local StateConfig = WeatherConfig.States[ZoneData.CurrentState]
		if StateConfig then
			MinDuration = StateConfig.MinimumDuration
		end

		if ZoneData.TimeInState >= MinDuration then
			local TransitionChance = 0.08 + (ZoneData.TimeInState - MinDuration) * 0.002
			TransitionChance = math.clamp(TransitionChance, 0.08, 0.3)

			if math.random() < TransitionChance then
				NewState = WeatherFronts.GetCalmWeather(ZoneData.Biome)
			else
				NewState = ZoneData.CurrentState
			end
		else
			NewState = ZoneData.CurrentState
		end
	end

	if NewState ~= ZoneData.CurrentState then
		ZoneData.PreviousState = ZoneData.CurrentState
		ZoneData.CurrentState = NewState
		ZoneData.TimeInState = 0
	end

	local Effects = WeatherEffects.States[ZoneData.CurrentState]
	if not Effects then
		Effects = WeatherEffects.States.Clear
	end

	if ZoneInstance then
		SetZoneAttributes(ZoneInstance, ZoneData, Effects)
	end
end

local function InitializeAllZones()
	for _, Child in ipairs(ZonesFolder:GetChildren()) do
		local ZoneData = InitializeZone(Child)
		if ZoneData then
			Zones[ZoneData.Name] = ZoneData

			local Effects = WeatherEffects.States[ZoneData.CurrentState]
			if not Effects then
				Effects = WeatherEffects.States.Clear
			end

			SetZoneAttributes(Child, ZoneData, Effects)
		end
	end
end

local function OnZoneAdded(ZoneInstance: Instance)
	local ZoneData = InitializeZone(ZoneInstance)
	if ZoneData then
		Zones[ZoneData.Name] = ZoneData

		local Effects = WeatherEffects.States[ZoneData.CurrentState]
		if not Effects then
			Effects = WeatherEffects.States.Clear
		end

		SetZoneAttributes(ZoneInstance, ZoneData, Effects)
	end
end

local function OnZoneRemoved(ZoneInstance: Instance)
	Zones[ZoneInstance.Name] = nil
end

local function ServerTick()
	local CurrentTime = os.clock()
	local DeltaTime = CurrentTime - LastTickTime
	LastTickTime = CurrentTime

	FrontManager.Update(DeltaTime)

	for _, ZoneData in pairs(Zones) do
		UpdateZone(ZoneData, DeltaTime)
	end
end

FrontManager.Initialize()
InitializeAllZones()

ZonesFolder.ChildAdded:Connect(OnZoneAdded)
ZonesFolder.ChildRemoved:Connect(OnZoneRemoved)

while true do
	ServerTick()
	task.wait(WeatherConfig.TICK_RATE)
end