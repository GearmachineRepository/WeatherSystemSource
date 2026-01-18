--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = Shared:WaitForChild("Weather")
local WeatherConfig = require(Weather:WaitForChild("WeatherConfig"))
local WeatherFronts = require(Weather:WaitForChild("WeatherFronts"))

local FrontManager = {}

type FrontData = {
	Id: string,
	Type: string,
	PointA: Vector3,
	PointB: Vector3,
	Width: number,
	Velocity: Vector3,
	Intensity: number,
	Age: number,
	Lifespan: number,
	Instance: Configuration?,
}

local ActiveFronts: { [string]: FrontData } = {}
local FrontsFolder: Folder? = nil

local WindDirection = Vector3.new(1, 0, 0.3).Unit
local WindSpeed = 12
local WindSeed = math.random(1, 10000)

local LastSpawnTime = 0
local NextSpawnInterval = 0
local StartTime = 0

local function GenerateId(): string
	return HttpService:GenerateGUID(false):sub(1, 8)
end

local function GetBounds(): (Vector3, Vector3)
	local Config = WeatherConfig.Fronts
	return Config.MapBoundsMin, Config.MapBoundsMax
end

local function UpdateWind(TimeElapsed: number)
	local Config = WeatherConfig.Wind

	local NoiseX = math.noise(TimeElapsed * Config.NoiseTimeScale * 0.25, 0, WindSeed)
	local NoiseZ = math.noise(TimeElapsed * Config.NoiseTimeScale * 0.25, 100, WindSeed)

	local Variance = Config.DirectionVariance * 0.3
	local Direction = Vector3.new(
		Config.BaseDirection.X + NoiseX * Variance,
		0,
		Config.BaseDirection.Z + NoiseZ * Variance
	)

	if Direction.Magnitude > 0.001 then
		WindDirection = Direction.Unit
	end

	local SpeedNoise = math.noise(TimeElapsed * Config.NoiseTimeScale * 0.4, 200, WindSeed)
	WindSpeed = 10 + SpeedNoise * 6
	WindSpeed = math.clamp(WindSpeed, 6, 20)
end

local function GetFrontPerpendicular(): Vector3
	local AbsX = math.abs(WindDirection.X)
	local AbsZ = math.abs(WindDirection.Z)

	if AbsX >= AbsZ then
		return Vector3.new(0, 0, 1)
	else
		return Vector3.new(1, 0, 0)
	end
end

local function GetFrontLength(): number
	local BoundsMin, BoundsMax = GetBounds()
	local AbsX = math.abs(WindDirection.X)
	local AbsZ = math.abs(WindDirection.Z)

	if AbsX >= AbsZ then
		return (BoundsMax.Z - BoundsMin.Z) * (1.1 + math.random() * 0.3)
	else
		return (BoundsMax.X - BoundsMin.X) * (1.1 + math.random() * 0.3)
	end
end

local function CreateFrontPoints(CenterX: number, CenterZ: number): (Vector3, Vector3)
	local Perpendicular = GetFrontPerpendicular()
	local FrontLength = GetFrontLength()

	local AngleVariance = (math.random() - 0.5) * 0.25
	local RotatedPerp = Vector3.new(
		Perpendicular.X * math.cos(AngleVariance) - Perpendicular.Z * math.sin(AngleVariance),
		0,
		Perpendicular.X * math.sin(AngleVariance) + Perpendicular.Z * math.cos(AngleVariance)
	)

	local Center = Vector3.new(CenterX, 0, CenterZ)
	local PointA = Center - RotatedPerp * (FrontLength / 2)
	local PointB = Center + RotatedPerp * (FrontLength / 2)

	return PointA, PointB
end

local function GetEdgeSpawnPosition(): (number, number)
	local BoundsMin, BoundsMax = GetBounds()
	local Config = WeatherConfig.Fronts
	local Buffer = Config.DespawnBuffer

	local MapCenterX = (BoundsMin.X + BoundsMax.X) / 2
	local MapCenterZ = (BoundsMin.Z + BoundsMax.Z) / 2
	local MapWidth = BoundsMax.X - BoundsMin.X
	local MapDepth = BoundsMax.Z - BoundsMin.Z

	local AbsX = math.abs(WindDirection.X)
	local AbsZ = math.abs(WindDirection.Z)

	local SpawnX: number
	local SpawnZ: number

	if AbsX >= AbsZ then
		if WindDirection.X > 0 then
			SpawnX = BoundsMin.X - Buffer
		else
			SpawnX = BoundsMax.X + Buffer
		end
		SpawnZ = MapCenterZ + (math.random() - 0.5) * MapDepth * 0.5
	else
		if WindDirection.Z > 0 then
			SpawnZ = BoundsMin.Z - Buffer
		else
			SpawnZ = BoundsMax.Z + Buffer
		end
		SpawnX = MapCenterX + (math.random() - 0.5) * MapWidth * 0.5
	end

	return SpawnX, SpawnZ
