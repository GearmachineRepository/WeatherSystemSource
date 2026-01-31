--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
local OceanSystem = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OceanSystem")
local GerstnerWave = require(OceanSystem.Shared.GerstnerWave)
local OceanSettings = require(OceanSystem.Shared.OceanSettings)
local BuoyUtils = require(OceanSystem.Shared.BuoyUtils)

local BOAT_TAG = "Boat"

local DEFAULT_MAX_FORWARD_SPEED = 30 --30
local DEFAULT_MAX_REVERSE_SPEED = 15
local DEFAULT_ACCELERATION = 15
local DEFAULT_DECELERATION = 5
local DEFAULT_MAX_TURN_RATE = 20 --15
local DEFAULT_TURN_ACCELERATION = 90
local DEFAULT_TURN_DECELERATION = 120
local DEFAULT_HEIGHT_OFFSET = 0

local BODY_POSITION_MAX_FORCE = math.huge
local BODY_POSITION_DAMPING = 500
local BODY_POSITION_POWER = 5000
local BODY_GYRO_MAX_TORQUE = math.huge
local BODY_GYRO_DAMPING = 500
local BODY_GYRO_POWER = 5000

local OCCUPIED_UPDATE_RATE = 30
local IDLE_UPDATE_RATE = 10

local OCCUPIED_UPDATE_INTERVAL = 1 / OCCUPIED_UPDATE_RATE
local IDLE_UPDATE_INTERVAL = 1 / IDLE_UPDATE_RATE

local OWNERSHIP_RELEASE_SPEED = 0.25
local OWNERSHIP_RELEASE_DELAY = 1.0

local MOVING_SPEED_THRESHOLD = 0.25

local WAVE_CALCULATION_RANGE = 300
local WAVE_CALCULATION_RANGE_SQUARED = WAVE_CALCULATION_RANGE * WAVE_CALCULATION_RANGE
local PLAYER_POSITION_UPDATE_INTERVAL = 0.5

type ControlInputs = {
	Throttle: number,
	Steer: number,
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
	Buoys: BuoyUtils.BuoyPoints,
	BodyPosition: BodyPosition,
	BodyGyro: BodyGyro,
	BodyVelocity: BodyVelocity,
	BodyAngularVelocity: BodyAngularVelocity,
	Settings: BoatSettings,
	CurrentSpeed: number,
	CurrentTurnSpeed: number,
	UpdateAccumulator: number,
	Trove: typeof(Trove.new()),
	LastOwner: Player?,
	LastOccupantChangeTime: number,
	WavesActive: boolean,
}

type CachedPlayerPosition = {
	X: number,
	Z: number,
}

local ActiveBoats: {[Model]: BoatData} = {}
local CachedPlayerPositions: {CachedPlayerPosition} = {}
local PlayerPositionUpdateAccumulator = 0
local MainTrove = Trove.new()

local function ReadAiInputs(Model: Model): ControlInputs
	local ThrottleValue = Model:GetAttribute("AiThrottle")
	local SteerValue = Model:GetAttribute("AiSteer")

	local Throttle = if typeof(ThrottleValue) == "number" then math.clamp(ThrottleValue, -1, 1) else 0
	local Steer = if typeof(SteerValue) == "number" then math.clamp(SteerValue, -1, 1) else 0

	return {
		Throttle = Throttle,
		Steer = Steer,
	}
end

local function GetControlInputs(Data: BoatData): ControlInputs
	local Seat = Data.Seat
	if Seat and Seat.Occupant ~= nil then
		return {
			Throttle = Seat.Throttle,
			Steer = Seat.Steer,
		}
	end

	if CollectionService:HasTag(Data.Model, "Agent") then
		return ReadAiInputs(Data.Model)
	end

	return { Throttle = 0, Steer = 0 }
end

local function GetWaveHeight(PositionX: number, PositionZ: number): number
	return GerstnerWave.GetIdealHeight(PositionX, PositionZ)
end

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

local function FindVehicleSeat(Model: Model): VehicleSeat?
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("VehicleSeat") then
			return Descendant
		end
	end
	return nil
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

	local CurrentTime = os.clock()

	local OccupantHumanoid = Seat.Occupant :: Humanoid?
	if OccupantHumanoid then
		local Character = OccupantHumanoid.Parent :: Model?
		local Owner = if Character then Players:GetPlayerFromCharacter(Character) else nil

		Data.LastOwner = Owner
		Data.LastOccupantChangeTime = CurrentTime

		if Owner then
			pcall(function()
				Data.PrimaryPart:SetNetworkOwner(Owner)
			end)
		end

		return
	end

	if Data.CurrentSpeed > OWNERSHIP_RELEASE_SPEED then
		local LastOwner = Data.LastOwner
		if LastOwner and LastOwner.Parent then
			pcall(function()
				Data.PrimaryPart:SetNetworkOwner(LastOwner)
			end)
		end
		return
	end

	if CurrentTime - Data.LastOccupantChangeTime < OWNERSHIP_RELEASE_DELAY then
		return
	end

	pcall(function()
		Data.PrimaryPart:SetNetworkOwner(nil)
	end)
