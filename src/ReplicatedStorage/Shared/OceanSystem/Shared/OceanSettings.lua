--[[
    OceanSettings
    Dynamic ocean intensity control via Attributes.

    Attributes on workspace.Ocean.Plane:
        - Intensity (number, 0-1): Overall wave intensity
        - Speed (number, 0.5-2): Wave speed multiplier
        - WindDirection (number, 0-360): Primary wave direction in degrees
        - Choppiness (number, 0-1): Noise detail intensity

    Presets: "Calm", "Moderate", "Rough", "Storm"
]]

local RunService = game:GetService("RunService")

local OceanSettings = {}

--[[
    5 Gerstner Waves + Noise Strategy

    Waves handle the organized rolling motion.
    Noise (controlled by Choppiness) handles chaotic surface detail.

    Directions spread across 360 degrees to avoid corduroy patterns.
    Prime-ish wavelengths prevent harmonic repetition.
]]
OceanSettings.BaseWaves = {
	{
		Wavelength = 173,
		Steepness = 0.15,
		Gravity = 9.8,
		Layer = "Primary",
		AngleOffset = 0,
	},
	{
		Wavelength = 97,
		Steepness = 0.12,
		Gravity = 9.8,
		Layer = "Primary",
		AngleOffset = 72,
	},
	{
		Wavelength = 53,
		Steepness = 0.09,
		Gravity = 9.8,
		Layer = "Secondary",
		AngleOffset = 155,
	},
	{
		Wavelength = 31,
		Steepness = 0.07,
		Gravity = 9.8,
		Layer = "Secondary",
		AngleOffset = 230,
	},
	{
		Wavelength = 17,
		Steepness = 0.05,
		Gravity = 9.8,
		Layer = "Secondary",
		AngleOffset = 310,
	},
}

OceanSettings.BaseNoiseSettings = {
	Enabled = true,
	Amplitude = 0.5,
	Scale = 0.025,
	Speed = 0.6,
	Octaves = 3,
	Lacunarity = 2.0,
	Persistence = 0.5,
	HorizontalDisplacement = true,
}

OceanSettings.Presets = {
	Calm = {
		Intensity = 0.2,
		Speed = 0.7,
		Choppiness = 0.1,
	},
	Moderate = {
		Intensity = 0.5,
		Speed = 1.0,
		Choppiness = 0.5,
	},
	Rough = {
		Intensity = 0.75,
		Speed = 1.2,
		Choppiness = 0.75,
	},
	Storm = {
		Intensity = 1.0,
		Speed = 1.4,
		Choppiness = 1.0,
	},
}

local CurrentSettings = {
	Intensity = 0.5,
	Speed = 1.0,
	WindDirection = 0,
	Choppiness = 0.5,
}

local OceanMesh = nil
local WaveConfig = nil
local OnSettingsChanged = Instance.new("BindableEvent")

OceanSettings.Changed = OnSettingsChanged.Event

function OceanSettings:Initialize(Mesh, Config)
	OceanMesh = Mesh
	WaveConfig = Config

	if not Mesh:GetAttribute("Intensity") then
		Mesh:SetAttribute("Intensity", 0.5)
	end
	if not Mesh:GetAttribute("Speed") then
		Mesh:SetAttribute("Speed", 1.0)
	end
	if not Mesh:GetAttribute("WindDirection") then
		Mesh:SetAttribute("WindDirection", 0)
	end
	if not Mesh:GetAttribute("Choppiness") then
		Mesh:SetAttribute("Choppiness", 0.5)
	end

	self:_ReadAttributes()
	self:_ApplySettings()

	Mesh.AttributeChanged:Connect(function(AttributeName)
		if AttributeName == "Intensity" or
			AttributeName == "Speed" or
			AttributeName == "WindDirection" or
			AttributeName == "Choppiness" then
			self:_ReadAttributes()
			self:_ApplySettings()
		end
	end)
end

function OceanSettings:_ReadAttributes()
	if not OceanMesh then
		return
	end

	CurrentSettings.Intensity = math.clamp(OceanMesh:GetAttribute("Intensity") or 0.5, 0, 1)
	CurrentSettings.Speed = math.clamp(OceanMesh:GetAttribute("Speed") or 1.0, 0.1, 3)
	CurrentSettings.WindDirection = (OceanMesh:GetAttribute("WindDirection") or 0) % 360
	CurrentSettings.Choppiness = math.clamp(OceanMesh:GetAttribute("Choppiness") or 0.5, 0, 1)
end

