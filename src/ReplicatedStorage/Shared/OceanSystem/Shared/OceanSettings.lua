--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
local OceanConfig = require(script.Parent.OceanConfig)

export type WaveDefinition = {
	Wavelength: number,
	Direction: Vector2,
	Steepness: number,
	Gravity: number,
	Layer: string?,
}

export type PresetSettings = {
	Intensity: number?,
	Speed: number?,
	WindDirection: number?,
	Choppiness: number?,
}

export type RuntimeSettings = {
	Intensity: number,
	Speed: number,
	WindDirection: number,
	Choppiness: number,
}

local OceanSettings = {}

local TILE_SIZE = 1024

local BASE_WAVES: {WaveDefinition} = {
	{
		Wavelength = 500,
		Direction = Vector2.new(1, 0),
		Steepness = 0.15,
		Gravity = 9.8,
		Layer = "Primary",
	},
	{
		Wavelength = 250,
		Direction = Vector2.new(0.7, 0.7),
		Steepness = 0.12,
		Gravity = 9.8,
		Layer = "Secondary",
	},
	{
		Wavelength = 100,
		Direction = Vector2.new(-0.5, 0.85),
		Steepness = 0.08,
		Gravity = 9.8,
		Layer = "Detail",
	},
	{
		Wavelength = 50,
		Direction = Vector2.new(0.6, -0.8),
		Steepness = 0.05,
		Gravity = 9.8,
		Layer = "Chop",
	},
}

local PRESETS: {[string]: PresetSettings} = {
	Calm = {
		Intensity = 0.15,
		Speed = 0.7,
		Choppiness = 0.1,
	},
	Moderate = {
		Intensity = 0.4,
		Speed = 1.0,
		Choppiness = 0.4,
	},
	Rough = {
		Intensity = 0.7,
		Speed = 1.2,
		Choppiness = 0.7,
	},
	Storm = {
		Intensity = 1.0,
		Speed = 1.5,
		Choppiness = 1.0,
	},
}

local DEFAULT_SETTINGS: RuntimeSettings = {
	Intensity = 0.5,
	Speed = 1.0,
	WindDirection = 0,
	Choppiness = 0.5,
}

local SettingsTrove: typeof(Trove.new())? = nil
local ConfigurationInstance: Configuration? = nil
local CurrentSettings: RuntimeSettings = table.clone(DEFAULT_SETTINGS)
local ComputedWaves: {WaveDefinition} = {}
local ComputedTimeModifier: number = 5

local OnSettingsChanged = Instance.new("BindableEvent")
OceanSettings.Changed = OnSettingsChanged.Event

local function ComputeWaves(): ()
	local Intensity = CurrentSettings.Intensity
	local Speed = CurrentSettings.Speed
	local WindRad = math.rad(CurrentSettings.WindDirection)
	local Choppiness = CurrentSettings.Choppiness

	local ScaledWaves: {WaveDefinition} = {}

	for _, BaseWave in BASE_WAVES do
		local SteepnessMultiplier = Intensity
		if BaseWave.Layer == "Chop" or BaseWave.Layer == "Detail" then
			SteepnessMultiplier = Intensity * Choppiness
		end

		local ComputedSteepness = BaseWave.Steepness * SteepnessMultiplier
		if ComputedSteepness > 0.001 then
			local OriginalDirection = BaseWave.Direction
			local Angle = math.atan2(OriginalDirection.Y, OriginalDirection.X) + WindRad

			table.insert(ScaledWaves, {
				Wavelength = BaseWave.Wavelength,
				Direction = Vector2.new(math.cos(Angle), math.sin(Angle)),
				Steepness = ComputedSteepness,
				Gravity = BaseWave.Gravity,
				Layer = BaseWave.Layer,
			})
		end
	end

	ComputedWaves = ScaledWaves
	ComputedTimeModifier = 4 / Speed

	OnSettingsChanged:Fire(CurrentSettings)
end

local function ReadAttributes(): ()
	if not ConfigurationInstance then
		return
	end

	local Intensity = ConfigurationInstance:GetAttribute("Intensity") :: number?
	local Speed = ConfigurationInstance:GetAttribute("Speed") :: number?
	local WindDirection = ConfigurationInstance:GetAttribute("WindDirection") :: number?
	local Choppiness = ConfigurationInstance:GetAttribute("Choppiness") :: number?

	CurrentSettings.Intensity = math.clamp(Intensity or 0.5, 0, 1)
	CurrentSettings.Speed = math.clamp(Speed or 1.0, 0.1, 3)
	CurrentSettings.WindDirection = (WindDirection or 0) % 360
	CurrentSettings.Choppiness = math.clamp(Choppiness or 0.5, 0, 1)
end

local function SetupDefaultAttributes(Config: Configuration): ()
	if not Config:GetAttribute("Intensity") then
		Config:SetAttribute("Intensity", DEFAULT_SETTINGS.Intensity)
	end
	if not Config:GetAttribute("Speed") then
		Config:SetAttribute("Speed", DEFAULT_SETTINGS.Speed)
	end
	if not Config:GetAttribute("WindDirection") then
		Config:SetAttribute("WindDirection", 45)
	end
	if not Config:GetAttribute("Choppiness") then
		Config:SetAttribute("Choppiness", DEFAULT_SETTINGS.Choppiness)
	end
end

