--[[
    GerstnerWave
    Mathematical functions for Gerstner wave calculations.

    This module provides the core wave math used by both:
    - OceanController (to displace bones visually)
    - WaveHeightSampler (to calculate heights for boats)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaveConfig = require(script.Parent.WaveConfig)

local GerstnerWave = {}

--[[
    Get synchronized time for wave calculations.
    Uses the same formula as the reference wave module.
]]
function GerstnerWave.GetSyncedTime()
	return DateTime.now().UnixTimestampMillis / 1000 / WaveConfig.TimeModifier
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
function GerstnerWave.CalculateSingleWave(Position, Wavelength, Direction, Steepness, Gravity, Time)
	local K = (2 * math.pi) / Wavelength
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
    Calculate total displacement from all wave components.

    Parameters:
        Position: Vector3 - The world position to sample
        Time: number (optional) - Override synced time

    Returns:
        Vector3 - Total displacement from all waves combined
]]
function GerstnerWave.CalculateTotalDisplacement(Position, Time)
	Time = Time or GerstnerWave.GetSyncedTime()

	local TotalDisplacement = Vector3.new(0, 0, 0)

	for _, Wave in ipairs(WaveConfig.Waves) do
		local Displacement = GerstnerWave.CalculateSingleWave(
			Position,
			Wave.Wavelength,
			Wave.Direction,
			Wave.Steepness,
			Wave.Gravity,
			Time
		)
		TotalDisplacement = TotalDisplacement + Displacement
	end

	return TotalDisplacement
end

--[[
    Get the ideal wave height at a position (ignoring mesh triangles).
    Use this for quick estimates or when outside the bone grid.

    Parameters:
        X: number - World X position
        Z: number - World Z position
        Time: number (optional) - Override synced time

    Returns:
        number - The Y height of the wave surface
]]
function GerstnerWave.GetIdealHeight(X, Z, Time)
	local Position = Vector3.new(X, 0, Z)
	local Displacement = GerstnerWave.CalculateTotalDisplacement(Position, Time)
	return WaveConfig.BaseWaterHeight + Displacement.Y
end

--[[
    Get the displaced world position of a point.
    Used when updating bone positions.

    Parameters:
        OriginalPosition: Vector3 - The rest position of the bone
        Time: number (optional) - Override synced time

    Returns:
        Vector3 - The new world position after wave displacement
]]
function GerstnerWave.GetDisplacedPosition(OriginalPosition, Time)
	local Displacement = GerstnerWave.CalculateTotalDisplacement(OriginalPosition, Time)
	return OriginalPosition + Displacement
end

return GerstnerWave