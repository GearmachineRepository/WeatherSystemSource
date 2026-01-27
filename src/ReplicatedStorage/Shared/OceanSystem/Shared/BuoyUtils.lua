--!strict

local OceanConfig = require(script.Parent.OceanConfig)

export type BuoyPoints = {
	Bow: BasePart?,
	Stern: BasePart?,
	Port: BasePart?,
	Starboard: BasePart?,
	All: {BasePart},
}

export type HeightFunction = (PositionX: number, PositionZ: number) -> number

local BuoyUtils = {}

function BuoyUtils.FindBuoys(Model: Model): BuoyPoints
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

function BuoyUtils.CreateDefaultBuoys(Model: Model): BuoyPoints
	local PrimaryPart = Model.PrimaryPart
	if not PrimaryPart then
		warn("[BuoyUtils] No PrimaryPart set on model")
		return BuoyUtils.FindBuoys(Model)
	end

	local ExistingFolder = Model:FindFirstChild("Buoys")
	if ExistingFolder then
		return BuoyUtils.FindBuoys(Model)
	end

	local Size = PrimaryPart.Size
	local HalfX = Size.X / 2 * 0.8
	local HalfZ = Size.Z / 2 * 0.8

	local BuoysFolder = Instance.new("Folder")
	BuoysFolder.Name = "Buoys"
	BuoysFolder.Parent = Model

	local function CreateBuoy(Name: string, Offset: Vector3): BasePart
		local Buoy = Instance.new("Part")
		Buoy.Name = Name
		Buoy.Size = Vector3.new(1, 1, 1)
		Buoy.Transparency = 1
		Buoy.CanCollide = false
		Buoy.Anchored = false
		Buoy.Massless = true
		Buoy.CFrame = PrimaryPart.CFrame * CFrame.new(Offset)
		Buoy.Parent = BuoysFolder

		local Weld = Instance.new("WeldConstraint")
		Weld.Part0 = PrimaryPart
		Weld.Part1 = Buoy
		Weld.Parent = Buoy

		return Buoy
	end

	CreateBuoy("Bow", Vector3.new(0, 0, -HalfZ))
	CreateBuoy("Stern", Vector3.new(0, 0, HalfZ))
	CreateBuoy("Port", Vector3.new(-HalfX, 0, 0))
	CreateBuoy("Starboard", Vector3.new(HalfX, 0, 0))

	return BuoyUtils.FindBuoys(Model)
end

function BuoyUtils.CalculateAverageHeight(Buoys: BuoyPoints, GetHeight: HeightFunction): number
	if #Buoys.All == 0 then
		return OceanConfig.BASE_WATER_HEIGHT
	end

	local TotalHeight = 0
	for _, Buoy in Buoys.All do
		local Position = Buoy.Position
		TotalHeight = TotalHeight + GetHeight(Position.X, Position.Z)
	end

	return TotalHeight / #Buoys.All
end

function BuoyUtils.CalculatePitch(Buoys: BuoyPoints, GetHeight: HeightFunction): number
	if not Buoys.Bow or not Buoys.Stern then
		return 0
	end

	local BowPosition = Buoys.Bow.Position
	local SternPosition = Buoys.Stern.Position

	local BowHeight = GetHeight(BowPosition.X, BowPosition.Z)
	local SternHeight = GetHeight(SternPosition.X, SternPosition.Z)

	local Distance = (Vector2.new(BowPosition.X, BowPosition.Z) - Vector2.new(SternPosition.X, SternPosition.Z)).Magnitude

	if Distance < 0.01 then
		return 0
	end

	local HeightDifference = BowHeight - SternHeight
	return math.atan2(HeightDifference, Distance)
end

function BuoyUtils.CalculateRoll(Buoys: BuoyPoints, GetHeight: HeightFunction): number
	if not Buoys.Port or not Buoys.Starboard then
		return 0
	end

	local PortPosition = Buoys.Port.Position
	local StarboardPosition = Buoys.Starboard.Position

	local PortHeight = GetHeight(PortPosition.X, PortPosition.Z)
	local StarboardHeight = GetHeight(StarboardPosition.X, StarboardPosition.Z)

	local Distance = (Vector2.new(PortPosition.X, PortPosition.Z) - Vector2.new(StarboardPosition.X, StarboardPosition.Z)).Magnitude

	if Distance < 0.01 then
		return 0
	end

	local HeightDifference = StarboardHeight - PortHeight
	return math.atan2(HeightDifference, Distance)
end

function BuoyUtils.ValidateBuoys(Buoys: BuoyPoints): boolean
	return Buoys.Bow ~= nil
		and Buoys.Stern ~= nil
		and Buoys.Port ~= nil
		and Buoys.Starboard ~= nil
end

return BuoyUtils