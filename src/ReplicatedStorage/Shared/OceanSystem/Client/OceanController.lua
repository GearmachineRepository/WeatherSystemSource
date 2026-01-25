--[[
    OceanController
    Client-side controller that updates ocean mesh bones.

    Based on the wave module pattern from:
    https://devforum.roblox.com/t/realistic-oceans-using-mesh-deformation/1159345
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WaveConfig = require(script.Parent.Parent.Shared.WaveConfig)
local WaveHeightSampler = require(script.Parent.Parent.Shared.WaveHeightSampler)

local OceanController = {}
OceanController.__index = OceanController

-- Gerstner wave calculation (matches the reference script exactly)
local function Gerstner(Position, Wavelength, Direction, Steepness, Gravity, Time)
	local K = (2 * math.pi) / Wavelength
	local A = Steepness / K
	local D = Direction.Unit
	local C = math.sqrt(Gravity / K)
	local F = K * D:Dot(Vector2.new(Position.X, Position.Z)) - C * Time
	local CosF = math.cos(F)

	local DX = D.X * A * CosF
	local DY = A * math.sin(F)
	local DZ = D.Y * A * CosF

	return Vector3.new(DX, DY, DZ)
end

--[[
    Create a new OceanController.

    Parameters:
        OceanMesh: MeshPart/Part - The skinned mesh with bones (workspace.Ocean.Plane)

    Returns:
        OceanController instance
]]
function OceanController.new(OceanMesh)
	local self = setmetatable({}, OceanController)

	self.OceanMesh = OceanMesh
	self.Bones = {}
	self.Running = false
	self.Connection = nil

	-- Collect all bones
	for _, Child in pairs(OceanMesh:GetDescendants()) do
		if Child:IsA("Bone") then
			table.insert(self.Bones, Child)
		end
	end

	-- Initialize the wave height sampler
	self.HeightSampler = WaveHeightSampler.new(OceanMesh)

	return self
end

--[[
    Update all bones with wave displacement.
]]
function OceanController:_Update()
	-- Time calculation matching reference script
	local Time = DateTime.now().UnixTimestampMillis / 1000 / WaveConfig.TimeModifier

	local LocalPlayer = Players.LocalPlayer
	local Character = LocalPlayer and LocalPlayer.Character
	local MaxDistance = WaveConfig.MaxUpdateDistance
	local MaxDistanceSq = MaxDistance * MaxDistance

	-- Get character position for distance check
	local CharacterPosition = nil
	if Character and Character.PrimaryPart then
		CharacterPosition = Character.PrimaryPart.Position
	end

	for _, Bone in pairs(self.Bones) do
		local WorldPos = Bone.WorldPosition

		-- Distance check (optional, skip if no character)
		local ShouldUpdate = true
		if CharacterPosition then
			local Delta = WorldPos - CharacterPosition
			local DistSq = Delta.X * Delta.X + Delta.Z * Delta.Z
			ShouldUpdate = DistSq < MaxDistanceSq
		end

		if ShouldUpdate then
			-- Sum all wave components
			local TotalDisplacement = Vector3.new(0, 0, 0)

			for _, Wave in ipairs(WaveConfig.Waves) do
				local Displacement = Gerstner(
					WorldPos,
					Wave.Wavelength,
					Wave.Direction,
					Wave.Steepness,
					Wave.Gravity,
					Time
				)
				TotalDisplacement = TotalDisplacement + Displacement
			end

			-- Apply displacement via Transform (this is what deforms the mesh)
			Bone.Transform = CFrame.new(TotalDisplacement)
		else
			-- Reset bones outside range
			Bone.Transform = CFrame.new()
		end
	end
end

--[[
    Start the wave animation loop.
]]
function OceanController:Start()
	if self.Running then
		warn("[OceanController] Already running")
		return
	end

	self.Running = true

	self.Connection = RunService.RenderStepped:Connect(function()
		if not game:IsLoaded() then return end
		self:_Update()
	end)
end

--[[
    Stop the wave animation loop.
]]
function OceanController:Stop()
	if not self.Running then return end

	self.Running = false

	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	-- Reset all bones
	for _, Bone in pairs(self.Bones) do
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
function OceanController:GetWaveHeight(X, Z)
	return self.HeightSampler:GetHeight(X, Z)
end

return OceanController