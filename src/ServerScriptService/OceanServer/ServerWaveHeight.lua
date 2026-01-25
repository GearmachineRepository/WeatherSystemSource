--[[
    ServerWaveHeight
    Server-side wave height calculations (doesn't need the mesh).
    Place in: ServerScriptService/OceanServer (as a Script)

    The server doesn't render the mesh, so it uses the raw Gerstner formula.
    This is slightly less accurate than the client's triangle interpolation,
    but the difference is negligible for gameplay purposes.

    Use this for:
    - Server-authoritative boat physics
    - Damage from underwater collisions
    - AI ship navigation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for modules
local OceanSystem = ReplicatedStorage:WaitForChild("OceanSystem")
local WaveConfig = require(OceanSystem.Shared.WaveConfig)
local GerstnerWave = require(OceanSystem.Shared.GerstnerWave)

local ServerWaveHeight = {}

--[[
    Get wave height at a position (server-side, uses formula directly).

    Parameters:
        X: number, Z: number

    Returns:
        number - The Y height
]]
function ServerWaveHeight.GetHeight(X, Z)
	return GerstnerWave.GetIdealHeight(X, Z)
end

--[[
    Get wave height at a Vector3 position.

    Parameters:
        Position: Vector3

    Returns:
        number
]]
function ServerWaveHeight.GetHeightAtPosition(Position)
	return GerstnerWave.GetIdealHeight(Position.X, Position.Z)
end

--[[
    Check if a position is underwater.

    Parameters:
        Position: Vector3

    Returns:
        boolean
]]
function ServerWaveHeight.IsUnderwater(Position)
	local Height = ServerWaveHeight.GetHeight(Position.X, Position.Z)
	return Position.Y < Height
end

--[[
    Get depth below surface.

    Parameters:
        Position: Vector3

    Returns:
        number (positive if underwater)
]]
function ServerWaveHeight.GetDepth(Position)
	local Height = ServerWaveHeight.GetHeight(Position.X, Position.Z)
	return Height - Position.Y
end

return ServerWaveHeight