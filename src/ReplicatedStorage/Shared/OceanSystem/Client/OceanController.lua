--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
local OceanConfig = require(script.Parent.Parent.Shared.OceanConfig)
local OceanSettings = require(script.Parent.Parent.Shared.OceanSettings)
local GerstnerWave = require(script.Parent.Parent.Shared.GerstnerWave)
local WaveHeightSampler = require(script.Parent.Parent.Shared.WaveHeightSampler)

local OceanController = {}
OceanController.__index = OceanController

export type OceanController = typeof(setmetatable({} :: {
	OceanMesh: MeshPart,
	Bones: {Bone},
	Running: boolean,
	_Trove: typeof(Trove.new()),
	HeightSampler: WaveHeightSampler.WaveHeightSampler,
}, OceanController))

function OceanController.new(OceanMesh: MeshPart): OceanController
	local self = setmetatable({}, OceanController) :: any

	self.OceanMesh = OceanMesh
	self.Bones = {}
	self.Running = false
	self._Trove = Trove.new()

	for _, Child in OceanMesh:GetDescendants() do
		if Child:IsA("Bone") then
			table.insert(self.Bones, Child)
		end
	end

	self.HeightSampler = WaveHeightSampler.new(OceanMesh)

	return self
end

function OceanController._Update(self: OceanController): ()
	local Time = GerstnerWave.GetSyncedTime()
	local Waves = OceanSettings.GetWaves()

	local LocalPlayer = Players.LocalPlayer
	local Character = LocalPlayer and LocalPlayer.Character
	local MaxDistance = OceanConfig.MAX_UPDATE_DISTANCE
	local MaxDistanceSquared = MaxDistance * MaxDistance

	local CharacterPosition: Vector3? = nil
	if Character and Character.PrimaryPart then
		local PrimaryPart = Character.PrimaryPart :: BasePart?
		if not PrimaryPart then return end
		CharacterPosition = PrimaryPart.Position
	end

	for _, Bone in self.Bones do
		local WorldPosition = Bone.WorldPosition :: Vector3

		local ShouldUpdate = true
		if CharacterPosition then
			local Delta = WorldPosition - CharacterPosition
			local DistanceSquared = Delta.X * Delta.X + Delta.Z * Delta.Z
			ShouldUpdate = DistanceSquared < MaxDistanceSquared
		end

		if ShouldUpdate then
			local TotalDisplacement = Vector3.zero

			for _, Wave in Waves do
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

function OceanController.Start(self: OceanController): ()
	if self.Running then
		warn("[OceanController] Already running")
		return
	end

	self.Running = true

	self._Trove:Connect(RunService.RenderStepped, function()
		if not game:IsLoaded() then
			return
		end
		self:_Update()
	end)
end

function OceanController.Stop(self: OceanController): ()
	if not self.Running then
		return
	end

	self.Running = false
	self._Trove:Clean()

	for _, Bone in self.Bones do
		Bone.Transform = CFrame.new()
	end
end

function OceanController.GetHeightSampler(self: OceanController): WaveHeightSampler.WaveHeightSampler
	return self.HeightSampler
end

function OceanController.GetWaveHeight(self: OceanController, PositionX: number, PositionZ: number): number
	return self.HeightSampler:GetHeight(PositionX, PositionZ)
end

function OceanController.Destroy(self: OceanController): ()
	self:Stop()
	self._Trove:Destroy()
	self.Bones = {}
end

return OceanController