end

local function CreateBodyMovers(PrimaryPart: BasePart, BoatTrove: typeof(Trove.new())): (BodyPosition, BodyGyro, BodyVelocity, BodyAngularVelocity)
	local Position = BoatTrove:Construct(Instance.new, "BodyPosition") :: BodyPosition
	Position.MaxForce = Vector3.new(0, BODY_POSITION_MAX_FORCE, 0)
	Position.D = BODY_POSITION_DAMPING
	Position.P = BODY_POSITION_POWER
	Position.Position = PrimaryPart.Position
	Position.Parent = PrimaryPart

	local Gyro = BoatTrove:Construct(Instance.new, "BodyGyro") :: BodyGyro
	Gyro.MaxTorque = Vector3.new(BODY_GYRO_MAX_TORQUE, 0, BODY_GYRO_MAX_TORQUE)
	Gyro.D = BODY_GYRO_DAMPING
	Gyro.P = BODY_GYRO_POWER
	Gyro.CFrame = PrimaryPart.CFrame
	Gyro.Parent = PrimaryPart

	local Velocity = BoatTrove:Construct(Instance.new, "BodyVelocity") :: BodyVelocity
	Velocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
	Velocity.Velocity = Vector3.zero
	Velocity.Parent = PrimaryPart

	local AngularVelocity = BoatTrove:Construct(Instance.new, "BodyAngularVelocity") :: BodyAngularVelocity
	AngularVelocity.MaxTorque = Vector3.new(0, math.huge, 0)
	AngularVelocity.AngularVelocity = Vector3.zero
	AngularVelocity.Parent = PrimaryPart

	return Position, Gyro, Velocity, AngularVelocity
end

local function UpdateCachedPlayerPositions(): ()
	table.clear(CachedPlayerPositions)

	for _, Player in Players:GetPlayers() do
		local Character = Player.Character
		if Character then
			local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if RootPart then
				local Position = RootPart.Position
				table.insert(CachedPlayerPositions, {
					X = Position.X,
					Z = Position.Z,
				})
			end
		end
	end
end

local function IsAnyPlayerNearby(BoatX: number, BoatZ: number): boolean
	for _, PlayerPos in CachedPlayerPositions do
		local DeltaX = BoatX - PlayerPos.X
		local DeltaZ = BoatZ - PlayerPos.Z
		local DistanceSquared = DeltaX * DeltaX + DeltaZ * DeltaZ

		if DistanceSquared < WAVE_CALCULATION_RANGE_SQUARED then
			return true
		end
	end

	return false
end

local function UpdateBoatHeight(Data: BoatData): ()
	local AverageHeight = BuoyUtils.CalculateAverageHeight(Data.Buoys, GetWaveHeight)
	local TargetHeight = AverageHeight + Data.Settings.HeightOffset

	local CurrentPosition = Data.PrimaryPart.Position
	Data.BodyPosition.Position = Vector3.new(
		CurrentPosition.X,
		TargetHeight,
		CurrentPosition.Z
	)
end

local function UpdateBoatTilt(Data: BoatData): ()
	local TargetPitch = BuoyUtils.CalculatePitch(Data.Buoys, GetWaveHeight)
	local TargetRoll = BuoyUtils.CalculateRoll(Data.Buoys, GetWaveHeight)

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

local function FlattenBoatTilt(Data: BoatData): ()
	local CurrentCFrame = Data.PrimaryPart.CFrame
	local LookVector = CurrentCFrame.LookVector

	local FlatLook = Vector3.new(LookVector.X, 0, LookVector.Z)
	if FlatLook.Magnitude < 0.01 then
		FlatLook = Vector3.new(0, 0, -1)
	else
		FlatLook = FlatLook.Unit
	end

	local Position = CurrentCFrame.Position
	local FlatCFrame = CFrame.lookAt(Position, Position + FlatLook)

	Data.BodyGyro.CFrame = FlatCFrame
end

local function HoldBoatAtCurrentHeight(Data: BoatData): ()
	local CurrentPosition = Data.PrimaryPart.Position
	Data.BodyPosition.Position = CurrentPosition
end

-- Replace the UpdateBoatMovement function in BoatPhysicsServer.server.lua with this:

