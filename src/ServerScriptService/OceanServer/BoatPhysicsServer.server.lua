--!strict
--[[
    BoatPhysicsServer
    Server-side boat movement and buoyancy using BodyMovers.

    Setup:
    1. Boat Model with PrimaryPart set (the hull)
    2. PrimaryPart should be a BasePart (not MeshPart ideally for physics)
    3. VehicleSeat inside the boat
    4. Tag boat with "Boat" or place in workspace.Boats folder
    5. Add a "Buoys" folder with Bow, Stern, Port, Starboard parts

    The script will add BodyMovers automatically if not present.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local GerstnerWave = require(OceanSystem.Shared.GerstnerWave)
local WaveConfig = require(OceanSystem.Shared.WaveConfig)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)

local Ocean = workspace:WaitForChild("Ocean", 30)
local OceanMesh = Ocean and Ocean:WaitForChild("Plane", 10)

if OceanMesh then
	OceanSettings:Initialize(OceanMesh, WaveConfig)
else
	warn("[BoatPhysicsServer] Could not find Ocean mesh for settings initialization")
end

local BOAT_TAG = "Boat"

local FORWARD_SPEED = 50
local REVERSE_SPEED = 25
local TURN_SPEED = 0.5

local BODY_POSITION_MAX_FORCE = Vector3.new(0, math.huge, 0)
local BODY_POSITION_DAMPING = 0.5
local BODY_POSITION_POWER = 1

local BODY_GYRO_MAX_TORQUE = Vector3.new(math.huge, math.huge, math.huge)
local BODY_GYRO_DAMPING = 0.8
local BODY_GYRO_POWER = 1

local BODY_VELOCITY_MAX_FORCE = Vector3.new(math.huge, 0, math.huge)

type BoatData = {
	Model: Model,
	PrimaryPart: BasePart,
	Seat: VehicleSeat?,
	BodyPosition: BodyPosition,
	BodyGyro: BodyGyro,
	BodyVelocity: BodyVelocity,
	Bow: BasePart?,
	Stern: BasePart?,
	Port: BasePart?,
	Starboard: BasePart?,
	CurrentYaw: number,
	HeightOffset: number,
}

local ActiveBoats: { [Model]: BoatData } = {}

--[[
    Find or create a BodyMover in a part.
]]
local function GetOrCreateBodyMover<T>(Parent: BasePart, ClassName: string)
	local Existing = Parent:FindFirstChildOfClass(ClassName)
	if Existing then
		return Existing
	end

	local New = Instance.new(ClassName)
	New.Parent = Parent
	return New
end

--[[
    Find VehicleSeat in a model.
]]
local function FindVehicleSeat(Model: Model): VehicleSeat?
	for _, Descendant in pairs(Model:GetDescendants()) do
		if Descendant:IsA("VehicleSeat") then
			return Descendant
		end
	end
	return nil
end

--[[
    Find buoy parts in the boat.
]]
local function FindBuoys(Model: Model): (BasePart?, BasePart?, BasePart?, BasePart?)
	local BuoysFolder = Model:FindFirstChild("Buoys")
	if not BuoysFolder then
		return nil, nil, nil, nil
	end

	local Bow = BuoysFolder:FindFirstChild("Bow") :: BasePart?
	local Stern = BuoysFolder:FindFirstChild("Stern") :: BasePart?
	local Port = BuoysFolder:FindFirstChild("Port") :: BasePart?
	local Starboard = BuoysFolder:FindFirstChild("Starboard") :: BasePart?

	return Bow, Stern, Port, Starboard
end

--[[
    Get wave height at a position using Gerstner formula.
]]
local function GetWaveHeight(X: number, Z: number): number
	return GerstnerWave.GetIdealHeight(X, Z)
end

--[[
    Calculate average height from buoy positions.
]]
local function CalculateAverageHeight(Data: BoatData): number
	local Positions = {}

	if Data.Bow then
		table.insert(Positions, Data.Bow.Position)
	end
	if Data.Stern then
		table.insert(Positions, Data.Stern.Position)
	end
	if Data.Port then
		table.insert(Positions, Data.Port.Position)
	end
	if Data.Starboard then
		table.insert(Positions, Data.Starboard.Position)
	end

	if #Positions == 0 then
		local Pos = Data.PrimaryPart.Position
		return GetWaveHeight(Pos.X, Pos.Z)
	end

	local TotalHeight = 0
	for _, Pos in ipairs(Positions) do
		TotalHeight = TotalHeight + GetWaveHeight(Pos.X, Pos.Z)
	end

	return TotalHeight / #Positions
end

--[[
    Calculate pitch angle from bow/stern wave heights.
]]
local function CalculatePitch(Data: BoatData): number
	if not Data.Bow or not Data.Stern then
		return 0
	end

	local BowPos = Data.Bow.Position
	local SternPos = Data.Stern.Position

	local BowHeight = GetWaveHeight(BowPos.X, BowPos.Z)
	local SternHeight = GetWaveHeight(SternPos.X, SternPos.Z)

	local Distance = (Vector2.new(BowPos.X, BowPos.Z) - Vector2.new(SternPos.X, SternPos.Z)).Magnitude

	if Distance < 0.01 then
		return 0
	end

	return math.atan2(BowHeight - SternHeight, Distance)
end

--[[
    Calculate roll angle from port/starboard wave heights.
]]
local function CalculateRoll(Data: BoatData): number
	if not Data.Port or not Data.Starboard then
		return 0
	end

	local PortPos = Data.Port.Position
	local StarboardPos = Data.Starboard.Position

	local PortHeight = GetWaveHeight(PortPos.X, PortPos.Z)
	local StarboardHeight = GetWaveHeight(StarboardPos.X, StarboardPos.Z)

	local Distance = (Vector2.new(PortPos.X, PortPos.Z) - Vector2.new(StarboardPos.X, StarboardPos.Z)).Magnitude

	if Distance < 0.01 then
		return 0
	end

	return math.atan2(StarboardHeight - PortHeight, Distance)
end

--[[
    Initialize a boat with BodyMovers.
]]
local function InitializeBoat(Model: Model): ()
	if ActiveBoats[Model] then
		return
	end

	local PrimaryPart = Model.PrimaryPart
	if not PrimaryPart then
		warn("[BoatPhysicsServer] Boat has no PrimaryPart:", Model:GetFullName())
		return
	end

	PrimaryPart.Anchored = false

	local BodyPosition = GetOrCreateBodyMover(PrimaryPart, "BodyPosition") :: BodyPosition
	BodyPosition.MaxForce = BODY_POSITION_MAX_FORCE
	BodyPosition.D = BODY_POSITION_DAMPING
	BodyPosition.P = BODY_POSITION_POWER
	BodyPosition.Position = PrimaryPart.Position

	local BodyGyro = GetOrCreateBodyMover(PrimaryPart, "BodyGyro") :: BodyGyro
	BodyGyro.MaxTorque = BODY_GYRO_MAX_TORQUE
	BodyGyro.D = BODY_GYRO_DAMPING
	BodyGyro.P = BODY_GYRO_POWER
	BodyGyro.CFrame = PrimaryPart.CFrame

	local BodyVelocity = GetOrCreateBodyMover(PrimaryPart, "BodyVelocity") :: BodyVelocity
	BodyVelocity.MaxForce = BODY_VELOCITY_MAX_FORCE
	BodyVelocity.Velocity = Vector3.zero

	local Seat = FindVehicleSeat(Model)
	local Bow, Stern, Port, Starboard = FindBuoys(Model)

	local _, CurrentYaw, _ = PrimaryPart.CFrame:ToEulerAnglesYXZ()

	local Data: BoatData = {
		Model = Model,
		PrimaryPart = PrimaryPart,
		Seat = Seat,
		BodyPosition = BodyPosition,
		BodyGyro = BodyGyro,
		BodyVelocity = BodyVelocity,
		Bow = Bow,
		Stern = Stern,
		Port = Port,
		Starboard = Starboard,
		CurrentYaw = CurrentYaw,
		HeightOffset = 2,
	}

	ActiveBoats[Model] = Data

	print("[BoatPhysicsServer] Initialized boat:", Model.Name)
end

--[[
    Remove a boat from the system.
]]
local function RemoveBoat(Model: Model): ()
	ActiveBoats[Model] = nil
end

--[[
    Update a single boat's physics.
]]
local function UpdateBoat(Data: BoatData, DeltaTime: number): ()
	local Seat = Data.Seat
	local Throttle = 0
	local Steer = 0

	if Seat then
		Throttle = Seat.Throttle
		Steer = Seat.Steer
	end

	Data.CurrentYaw = Data.CurrentYaw - (Steer * TURN_SPEED * DeltaTime)

	local Speed = 0
	if Throttle > 0 then
		Speed = FORWARD_SPEED * Throttle
	elseif Throttle < 0 then
		Speed = REVERSE_SPEED * Throttle
	end

	local YawCFrame = CFrame.Angles(0, Data.CurrentYaw, 0)
	local LookVector = YawCFrame.LookVector
	Data.BodyVelocity.Velocity = LookVector * Speed

	local WaveHeight = CalculateAverageHeight(Data) + Data.HeightOffset
	local CurrentPos = Data.PrimaryPart.Position
	Data.BodyPosition.Position = Vector3.new(CurrentPos.X, WaveHeight, CurrentPos.Z)

	local Pitch = CalculatePitch(Data)
	local Roll = CalculateRoll(Data)
	Data.BodyGyro.CFrame = CFrame.Angles(Pitch, Data.CurrentYaw, Roll)
end

--[[
    Main update loop.
]]
local function OnHeartbeat(DeltaTime: number): ()
	for _, Data in pairs(ActiveBoats) do
		UpdateBoat(Data, DeltaTime)
	end
end

--[[
    Setup existing boats.
]]
local function SetupExistingBoats(): ()
	for _, Model in pairs(CollectionService:GetTagged(BOAT_TAG)) do
		if Model:IsA("Model") then
			InitializeBoat(Model)
		end
	end

	local BoatsFolder = workspace:FindFirstChild("Boats")
	if BoatsFolder then
		for _, Child in pairs(BoatsFolder:GetChildren()) do
			if Child:IsA("Model") then
				InitializeBoat(Child)
			end
		end
	end
end

CollectionService:GetInstanceAddedSignal(BOAT_TAG):Connect(function(Instance)
	if Instance:IsA("Model") then
		InitializeBoat(Instance)
	end
end)

CollectionService:GetInstanceRemovedSignal(BOAT_TAG):Connect(function(Instance)
	if Instance:IsA("Model") then
		RemoveBoat(Instance)
	end
end)

RunService.Heartbeat:Connect(OnHeartbeat)

SetupExistingBoats()