--!strict
--[[
    OceanController
    Client-side controller that updates ocean mesh bones.

    Uses GerstnerWave module for wave calculations to ensure
    server and client use identical math.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WaveConfig = require(script.Parent.Parent.Shared.WaveConfig)
local GerstnerWave = require(script.Parent.Parent.Shared.GerstnerWave)
local WaveHeightSampler = require(script.Parent.Parent.Shared.WaveHeightSampler)

local OceanController = {}
OceanController.__index = OceanController

export type OceanController = {
	OceanMesh: MeshPart,
	Bones: {Bone},
	Running: boolean,
	Connection: RBXScriptConnection?,
	HeightSampler: typeof(WaveHeightSampler.new(nil :: any)),
}

--[[
    Create a new OceanController.

    Parameters:
        OceanMesh: MeshPart - The skinned mesh with bones (workspace.Ocean.Plane)

    Returns:
        OceanController instance
]]
function OceanController.new(OceanMesh: MeshPart)
	local self = setmetatable({}, OceanController)

	self.OceanMesh = OceanMesh
	self.Bones = {}
	self.Running = false
	self.Connection = nil

	for _, Child in pairs(OceanMesh:GetDescendants()) do
		if Child:IsA("Bone") then
			table.insert(self.Bones, Child)
		end
	end

	self.HeightSampler = WaveHeightSampler.new(OceanMesh)

	return self
end

--[[
    Update all bones with wave displacement.
]]
function OceanController:_Update(): ()
	local Time = GerstnerWave.GetSyncedTime()

	local LocalPlayer = Players.LocalPlayer
	local Character = LocalPlayer and LocalPlayer.Character
	local MaxDistance = WaveConfig.MaxUpdateDistance
	local MaxDistanceSquared = MaxDistance * MaxDistance

	local CharacterPosition: Vector3? = nil
	if Character and Character.PrimaryPart then
		CharacterPosition = Character.PrimaryPart.Position
	end

	for _, Bone in ipairs(self.Bones) do
		local WorldPosition = Bone.WorldPosition :: Vector3

		local ShouldUpdate = true
		if CharacterPosition then
			local Delta = WorldPosition - CharacterPosition
			local DistanceSquared = Delta.X * Delta.X + Delta.Z * Delta.Z
			ShouldUpdate = DistanceSquared < MaxDistanceSquared
		end

		if ShouldUpdate then
			local TotalDisplacement = Vector3.zero

			for _, Wave in ipairs(WaveConfig.Waves) do
				local Displacement = GerstnerWave.CalculateSingleWave(
					WorldPosition,
					Wave.Wavelength,
					Wave.Direction,
					Wave.Steepness,
					Wave.Gravity,
					Time
				)
				TotalDisplacement = TotalDisplacement + Displacement
			end

			Bone.Transform = CFrame.new(TotalDisplacement)
		else
			Bone.Transform = CFrame.new()
		end
	end
end

--[[
    Start the wave animation loop.
]]
function OceanController:Start(): ()
	if self.Running then
		warn("[OceanController] Already running")
		return
	end

	self.Running = true

	self.Connection = RunService.RenderStepped:Connect(function()
		if not game:IsLoaded() then
			return
		end
		self:_Update()
	end)
end

--[[
    Stop the wave animation loop.
]]
function OceanController:Stop(): ()
	if not self.Running then
		return
	end

	self.Running = false
	local Connection = self.Connection :: RBXScriptConnection?

	if Connection then
		Connection:Disconnect()
		self.Connection = nil
	end

	for _, Bone in ipairs(self.Bones) do
		Bone.Transform = CFrame.new()
	end
end

--[[
    Get the WaveHeightSampler instance.
]]
function OceanController:GetHeightSampler()
	return self.HeightSampler
end

--[[
    Get wave height at a position (convenience function).
]]
function OceanController:GetWaveHeight(X: number, Z: number): number
	return self.HeightSampler:GetHeight(X, Z)
end

-- Add after GetWaveHeight:
--[[
    Clean up the controller and all connections.
]]
function OceanController:Destroy(): ()
	self:Stop()
	self.Bones = {}
	self.OceanMesh = nil
	self.HeightSampler = nil
end

return OceanController