local function UpdateBoatMovement(Data: BoatData, DeltaTime: number): ()
	local Inputs = GetControlInputs(Data)
	local Throttle = Inputs.Throttle
	local Steer = Inputs.Steer

	local Settings = Data.Settings

	local TargetTurnSpeed = -Steer * Settings.MaxTurnRate

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
	if Throttle > 0 then
		TargetSpeed = Throttle * Settings.MaxForwardSpeed
	elseif Throttle < 0 then
		TargetSpeed = Throttle * Settings.MaxReverseSpeed
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

	SetNetworkOwnership(Data)
end

local function UpdateBoat(Data: BoatData, DeltaTime: number): ()
	local BoatPosition = Data.PrimaryPart.Position
	local ShouldCalculateWaves = IsAnyPlayerNearby(BoatPosition.X, BoatPosition.Z)

	if ShouldCalculateWaves then
		if not Data.WavesActive then
			Data.WavesActive = true
		end
		UpdateBoatHeight(Data)
		UpdateBoatTilt(Data)
	else
		if Data.WavesActive then
			Data.WavesActive = false
			FlattenBoatTilt(Data)
		end
		HoldBoatAtCurrentHeight(Data)
	end

	UpdateBoatMovement(Data, DeltaTime)
end

local function RemoveBoat(Model: Model): ()
	local Data = ActiveBoats[Model]
	if not Data then
		return
	end

	Data.Trove:Destroy()
	ActiveBoats[Model] = nil
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

	local Buoys = BuoyUtils.FindBuoys(Model)
	if #Buoys.All == 0 then
		Buoys = BuoyUtils.CreateDefaultBuoys(Model)
	end

	if not BuoyUtils.ValidateBuoys(Buoys) then
		warn("[BoatPhysicsServer] Missing required buoys for:", Model.Name)
	end

	local Settings = ReadBoatSettings(Model)
	local BoatTrove = Trove.new()

	local BodyPosition, BodyGyro, BodyVelocity, BodyAngularVelocity = CreateBodyMovers(PrimaryPart, BoatTrove)

	local Seat = FindVehicleSeat(Model)
	if Seat then
		DisableVehicleSeatPhysics(Seat)
	end

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
		UpdateAccumulator = 0,
		Trove = BoatTrove,
		LastOwner = nil,
		LastOccupantChangeTime = 0,
		WavesActive = true,
	}

	if Seat then
		BoatTrove:Connect(Seat:GetPropertyChangedSignal("Occupant"), function()
			SetNetworkOwnership(Data)
		end)
		SetNetworkOwnership(Data)
	end

	BoatTrove:AttachToInstance(Model)

	ActiveBoats[Model] = Data
	CollectionService:AddTag(Model, "MovingSurface")
end

local function InitializeOceanSettings(): ()
	local Configuration = ReplicatedStorage:WaitForChild("OceanConfiguration", 10) :: Configuration?
	if not Configuration then
		warn("[BoatPhysicsServer] OceanConfiguration not found in ReplicatedStorage")
		return
	end

	OceanSettings.Initialize(Configuration)
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

local function IsOccupied(Data: BoatData): boolean
	if not Data.Seat then
		return false
	end
	return Data.Seat.Occupant ~= nil
end

local function GetUpdateInterval(Data: BoatData): number
	if IsOccupied(Data) then
		return OCCUPIED_UPDATE_INTERVAL
	end

	if math.abs(Data.CurrentSpeed) > MOVING_SPEED_THRESHOLD or math.abs(Data.CurrentTurnSpeed) > math.rad(1) then
		return OCCUPIED_UPDATE_INTERVAL
	end

	return IDLE_UPDATE_INTERVAL
end

local function OnHeartbeat(DeltaTime: number): ()
	PlayerPositionUpdateAccumulator += DeltaTime
	if PlayerPositionUpdateAccumulator >= PLAYER_POSITION_UPDATE_INTERVAL then
		UpdateCachedPlayerPositions()
		PlayerPositionUpdateAccumulator = 0
	end

	for _, Data in pairs(ActiveBoats) do
		Data.UpdateAccumulator += DeltaTime

		local Interval = GetUpdateInterval(Data)

		if Data.UpdateAccumulator >= Interval then
			UpdateBoat(Data, Data.UpdateAccumulator)
			Data.UpdateAccumulator = 0
		end
	end
end

MainTrove:Connect(CollectionService:GetInstanceAddedSignal(BOAT_TAG), function(Instance)
	if Instance:IsA("Model") then
		InitializeBoat(Instance)
	end
end)

MainTrove:Connect(CollectionService:GetInstanceRemovedSignal(BOAT_TAG), function(Instance)
	if Instance:IsA("Model") then
		RemoveBoat(Instance)
	end
end)

MainTrove:Connect(RunService.Heartbeat, OnHeartbeat)

InitializeOceanSettings()
SetupExistingBoats()