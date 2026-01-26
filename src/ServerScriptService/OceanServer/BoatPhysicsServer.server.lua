--!strict
--[[
    BoatPhysicsServer

    Server-side boat physics using body movers with wave sampling.

    Height: BodyPosition (Y axis only) - samples average wave height at buoys
    Tilting: BodyGyro (X/Z torque only) - samples pitch from Bow/Stern, roll from Port/Starboard
    Steering: BodyAngularVelocity (Y axis only) - controlled by VehicleSeat input
    Movement: BodyVelocity (XZ plane only) - controlled by VehicleSeat input

    Per-Boat Attributes (all optional, defaults used if not set):
        MaxForwardSpeed: number - Maximum forward speed (studs/sec)
        MaxReverseSpeed: number - Maximum reverse speed (studs/sec)
        Acceleration: number - How fast the boat accelerates (studs/sec²)
        Deceleration: number - How fast the boat drifts to a stop (studs/sec²)
        MaxTurnRate: number - Maximum turn speed (degrees/sec)
        TurnAcceleration: number - How fast turning ramps up (degrees/sec²)
        TurnDeceleration: number - How fast turning eases out (degrees/sec²)
        HeightOffset: number - Vertical offset from wave surface (studs)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local GerstnerWave = require(OceanSystem.Shared.GerstnerWave)
local WaveConfig = require(OceanSystem.Shared.WaveConfig)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)

local BOAT_TAG = "Boat"
local MOVING_SURFACE_TAG = "MovingSurface"

local DEFAULT_MAX_FORWARD_SPEED = 30
local DEFAULT_MAX_REVERSE_SPEED = 15
local DEFAULT_ACCELERATION = 15
local DEFAULT_DECELERATION = 5

local DEFAULT_MAX_TURN_RATE = 15
local DEFAULT_TURN_ACCELERATION = 180
local DEFAULT_TURN_DECELERATION = 120

local DEFAULT_HEIGHT_OFFSET = 0

local BODY_POSITION_MAX_FORCE = math.huge
local BODY_POSITION_DAMPING = 500
local BODY_POSITION_POWER = 5000

local BODY_GYRO_MAX_TORQUE = math.huge
local BODY_GYRO_DAMPING = 500
local BODY_GYRO_POWER = 5000

type BuoyPoints = {
	Bow: BasePart?,
	Stern: BasePart?,
	Port: BasePart?,
	Starboard: BasePart?,
	All: {BasePart},
}

type BoatSettings = {
	MaxForwardSpeed: number,
	MaxReverseSpeed: number,
	Acceleration: number,
	Deceleration: number,
	MaxTurnRate: number,
	TurnAcceleration: number,
	TurnDeceleration: number,
	HeightOffset: number,
}

type BoatData = {
	Model: Model,
	PrimaryPart: BasePart,
	Seat: VehicleSeat?,
	Buoys: BuoyPoints,
	BodyPosition: BodyPosition,
	BodyGyro: BodyGyro,
	BodyVelocity: BodyVelocity,
	BodyAngularVelocity: BodyAngularVelocity,
	Settings: BoatSettings,
	CurrentSpeed: number,
	CurrentTurnSpeed: number,
}

local ActiveBoats: {[Model]: BoatData} = {}
local OceanMesh: MeshPart? = nil

local function GetHorizontalLookVector(Part: BasePart): Vector3
	local Look = Part.CFrame.LookVector
	local Flat = Vector3.new(Look.X, 0, Look.Z)
	local Magnitude = Flat.Magnitude
	if Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return Flat / Magnitude
end

local function MoveTowards(Current: number, Target: number, MaxDelta: number): number
	local Difference = Target - Current
	if math.abs(Difference) <= MaxDelta then
		return Target
	end
	return Current + math.sign(Difference) * MaxDelta
end

local function GetAttribute(Model: Model, Name: string, Default: number): number
	local Value = Model:GetAttribute(Name)
	if typeof(Value) == "number" then
		return Value
	end
	return Default
end

local function ReadBoatSettings(Model: Model): BoatSettings
	return {
		MaxForwardSpeed = GetAttribute(Model, "MaxForwardSpeed", DEFAULT_MAX_FORWARD_SPEED),
		MaxReverseSpeed = GetAttribute(Model, "MaxReverseSpeed", DEFAULT_MAX_REVERSE_SPEED),
		Acceleration = GetAttribute(Model, "Acceleration", DEFAULT_ACCELERATION),
		Deceleration = GetAttribute(Model, "Deceleration", DEFAULT_DECELERATION),
		MaxTurnRate = math.rad(GetAttribute(Model, "MaxTurnRate", DEFAULT_MAX_TURN_RATE)),
		TurnAcceleration = math.rad(GetAttribute(Model, "TurnAcceleration", DEFAULT_TURN_ACCELERATION)),
		TurnDeceleration = math.rad(GetAttribute(Model, "TurnDeceleration", DEFAULT_TURN_DECELERATION)),
		HeightOffset = GetAttribute(Model, "HeightOffset", DEFAULT_HEIGHT_OFFSET),
	}
end

local function InitializeOceanSettings(): ()
	local Ocean = workspace:FindFirstChild("Ocean")
	if not Ocean then
		warn("[BoatPhysicsServer] Ocean folder not found")
		return
	end
	OceanMesh = Ocean:FindFirstChild("Plane") :: MeshPart?
	if OceanMesh then
		OceanSettings:Initialize(OceanMesh, WaveConfig)
	end
end

local function FindVehicleSeat(Model: Model): VehicleSeat?
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("VehicleSeat") then
			return Descendant
		end
	end
	return nil
end

local function FindBuoys(Model: Model): BuoyPoints
	local BuoysFolder = Model:FindFirstChild("Buoys")

	local Result: BuoyPoints = {
		Bow = nil,
		Stern = nil,
		Port = nil,
		Starboard = nil,
		All = {},
	}

	if not BuoysFolder then
		return Result
	end

	Result.Bow = BuoysFolder:FindFirstChild("Bow") :: BasePart?
	Result.Stern = BuoysFolder:FindFirstChild("Stern") :: BasePart?
	Result.Port = BuoysFolder:FindFirstChild("Port") :: BasePart?
	Result.Starboard = BuoysFolder:FindFirstChild("Starboard") :: BasePart?

	for _, Child in BuoysFolder:GetChildren() do
		if Child:IsA("BasePart") then
			table.insert(Result.All, Child)
		end
	end

	return Result
end

local function DisableVehicleSeatPhysics(Seat: VehicleSeat): ()
	Seat.MaxSpeed = 0
	Seat.Torque = 0
	Seat.TurnSpeed = 0
end

local function SetNetworkOwnership(Data: BoatData): ()
	local Seat = Data.Seat
	if not Seat then
		return
	end

	local Owner: Player? = nil
	local Occupant = Seat.Occupant
	if Occupant and Occupant.Parent then
		Owner = Players:GetPlayerFromCharacter(Occupant.Parent)
	end

	pcall(function()
		Data.PrimaryPart:SetNetworkOwner(Owner)
	end)
end

local function GetWaveHeight(PositionX: number, PositionZ: number): number
	return GerstnerWave.GetIdealHeight(PositionX, PositionZ)
end

local function CalculateAverageWaveHeight(Buoys: BuoyPoints): number
	if #Buoys.All == 0 then
		return WaveConfig.BaseWaterHeight
	end

	local TotalHeight = 0
	for _, Buoy in Buoys.All do
		local Position = Buoy.Position
		TotalHeight = TotalHeight + GetWaveHeight(Position.X, Position.Z)
	end

	return TotalHeight / #Buoys.All
end

local function CalculatePitch(Buoys: BuoyPoints): number
	if not Buoys.Bow or not Buoys.Stern then
		return 0
	end

	local BowPosition = Buoys.Bow.Position
	local SternPosition = Buoys.Stern.Position

	local BowHeight = GetWaveHeight(BowPosition.X, BowPosition.Z)
	local SternHeight = GetWaveHeight(SternPosition.X, SternPosition.Z)

	local Distance = (Vector2.new(BowPosition.X, BowPosition.Z) - Vector2.new(SternPosition.X, SternPosition.Z)).Magnitude

	if Distance < 0.01 then
		return 0
	end

	local HeightDifference = BowHeight - SternHeight

	return math.atan2(HeightDifference, Distance)
end

local function CalculateRoll(Buoys: BuoyPoints): number
	if not Buoys.Port or not Buoys.Starboard then
		return 0
	end

	local PortPosition = Buoys.Port.Position
	local StarboardPosition = Buoys.Starboard.Position

	local PortHeight = GetWaveHeight(PortPosition.X, PortPosition.Z)
	local StarboardHeight = GetWaveHeight(StarboardPosition.X, StarboardPosition.Z)

	local Distance = (Vector2.new(PortPosition.X, PortPosition.Z) - Vector2.new(StarboardPosition.X, StarboardPosition.Z)).Magnitude

	if Distance < 0.01 then
		return 0
	end

	local HeightDifference = StarboardHeight - PortHeight

	return math.atan2(HeightDifference, Distance)
end

local function InitializeBoat(Model: Model): ()
	if ActiveBoats[Model] then
		return
	end

	local PrimaryPart = Model.PrimaryPart
	if not PrimaryPart then
		warn("[BoatPhysicsServer] No PrimaryPart:", Model:GetFullName())
		return
	end

	local Buoys = FindBuoys(Model)
	if #Buoys.All == 0 then
		warn("[BoatPhysicsServer] No buoys found in Buoys folder for:", Model.Name)
	end

	local Settings = ReadBoatSettings(Model)

	PrimaryPart.Anchored = false

	for _, Child in PrimaryPart:GetChildren() do
		if Child:IsA("BodyMover") then
			Child:Destroy()
		end
	end

	local BodyPosition = Instance.new("BodyPosition")
	BodyPosition.MaxForce = Vector3.new(0, BODY_POSITION_MAX_FORCE, 0)
	BodyPosition.D = BODY_POSITION_DAMPING
	BodyPosition.P = BODY_POSITION_POWER
	BodyPosition.Position = PrimaryPart.Position
	BodyPosition.Parent = PrimaryPart

	local BodyGyro = Instance.new("BodyGyro")
	BodyGyro.MaxTorque = Vector3.new(BODY_GYRO_MAX_TORQUE, 0, BODY_GYRO_MAX_TORQUE)
	BodyGyro.D = BODY_GYRO_DAMPING
	BodyGyro.P = BODY_GYRO_POWER
	BodyGyro.CFrame = PrimaryPart.CFrame
	BodyGyro.Parent = PrimaryPart

	local BodyVelocity = Instance.new("BodyVelocity")
	BodyVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
	BodyVelocity.Velocity = Vector3.zero
	BodyVelocity.Parent = PrimaryPart

	local BodyAngularVelocity = Instance.new("BodyAngularVelocity")
	BodyAngularVelocity.MaxTorque = Vector3.new(0, math.huge, 0)
	BodyAngularVelocity.AngularVelocity = Vector3.zero
	BodyAngularVelocity.Parent = PrimaryPart

	local Seat = FindVehicleSeat(Model)

	local Data: BoatData = {
		Model = Model,
		PrimaryPart = PrimaryPart,
		Seat = Seat,
		Buoys = Buoys,
		BodyPosition = BodyPosition,
		BodyGyro = BodyGyro,
		BodyVelocity = BodyVelocity,
		BodyAngularVelocity = BodyAngularVelocity,
		Settings = Settings,
		CurrentSpeed = 0,
		CurrentTurnSpeed = 0,
	}

	ActiveBoats[Model] = Data
	CollectionService:AddTag(Model, MOVING_SURFACE_TAG)

	if Seat then
		DisableVehicleSeatPhysics(Seat)
		Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			SetNetworkOwnership(Data)
		end)
	end

	print("[BoatPhysicsServer] Initialized boat:", Model.Name, "with", #Buoys.All, "buoys")
end

local function RemoveBoat(Model: Model): ()
	local Data = ActiveBoats[Model]
	if Data then
		if Data.BodyPosition then
			Data.BodyPosition:Destroy()
		end
		if Data.BodyGyro then
			Data.BodyGyro:Destroy()
		end
		if Data.BodyVelocity then
			Data.BodyVelocity:Destroy()
		end
		if Data.BodyAngularVelocity then
			Data.BodyAngularVelocity:Destroy()
		end
	end
	ActiveBoats[Model] = nil
end

local function UpdateBoatHeight(Data: BoatData): ()
	local WaveHeight = CalculateAverageWaveHeight(Data.Buoys)
	local TargetHeight = WaveHeight + Data.Settings.HeightOffset

	local CurrentPosition = Data.PrimaryPart.Position
	Data.BodyPosition.Position = Vector3.new(
		CurrentPosition.X,
		TargetHeight,
		CurrentPosition.Z
	)
end

local function UpdateBoatTilt(Data: BoatData): ()
	local TargetPitch = CalculatePitch(Data.Buoys)
	local TargetRoll = CalculateRoll(Data.Buoys)

	local CurrentCFrame = Data.PrimaryPart.CFrame
	local LookVector = CurrentCFrame.LookVector

	local FlatLook = Vector3.new(LookVector.X, 0, LookVector.Z)
	if FlatLook.Magnitude < 0.01 then
		FlatLook = Vector3.new(0, 0, -1)
	else
		FlatLook = FlatLook.Unit
	end

	local Position = CurrentCFrame.Position
	local BaseCFrame = CFrame.lookAt(Position, Position + FlatLook)
	local TiltedCFrame = BaseCFrame * CFrame.Angles(TargetPitch, 0, TargetRoll)

	Data.BodyGyro.CFrame = TiltedCFrame
end

local function UpdateBoatMovement(Data: BoatData, DeltaTime: number): ()
	local Throttle = 0
	local Steer = 0

	if Data.Seat then
		Throttle = Data.Seat.Throttle
		Steer = Data.Seat.Steer
	end

	local Settings = Data.Settings

	local TargetTurnSpeed = 0
	if Steer == 1 then
		TargetTurnSpeed = -Settings.MaxTurnRate
	elseif Steer == -1 then
		TargetTurnSpeed = Settings.MaxTurnRate
	end

	if Steer ~= 0 then
		Data.CurrentTurnSpeed = MoveTowards(
			Data.CurrentTurnSpeed,
			TargetTurnSpeed,
			Settings.TurnAcceleration * DeltaTime
		)
	else
		Data.CurrentTurnSpeed = MoveTowards(
			Data.CurrentTurnSpeed,
			0,
			Settings.TurnDeceleration * DeltaTime
		)
	end

	Data.BodyAngularVelocity.AngularVelocity = Vector3.new(0, Data.CurrentTurnSpeed, 0)

	local TargetSpeed = 0
	if Throttle == 1 then
		TargetSpeed = Settings.MaxForwardSpeed
	elseif Throttle == -1 then
		TargetSpeed = -Settings.MaxReverseSpeed
	end

	if Throttle ~= 0 then
		Data.CurrentSpeed = MoveTowards(
			Data.CurrentSpeed,
			TargetSpeed,
			Settings.Acceleration * DeltaTime
		)
	else
		Data.CurrentSpeed = MoveTowards(
			Data.CurrentSpeed,
			0,
			Settings.Deceleration * DeltaTime
		)
	end

	local Forward = GetHorizontalLookVector(Data.PrimaryPart)
	Data.BodyVelocity.Velocity = Forward * Data.CurrentSpeed
end

local function UpdateBoat(Data: BoatData, DeltaTime: number): ()
	UpdateBoatHeight(Data)
	UpdateBoatTilt(Data)
	UpdateBoatMovement(Data, DeltaTime)
end

local function OnHeartbeat(DeltaTime: number): ()
	for _, Data in ActiveBoats do
		UpdateBoat(Data, DeltaTime)
	end
end

local function SetupExistingBoats(): ()
	for _, Model in CollectionService:GetTagged(BOAT_TAG) do
		if Model:IsA("Model") then
			InitializeBoat(Model)
		end
	end

	local BoatsFolder = workspace:FindFirstChild("Boats")
	if BoatsFolder then
		for _, Child in BoatsFolder:GetChildren() do
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

InitializeOceanSettings()
SetupExistingBoats()