end

local function GetRandomMapPosition(): (number, number)
	local BoundsMin, BoundsMax = GetBounds()

	local SpawnX = BoundsMin.X + math.random() * (BoundsMax.X - BoundsMin.X)
	local SpawnZ = BoundsMin.Z + math.random() * (BoundsMax.Z - BoundsMin.Z)

	return SpawnX, SpawnZ
end

local function CreateFrontInstance(Front: FrontData): Configuration
	local Config = Instance.new("Configuration")
	Config.Name = Front.Id

	Config:SetAttribute("Type", Front.Type)
	Config:SetAttribute("PointAX", Front.PointA.X)
	Config:SetAttribute("PointAY", Front.PointA.Y)
	Config:SetAttribute("PointAZ", Front.PointA.Z)
	Config:SetAttribute("PointBX", Front.PointB.X)
	Config:SetAttribute("PointBY", Front.PointB.Y)
	Config:SetAttribute("PointBZ", Front.PointB.Z)
	Config:SetAttribute("Width", Front.Width)
	Config:SetAttribute("VelocityX", Front.Velocity.X)
	Config:SetAttribute("VelocityY", Front.Velocity.Y)
	Config:SetAttribute("VelocityZ", Front.Velocity.Z)
	Config:SetAttribute("Intensity", Front.Intensity)
	Config:SetAttribute("Age", Front.Age)
	Config:SetAttribute("Lifespan", Front.Lifespan)

	if FrontsFolder then
		Config.Parent = FrontsFolder
	end

	return Config
end

local function UpdateFrontInstance(Front: FrontData)
	local Config = Front.Instance
	if not Config then
		return
	end

	Config:SetAttribute("PointAX", Front.PointA.X)
	Config:SetAttribute("PointAY", Front.PointA.Y)
	Config:SetAttribute("PointAZ", Front.PointA.Z)
	Config:SetAttribute("PointBX", Front.PointB.X)
	Config:SetAttribute("PointBY", Front.PointB.Y)
	Config:SetAttribute("PointBZ", Front.PointB.Z)
	Config:SetAttribute("VelocityX", Front.Velocity.X)
	Config:SetAttribute("VelocityY", Front.Velocity.Y)
	Config:SetAttribute("VelocityZ", Front.Velocity.Z)
	Config:SetAttribute("Age", Front.Age)
end

local function IsFrontOutOfBounds(Front: FrontData): boolean
	local BoundsMin, BoundsMax = GetBounds()
	local Config = WeatherConfig.Fronts
	local Buffer = Config.DespawnBuffer * 1.5

	local CenterX = (Front.PointA.X + Front.PointB.X) / 2
	local CenterZ = (Front.PointA.Z + Front.PointB.Z) / 2

	return CenterX < BoundsMin.X - Buffer
		or CenterX > BoundsMax.X + Buffer
		or CenterZ < BoundsMin.Z - Buffer
		or CenterZ > BoundsMax.Z + Buffer
end

local function SpawnFront(SpawnX: number, SpawnZ: number, InitialAge: number?): FrontData?
	local Config = WeatherConfig.Fronts

	local ActiveCount = 0
	for _ in pairs(ActiveFronts) do
		ActiveCount = ActiveCount + 1
	end

	if ActiveCount >= Config.MaxActiveFronts then
		return nil
	end

	local FrontType = WeatherFronts.SelectRandomFrontType()
	local TypeConfig = WeatherFronts.Types[FrontType]
	if not TypeConfig then
		return nil
	end

	local PointA, PointB = CreateFrontPoints(SpawnX, SpawnZ)

	local Width = TypeConfig.MinWidth + math.random() * (TypeConfig.MaxWidth - TypeConfig.MinWidth)
	local Lifespan = TypeConfig.MinLifespan + math.random() * (TypeConfig.MaxLifespan - TypeConfig.MinLifespan)
	local Intensity = TypeConfig.MinIntensity + math.random() * (TypeConfig.MaxIntensity - TypeConfig.MinIntensity)

	local Speed = Config.BaseSpeed + WindSpeed * Config.WindSpeedInfluence
	local Velocity = WindDirection * Speed

	local Age = InitialAge or 0

	local Front: FrontData = {
		Id = GenerateId(),
		Type = FrontType,
		PointA = PointA,
		PointB = PointB,
		Width = Width,
		Velocity = Velocity,
		Intensity = Intensity,
		Age = Age,
		Lifespan = Lifespan,
		Instance = nil,
	}

	Front.Instance = CreateFrontInstance(Front)
	ActiveFronts[Front.Id] = Front

	return Front