function OceanSettings.Initialize(Config: Configuration): ()
	if SettingsTrove then
		SettingsTrove:Destroy()
	end

	local NewTrove = Trove.new()
	ConfigurationInstance = Config

	SetupDefaultAttributes(Config)
	ReadAttributes()
	ComputeWaves()

	NewTrove:Connect(Config.AttributeChanged, function(AttributeName: string)
		if AttributeName == "Intensity"
			or AttributeName == "Speed"
			or AttributeName == "WindDirection"
			or AttributeName == "Choppiness"
		then
			ReadAttributes()
			ComputeWaves()
		end
	end)

	SettingsTrove = NewTrove
end

function OceanSettings.GetWaves(): {WaveDefinition}
	return ComputedWaves
end

function OceanSettings.GetTimeModifier(): number
	return ComputedTimeModifier
end

function OceanSettings.GetBaseWaterHeight(): number
	return OceanConfig.BASE_WATER_HEIGHT
end

function OceanSettings.GetTileSize(): number
	return TILE_SIZE
end

function OceanSettings.Get(): RuntimeSettings
	return {
		Intensity = CurrentSettings.Intensity,
		Speed = CurrentSettings.Speed,
		WindDirection = CurrentSettings.WindDirection,
		Choppiness = CurrentSettings.Choppiness,
	}
end

function OceanSettings.Set(Settings: {
	Intensity: number?,
	Speed: number?,
	WindDirection: number?,
	Choppiness: number?,
}): ()
	if not ConfigurationInstance then
		return
	end

	if Settings.Intensity then
		ConfigurationInstance:SetAttribute("Intensity", Settings.Intensity)
	end
	if Settings.Speed then
		ConfigurationInstance:SetAttribute("Speed", Settings.Speed)
	end
	if Settings.WindDirection then
		ConfigurationInstance:SetAttribute("WindDirection", Settings.WindDirection)
	end
	if Settings.Choppiness then
		ConfigurationInstance:SetAttribute("Choppiness", Settings.Choppiness)
	end
end

function OceanSettings.SetPreset(PresetName: string): ()
	local Preset = PRESETS[PresetName]
	if not Preset then
		warn("[OceanSettings] Unknown preset:", PresetName)
		return
	end

	if ConfigurationInstance then
		ConfigurationInstance:SetAttribute("Intensity", Preset.Intensity)
		ConfigurationInstance:SetAttribute("Speed", Preset.Speed)
		ConfigurationInstance:SetAttribute("Choppiness", Preset.Choppiness)
	end
end

function OceanSettings.TweenTo(
	TargetSettings: {
		Intensity: number?,
		Speed: number?,
		WindDirection: number?,
		Choppiness: number?,
	},
	Duration: number
): RBXScriptConnection?
	local ActiveConfig = ConfigurationInstance
	local ActiveTrove = SettingsTrove
	if not ActiveConfig or not ActiveTrove then
		return nil
	end

	if Duration <= 0 then
		OceanSettings.Set(TargetSettings)
		return nil
	end

	local RunService = game:GetService("RunService")
	local StartSettings = OceanSettings.Get()
	local StartTime = os.clock()

	local TweenConnection: RBXScriptConnection? = nil

	TweenConnection = RunService.Heartbeat:Connect(function()
		local Elapsed = os.clock() - StartTime
		local Alpha = math.min(Elapsed / Duration, 1)
		Alpha = Alpha * Alpha * (3 - 2 * Alpha)

		if TargetSettings.Intensity then
			local Value = StartSettings.Intensity + (TargetSettings.Intensity - StartSettings.Intensity) * Alpha
			ActiveConfig:SetAttribute("Intensity", Value)
		end

		if TargetSettings.Speed then
			local Value = StartSettings.Speed + (TargetSettings.Speed - StartSettings.Speed) * Alpha
			ActiveConfig:SetAttribute("Speed", Value)
		end

		if TargetSettings.Choppiness then
			local Value = StartSettings.Choppiness + (TargetSettings.Choppiness - StartSettings.Choppiness) * Alpha
			ActiveConfig:SetAttribute("Choppiness", Value)
		end

		if TargetSettings.WindDirection then
			local Start = StartSettings.WindDirection
			local Target = TargetSettings.WindDirection
			local Diff = (Target - Start + 180) % 360 - 180
			local Value = Start + Diff * Alpha
			ActiveConfig:SetAttribute("WindDirection", Value)
		end

		if Alpha >= 1 then
			local ConnectionToStop = TweenConnection
			if ConnectionToStop then
				ConnectionToStop:Disconnect()
				ActiveTrove:Remove(ConnectionToStop)
			end
		end
	end)

	ActiveTrove:Add(TweenConnection :: RBXScriptConnection)
	return TweenConnection
end

function OceanSettings.TweenToPreset(PresetName: string, Duration: number): RBXScriptConnection?
	local Preset = PRESETS[PresetName]
	if not Preset then
		warn("[OceanSettings] Unknown preset:", PresetName)
		return nil
	end

	local TargetSettings: PresetSettings = {
		Intensity = Preset.Intensity,
		Speed = Preset.Speed,
		Choppiness = Preset.Choppiness,
		WindDirection = Preset.WindDirection,
	}

	return OceanSettings.TweenTo(TargetSettings, Duration)
end

function OceanSettings.GetPresets(): {[string]: PresetSettings}
	return PRESETS
end

function OceanSettings.Destroy(): ()
	if SettingsTrove then
		SettingsTrove:Destroy()
		SettingsTrove = nil
	end
	ConfigurationInstance = nil
	ComputedWaves = {}
end

return OceanSettings