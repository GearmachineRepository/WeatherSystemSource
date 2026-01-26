--!strict
--[[
    GerstnerWave
    Mathematical functions for Gerstner wave calculations with noise detail layer.

    This module provides the core wave math used by both:
    - OceanController (to displace bones visually on client)
    - BoatPhysicsServer (to calculate heights for boats on server)

    CRITICAL: Both server and client MUST use workspace:GetServerTimeNow()
    for synchronized wave calculations.
]]

local WaveConfig = require(script.Parent.WaveConfig)

local GerstnerWave = {}

local TAU = math.pi * 2

--[[
    Get synchronized time for wave calculations.
    Uses workspace:GetServerTimeNow() which is synchronized across server and all clients.
]]
function GerstnerWave.GetSyncedTime(): number
	return workspace:GetServerTimeNow() / WaveConfig.TimeModifier
end

--[[
    Deterministic noise function for synchronized displacement.
    Uses math.noise which is consistent across server/client for same inputs.

    Parameters:
        X: number - World X position
        Z: number - World Z position
        Time: number - Synced time

    Returns:
        number - Noise value between -1 and 1
]]
local function SampleNoise(X: number, Z: number, Time: number, Scale: number, Speed: number): number
	local NoiseX = X * Scale + Time * Speed
	local NoiseZ = Z * Scale + Time * Speed * 0.7
	return math.noise(NoiseX, NoiseZ, Time * 0.1)
end

--[[
    Calculate layered noise displacement for surface detail.
    Adds the choppy, chaotic look that breaks up Gerstner patterns.

    Parameters:
        X: number - World X position
        Z: number - World Z position
        Time: number - Synced time

    Returns:
        Vector3 - Small-scale displacement
]]
function GerstnerWave.CalculateNoiseDisplacement(X: number, Z: number, Time: number): Vector3
	local Settings = WaveConfig.NoiseSettings
	if not Settings or not Settings.Enabled then
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
		local NoiseValue = SampleNoise(X, Z, Time, Scale, Speed)
		TotalY = TotalY + NoiseValue * Amplitude

		if Settings.HorizontalDisplacement then
			local NoiseX = SampleNoise(X + 100, Z, Time, Scale, Speed * 1.1)
			local NoiseZ = SampleNoise(X, Z + 100, Time, Scale, Speed * 0.9)
			TotalX = TotalX + NoiseX * Amplitude * 0.3
			TotalZ = TotalZ + NoiseZ * Amplitude * 0.3
		end

		Amplitude = Amplitude * Persistence
		Scale = Scale * Lacunarity
		Speed = Speed * 1.2
	end

	return Vector3.new(TotalX, TotalY, TotalZ)
end

--[[
    Calculate displacement for a single Gerstner wave component.

    Parameters:
        Position: Vector3 - The world position to sample
        Wavelength: number - Distance between wave peaks
        Direction: Vector2 - Normalized direction the wave travels
        Steepness: number - How "pointy" the waves are (0 to 1)
        Gravity: number - Affects wave speed
        Time: number - Current synced time

    Returns:
        Vector3 - The displacement (X, Y, Z offset)
]]
function GerstnerWave.CalculateSingleWave(
	Position: Vector3,
	Wavelength: number,
	Direction: Vector2,
	Steepness: number,
	Gravity: number,
	Time: number
): Vector3
	local K = TAU / Wavelength
	local A = Steepness / K
	local D = Direction.Unit
	local C = math.sqrt(Gravity / K)
	local DotProduct = D.X * Position.X + D.Y * Position.Z
	local F = K * DotProduct - C * Time
	local CosF = math.cos(F)
	local SinF = math.sin(F)

	local DisplacementX = D.X * A * CosF
	local DisplacementY = A * SinF
	local DisplacementZ = D.Y * A * CosF

	return Vector3.new(DisplacementX, DisplacementY, DisplacementZ)
end

--[[
    Calculate total displacement from all wave components plus noise.

    Parameters:
        Position: Vector3 - The world position to sample
        Time: number? - Override synced time (optional)

    Returns:
        Vector3 - Total displacement from all waves combined
]]
function GerstnerWave.CalculateTotalDisplacement(Position: Vector3, Time: number?): Vector3
	local ResolvedTime = Time or GerstnerWave.GetSyncedTime()

	local TotalDisplacement = Vector3.zero

	for _, Wave in ipairs(WaveConfig.Waves) do
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

--[[
    Get the ideal wave height at a position.
    Use this for quick estimates or when outside the bone grid.

    Parameters:
        X: number - World X position
        Z: number - World Z position
        Time: number? - Override synced time (optional)

    Returns:
        number - The Y height of the wave surface
]]
function GerstnerWave.GetIdealHeight(X: number, Z: number, Time: number?): number
	local Position = Vector3.new(X, 0, Z)
	local Displacement = GerstnerWave.CalculateTotalDisplacement(Position, Time)
	return WaveConfig.BaseWaterHeight + Displacement.Y
end

--[[
    Get the displaced world position of a point.
    Used when updating bone positions.

    Parameters:
        OriginalPosition: Vector3 - The rest position of the bone
        Time: number? - Override synced time (optional)

    Returns:
        Vector3 - The new world position after wave displacement
]]
function GerstnerWave.GetDisplacedPosition(OriginalPosition: Vector3, Time: number?): Vector3
	local Displacement = GerstnerWave.CalculateTotalDisplacement(OriginalPosition, Time)
	return OriginalPosition + Displacement
end

return GerstnerWave