end

local function SpawnEdgeFront(): FrontData?
	local SpawnX, SpawnZ = GetEdgeSpawnPosition()
	return SpawnFront(SpawnX, SpawnZ, 0)
end

local function SpawnInitialFront(): FrontData?
	local SpawnX, SpawnZ = GetRandomMapPosition()
	local TypeConfig = WeatherFronts.Types[WeatherFronts.SelectRandomFrontType()]
	local MaxAge = TypeConfig and TypeConfig.MinLifespan * 0.3 or 100
	local InitialAge = math.random() * MaxAge
	return SpawnFront(SpawnX, SpawnZ, InitialAge)
end

local function DestroyFront(FrontId: string)
	local Front = ActiveFronts[FrontId]
	if not Front then
		return
	end

	if Front.Instance then
		Front.Instance:Destroy()
	end

	ActiveFronts[FrontId] = nil
end

local function UpdateFront(Front: FrontData, DeltaTime: number): boolean
	Front.Age = Front.Age + DeltaTime

	if Front.Age >= Front.Lifespan then
		return false
	end

	local Config = WeatherConfig.Fronts
	local Speed = Config.BaseSpeed + WindSpeed * Config.WindSpeedInfluence
	Front.Velocity = WindDirection * Speed

	local Movement = Front.Velocity * DeltaTime
	Front.PointA = Front.PointA + Movement
	Front.PointB = Front.PointB + Movement

	if IsFrontOutOfBounds(Front) then
		return false
	end

	UpdateFrontInstance(Front)
	return true
end

function FrontManager.Initialize()
	FrontsFolder = Instance.new("Folder")
	FrontsFolder.Name = "WeatherFronts"
	FrontsFolder.Parent = ReplicatedStorage

	StartTime = os.clock()
	UpdateWind(0)

	local Config = WeatherConfig.Fronts
	local InitialCount = math.random(2, math.min(4, Config.MaxActiveFronts))

	for Index = 1, InitialCount do
		SpawnInitialFront()
	end

	local SpawnRange = Config.SpawnIntervalMax - Config.SpawnIntervalMin
	NextSpawnInterval = Config.SpawnIntervalMin + math.random() * SpawnRange * 0.5
	LastSpawnTime = os.clock()
end

function FrontManager.Update(DeltaTime: number)
	local CurrentTime = os.clock()
	local TimeElapsed = CurrentTime - StartTime

	UpdateWind(TimeElapsed)

	local ToRemove: { string } = {}

	for FrontId, Front in pairs(ActiveFronts) do
		local ShouldKeep = UpdateFront(Front, DeltaTime)
		if not ShouldKeep then
			table.insert(ToRemove, FrontId)
		end
	end

	for _, FrontId in ipairs(ToRemove) do
		DestroyFront(FrontId)
	end

	local Config = WeatherConfig.Fronts
	if Config.Enabled and CurrentTime - LastSpawnTime >= NextSpawnInterval then
		SpawnEdgeFront()
		LastSpawnTime = CurrentTime
		NextSpawnInterval = Config.SpawnIntervalMin + math.random() * (Config.SpawnIntervalMax - Config.SpawnIntervalMin)
	end
end

function FrontManager.GetActiveFronts(): { [string]: FrontData }
	return ActiveFronts
end

function FrontManager.GetFrontAtPosition(Position: Vector3): FrontData?
	local StrongestFront: FrontData? = nil
	local StrongestIntensity = 0

	for _, Front in pairs(ActiveFronts) do
		if WeatherFronts.IsInsideFront(Position, Front.PointA, Front.PointB, Front.Width) then
			local Distance = WeatherFronts.GetDistanceToFront(Position, Front.PointA, Front.PointB)
			local NormalizedDist = Distance / (Front.Width / 2)
			local EffectiveIntensity = Front.Intensity * (1 - NormalizedDist * 0.25)

			if EffectiveIntensity > StrongestIntensity then
				StrongestIntensity = EffectiveIntensity
				StrongestFront = Front
			end
		end
	end

	return StrongestFront
end

function FrontManager.GetWindDirection(): Vector3
	return WindDirection
end

function FrontManager.GetWindSpeed(): number
	return WindSpeed
end

return FrontManager