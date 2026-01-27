--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local GerstnerWave = require(OceanSystem.Shared.GerstnerWave)

local ServerWaveHeight = {}

function ServerWaveHeight.GetHeight(PositionX: number, PositionZ: number): number
	return GerstnerWave.GetIdealHeight(PositionX, PositionZ)
end

function ServerWaveHeight.GetHeightAtPosition(Position: Vector3): number
	return GerstnerWave.GetIdealHeight(Position.X, Position.Z)
end

function ServerWaveHeight.IsUnderwater(Position: Vector3): boolean
	local Height = ServerWaveHeight.GetHeight(Position.X, Position.Z)
	return Position.Y < Height
end

function ServerWaveHeight.GetDepth(Position: Vector3): number
	local Height = ServerWaveHeight.GetHeight(Position.X, Position.Z)
	return Height - Position.Y
end

return ServerWaveHeight