function OceanSettings:_ApplySettings()
	if not WaveConfig then
		return
	end

	local Intensity = CurrentSettings.Intensity
	local Speed = CurrentSettings.Speed
	local WindRad = math.rad(CurrentSettings.WindDirection)
	local Choppiness = CurrentSettings.Choppiness

	local ScaledWaves = {}

	for _, BaseWave in ipairs(self.BaseWaves) do
		local Wave = {
			Wavelength = BaseWave.Wavelength,
			Gravity = BaseWave.Gravity,
		}

		Wave.Steepness = BaseWave.Steepness * Intensity

		local AngleOffset = math.rad(BaseWave.AngleOffset or 0)
		local FinalAngle = WindRad + AngleOffset
		Wave.Direction = Vector2.new(math.cos(FinalAngle), math.sin(FinalAngle))

		if Wave.Steepness > 0.001 then
			table.insert(ScaledWaves, Wave)
		end
	end

	WaveConfig.Waves = ScaledWaves
	WaveConfig.TimeModifier = 4 / Speed

	local BaseNoise = self.BaseNoiseSettings
	WaveConfig.NoiseSettings = {
		Enabled = BaseNoise.Enabled and Choppiness > 0.01,
		Amplitude = BaseNoise.Amplitude * Choppiness * Intensity,
		Scale = BaseNoise.Scale,
		Speed = BaseNoise.Speed * Speed,
		Octaves = BaseNoise.Octaves,
		Lacunarity = BaseNoise.Lacunarity,
		Persistence = BaseNoise.Persistence,
		HorizontalDisplacement = BaseNoise.HorizontalDisplacement,
	}

	OnSettingsChanged:Fire(CurrentSettings)
end

function OceanSettings:SetPreset(PresetName)
	local Preset = self.Presets[PresetName]
	if not Preset then
		warn("[OceanSettings] Unknown preset:", PresetName)
		return
	end

	if OceanMesh then
		OceanMesh:SetAttribute("Intensity", Preset.Intensity)
		OceanMesh:SetAttribute("Speed", Preset.Speed)
		OceanMesh:SetAttribute("Choppiness", Preset.Choppiness)
	end
end

function OceanSettings:Set(Settings)
	if not OceanMesh then
		return
	end

	if Settings.Intensity then
		OceanMesh:SetAttribute("Intensity", Settings.Intensity)
	end
	if Settings.Speed then
		OceanMesh:SetAttribute("Speed", Settings.Speed)
	end
	if Settings.WindDirection then
		OceanMesh:SetAttribute("WindDirection", Settings.WindDirection)
	end
	if Settings.Choppiness then
		OceanMesh:SetAttribute("Choppiness", Settings.Choppiness)
	end
end

function OceanSettings:Get()
	return {
		Intensity = CurrentSettings.Intensity,
		Speed = CurrentSettings.Speed,
		WindDirection = CurrentSettings.WindDirection,
		Choppiness = CurrentSettings.Choppiness,
	}
end

function OceanSettings:TweenTo(TargetSettings, Duration)
	if not OceanMesh then
		return
	end

	local StartSettings = self:Get()
	local StartTime = tick()

	local Connection
	Connection = RunService.Heartbeat:Connect(function()
		local Elapsed = tick() - StartTime
		local Alpha = math.min(Elapsed / Duration, 1)

		Alpha = Alpha * Alpha * (3 - 2 * Alpha)

		if TargetSettings.Intensity then
			local Value = StartSettings.Intensity + (TargetSettings.Intensity - StartSettings.Intensity) * Alpha
			OceanMesh:SetAttribute("Intensity", Value)
		end
		if TargetSettings.Speed then
			local Value = StartSettings.Speed + (TargetSettings.Speed - StartSettings.Speed) * Alpha
			OceanMesh:SetAttribute("Speed", Value)
		end
		if TargetSettings.Choppiness then
			local Value = StartSettings.Choppiness + (TargetSettings.Choppiness - StartSettings.Choppiness) * Alpha
			OceanMesh:SetAttribute("Choppiness", Value)
		end
		if TargetSettings.WindDirection then
			local Start = StartSettings.WindDirection
			local Target = TargetSettings.WindDirection
			local Diff = (Target - Start + 180) % 360 - 180
			local Value = Start + Diff * Alpha
			OceanMesh:SetAttribute("WindDirection", Value)
		end

		if Alpha >= 1 then
			Connection:Disconnect()
		end
	end)

	return Connection
end

function OceanSettings:TweenToPreset(PresetName, Duration)
	local Preset = self.Presets[PresetName]
	if not Preset then
		warn("[OceanSettings] Unknown preset:", PresetName)
		return
	end

	return self:TweenTo(Preset, Duration)
end

return OceanSettings