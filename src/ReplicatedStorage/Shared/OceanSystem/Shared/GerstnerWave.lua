--!strict

local OceanConfig = require(script.Parent.OceanConfig)
local OceanSettings = require(script.Parent.OceanSettings)

local GerstnerWave = {}

local TAU = math.pi * 2

local function SampleNoise(PositionX: number, PositionZ: number, Time: number, Scale: number, Speed: number): number
	local NoiseX = PositionX * Scale + Time * Speed
	local NoiseZ = PositionZ * Scale + Time * Speed * 0.7
	return math.noise(NoiseX, NoiseZ, Time * 0.1)
end

function GerstnerWave.GetSyncedTime(): number
	return workspace:GetServerTimeNow() / OceanSettings.GetTimeModifier()
end

function GerstnerWave.CalculateNoiseDisplacement(PositionX: number, PositionZ: number, Time: number): Vector3
	local Settings = OceanConfig.Noise
	if not Settings.Enabled then
		return Vector3.zero
	end

	local TotalY = 0
	local TotalX = 0
	local TotalZ = 0

	local Amplitude = Settings.Amplitude
	local Scale = Settings.Scale
	local Speed = Settings.Speed
	local Lacunarity = Settings.Lacunarity
	local Persistence = Settings.Persistence

	for _Octave = 1, Settings.Octaves do
		local NoiseValue = SampleNoise(PositionX, PositionZ, Time, Scale, Speed)
		TotalY = TotalY + NoiseValue * Amplitude

		if Settings.HorizontalDisplacement then
			local NoiseX = SampleNoise(PositionX + 100, PositionZ, Time, Scale, Speed * 1.1)
			local NoiseZ = SampleNoise(PositionX, PositionZ + 100, Time, Scale, Speed * 0.9)
			TotalX = TotalX + NoiseX * Amplitude * 0.3
			TotalZ = TotalZ + NoiseZ * Amplitude * 0.3
		end

		Amplitude = Amplitude * Persistence
		Scale = Scale * Lacunarity
		Speed = Speed * 1.2
	end

	return Vector3.new(TotalX, TotalY, TotalZ)
end

function GerstnerWave.CalculateSingleWave(
	Position: Vector3,
	Wavelength: number,
	Direction: Vector2,
	Steepness: number,
	Gravity: number,
	Time: number
): Vector3
	local WaveNumber = TAU / Wavelength
	local Amplitude = Steepness / WaveNumber
	local NormalizedDirection = Direction.Unit
	local WaveSpeed = math.sqrt(Gravity / WaveNumber)
	local DotProduct = NormalizedDirection.X * Position.X + NormalizedDirection.Y * Position.Z
	local Phase = WaveNumber * DotProduct - WaveSpeed * Time
	local CosPhase = math.cos(Phase)
	local SinPhase = math.sin(Phase)

	local DisplacementX = NormalizedDirection.X * Amplitude * CosPhase
	local DisplacementY = Amplitude * SinPhase
	local DisplacementZ = NormalizedDirection.Y * Amplitude * CosPhase

	return Vector3.new(DisplacementX, DisplacementY, DisplacementZ)
end

function GerstnerWave.CalculateTotalDisplacement(Position: Vector3, Time: number?): Vector3
	local ResolvedTime = Time or GerstnerWave.GetSyncedTime()
	local TotalDisplacement = Vector3.zero

	for _, Wave in OceanSettings.GetWaves() do
		local Displacement = GerstnerWave.CalculateSingleWave(
			Position,
			Wave.Wavelength,
			Wave.Direction,
			Wave.Steepness,
			Wave.Gravity,
			ResolvedTime
		)
		TotalDisplacement = TotalDisplacement + Displacement
	end

	local NoiseDisplacement = GerstnerWave.CalculateNoiseDisplacement(
		Position.X,
		Position.Z,
		ResolvedTime
	)
	TotalDisplacement = TotalDisplacement + NoiseDisplacement

	return TotalDisplacement
end

function GerstnerWave.GetIdealHeight(PositionX: number, PositionZ: number, Time: number?): number
	local Position = Vector3.new(PositionX, 0, PositionZ)
	local Displacement = GerstnerWave.CalculateTotalDisplacement(Position, Time)
	return OceanConfig.BASE_WATER_HEIGHT + Displacement.Y
end

function GerstnerWave.GetDisplacedPosition(OriginalPosition: Vector3, Time: number?): Vector3
	local Displacement = GerstnerWave.CalculateTotalDisplacement(OriginalPosition, Time)
	return OriginalPosition + Displacement
end

return GerstnerWave