--!strict
--[[
    BoatPhysicsServer

    VectorForce-based buoyancy following DevVexus's approach.

    Setup Requirements:
    1. Boat Model with PrimaryPart (this becomes the "mass holder")
    2. All OTHER parts in the boat should be Massless = true
    3. Buoys folder with BaseParts representing buoy positions
    4. Each buoy will get an Attachment + VectorForce created automatically

    The system:
    - Calculates displaced volume based on depth underwater
    - Applies upward VectorForce proportional to displaced volume
    - Includes velocity-based damping to prevent oscillation
    - Physics naturally handles tilting when buoys have different depths
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

local MAX_FORWARD_SPEED = 30
local MAX_REVERSE_SPEED = 15
local SPEED_INCREMENT = 15
local SPEED_DECREMENT = 20
local TURN_RATE = 1.5

local WATER_DENSITY = 1.025
local BUOY_RADIUS = 38.0
local DAMPING_COEFFICIENT = 45.8
local HEIGHT_OFFSET = 0

type BuoyData = {
    Part: BasePart,
    Attachment: Attachment,
    VectorForce: VectorForce,
}

type BoatData = {
    Model: Model,
    PrimaryPart: BasePart,
    Seat: VehicleSeat?,
    BodyVelocity: BodyVelocity,
    BodyAngularVelocity: BodyAngularVelocity,
    Buoys: {BuoyData},
    CurrentSpeed: number,
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

local function CalculateSphereSubmergedVolume(Radius: number, Depth: number): number
    if Depth <= 0 then
        return 0
    end

    if Depth >= Radius * 2 then
        return (4 / 3) * math.pi * Radius ^ 3
    end

    local Height = math.min(Depth, Radius * 2)
    return (math.pi / 3) * Height ^ 2 * (3 * Radius - Height)
end

local function GetWaveHeight(PositionX: number, PositionZ: number): number
    return GerstnerWave.GetIdealHeight(PositionX, PositionZ)
end

local function SetupBuoys(Model: Model, PrimaryPart: BasePart): {BuoyData}
    local BuoysFolder = Model:FindFirstChild("Buoys")
    if not BuoysFolder then
        return {}
    end

    local BuoyDataList: {BuoyData} = {}

    for _, Child in BuoysFolder:GetChildren() do
        if Child:IsA("BasePart") then
            local BuoyPart = Child

            local ExistingAttachment = BuoyPart:FindFirstChild("BuoyAttachment")
            if ExistingAttachment then
                ExistingAttachment:Destroy()
            end

            local Attachment = Instance.new("Attachment")
            Attachment.Name = "BuoyAttachment"
            Attachment.Parent = BuoyPart

            local VectorForceInstance = Instance.new("VectorForce")
            VectorForceInstance.Name = "BuoyForce"
            VectorForceInstance.ApplyAtCenterOfMass = false
            VectorForceInstance.Attachment0 = Attachment
            VectorForceInstance.RelativeTo = Enum.ActuatorRelativeTo.World
            VectorForceInstance.Force = Vector3.zero
            VectorForceInstance.Parent = BuoyPart

            local BuoyEntry: BuoyData = {
                Part = BuoyPart,
                Attachment = Attachment,
                VectorForce = VectorForceInstance,
            }

            table.insert(BuoyDataList, BuoyEntry)
        end
    end

    return BuoyDataList
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

local function MakeShipMassless(Model: Model, PrimaryPart: BasePart): ()
    for _, Descendant in Model:GetDescendants() do
        if Descendant:IsA("BasePart") and Descendant ~= PrimaryPart then
            Descendant.Massless = true
        end
    end
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

    PrimaryPart.Anchored = false

    for _, Child in PrimaryPart:GetChildren() do
        if Child:IsA("BodyMover") then
            Child:Destroy()
        end
    end

    MakeShipMassless(Model, PrimaryPart)

    local BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
    BodyVelocity.Velocity = Vector3.zero
    BodyVelocity.Parent = PrimaryPart

    local BodyAngularVelocity = Instance.new("BodyAngularVelocity")
    BodyAngularVelocity.MaxTorque = Vector3.new(0, math.huge, 0)
    BodyAngularVelocity.AngularVelocity = Vector3.zero
    BodyAngularVelocity.Parent = PrimaryPart

    local Seat = FindVehicleSeat(Model)
    local Buoys = SetupBuoys(Model, PrimaryPart)

    if #Buoys == 0 then
        warn("[BoatPhysicsServer] No buoys found for:", Model.Name)
    end

    local Data: BoatData = {
        Model = Model,
        PrimaryPart = PrimaryPart,
        Seat = Seat,
        BodyVelocity = BodyVelocity,
        BodyAngularVelocity = BodyAngularVelocity,
        Buoys = Buoys,
        CurrentSpeed = 0,
    }

    ActiveBoats[Model] = Data
    CollectionService:AddTag(Model, MOVING_SURFACE_TAG)

    if Seat then
        DisableVehicleSeatPhysics(Seat)
        Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
            SetNetworkOwnership(Data)
        end)
    end

    print("[BoatPhysicsServer] Initialized boat:", Model.Name, "with", #Buoys, "buoys")
end

local function RemoveBoat(Model: Model): ()
    local Data = ActiveBoats[Model]
    if Data then
        for _, BuoyEntry in Data.Buoys do
            if BuoyEntry.VectorForce then
                BuoyEntry.VectorForce:Destroy()
            end
            if BuoyEntry.Attachment then
                BuoyEntry.Attachment:Destroy()
            end
        end
    end
    ActiveBoats[Model] = nil
end

local function UpdateBuoyancyForces(Data: BoatData): ()
    local PrimaryPart = Data.PrimaryPart
    local Gravity = workspace.Gravity
    local VerticalVelocity = PrimaryPart.AssemblyLinearVelocity.Y

    for _, BuoyEntry in Data.Buoys do
        local BuoyPosition = BuoyEntry.Part.Position
        local WaveHeight = GetWaveHeight(BuoyPosition.X, BuoyPosition.Z) + HEIGHT_OFFSET

        local Depth = WaveHeight - BuoyPosition.Y

        local SubmergedVolume = CalculateSphereSubmergedVolume(BUOY_RADIUS, Depth)

        local BuoyancyForce = WATER_DENSITY * Gravity * SubmergedVolume

        local DampingForce = -DAMPING_COEFFICIENT * VerticalVelocity * PrimaryPart.AssemblyMass / #Data.Buoys

        local TotalForce = BuoyancyForce + DampingForce

        TotalForce = math.max(TotalForce, 0)

        BuoyEntry.VectorForce.Force = Vector3.new(0, TotalForce, 0)
    end
end

local function UpdateBoat(Data: BoatData, DeltaTime: number): ()
    local Throttle = 0
    local Steer = 0

    if Data.Seat then
        Throttle = Data.Seat.Throttle
        Steer = Data.Seat.Steer
    end

    local TurnVelocity = 0
    if Steer == 1 then
        TurnVelocity = -TURN_RATE
    elseif Steer == -1 then
        TurnVelocity = TURN_RATE
    end

    Data.BodyAngularVelocity.AngularVelocity = Vector3.new(0, TurnVelocity, 0)

    local TargetSpeed = 0
    if Throttle == 1 then
        TargetSpeed = MAX_FORWARD_SPEED
    elseif Throttle == -1 then
        TargetSpeed = -MAX_REVERSE_SPEED
    end

    if Throttle ~= 0 then
        Data.CurrentSpeed = MoveTowards(Data.CurrentSpeed, TargetSpeed, SPEED_INCREMENT * DeltaTime)
    else
        Data.CurrentSpeed = MoveTowards(Data.CurrentSpeed, 0, SPEED_DECREMENT * DeltaTime)
    end

    local Forward = GetHorizontalLookVector(Data.PrimaryPart)
    Data.BodyVelocity.Velocity = Forward * Data.CurrentSpeed

    UpdateBuoyancyForces(Data)
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