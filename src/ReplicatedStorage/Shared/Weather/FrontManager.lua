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
	Center: Vector3,
	RadiusX: number,
	RadiusZ: number,
	Rotation: number,
	Velocity: Vector3,
	Intensity: number,
	Age: number,
	Lifespan: number,
	NoiseSeed: number,
	Instance: Configuration?,
}

local ActiveFronts: { [string]: FrontData } = {}
local FrontsFolder: Folder? = nil

local WindDirection = Vector3.new(1, 0, 0.3).Unit
local WindSpeed = 12
local WindSeed = math.random(1, 10000)

local StartTime = 0
local LastSpawnTime = 0
local NextSpawnInterval = 0
local IsInitializing = false

local function GenerateId(): string
	return HttpService:GenerateGUID(false):sub(1, 8)
end

local function GetBounds(): (Vector3, Vector3)
	local Config = WeatherConfig.Fronts
	return Config.MapBoundsMin, Config.MapBoundsMax
end

local function GetActiveFrontCount(): number
	local Count = 0
	for _ in pairs(ActiveFronts) do
		Count = Count + 1
	end
	return Count
end

local function UpdateWind(TimeElapsed: number)
	local Config = WeatherConfig.Wind

	local NoiseX = math.noise(TimeElapsed * Config.NoiseTimeScale * 0.15, 0, WindSeed)
	local NoiseZ = math.noise(TimeElapsed * Config.NoiseTimeScale * 0.15, 100, WindSeed)

	local Variance = Config.DirectionVariance * 0.2
	local Direction = Vector3.new(
		Config.BaseDirection.X + NoiseX * Variance,
		0,
		Config.BaseDirection.Z + NoiseZ * Variance
	)

	if Direction.Magnitude > 0.001 then
		WindDirection = Direction.Unit
	end

	local SpeedNoise = math.noise(TimeElapsed * Config.NoiseTimeScale * 0.25, 200, WindSeed)
	WindSpeed = 10 + SpeedNoise * 6
	WindSpeed = math.clamp(WindSpeed, 6, 20)
end

local function GetEdgeSpawnPosition(): Vector3
	local BoundsMin, BoundsMax = GetBounds()
	local Config = WeatherConfig.Fronts
	local Buffer = Config.SpawnBuffer

	local MapWidth = BoundsMax.X - BoundsMin.X
	local MapDepth = BoundsMax.Z - BoundsMin.Z
	local MapCenterX = (BoundsMin.X + BoundsMax.X) / 2
	local MapCenterZ = (BoundsMin.Z + BoundsMax.Z) / 2

	local AbsX = math.abs(WindDirection.X)
	local AbsZ = math.abs(WindDirection.Z)

	local SpawnX: number
	local SpawnZ: number

	local EdgeVariance = 0.7

	if AbsX >= AbsZ then
		if WindDirection.X > 0 then
			SpawnX = BoundsMin.X - Buffer
		else
			SpawnX = BoundsMax.X + Buffer
		end
		SpawnZ = MapCenterZ + (math.random() - 0.5) * MapDepth * EdgeVariance
	else
		if WindDirection.Z > 0 then
			SpawnZ = BoundsMin.Z - Buffer
		else
			SpawnZ = BoundsMax.Z + Buffer
		end
		SpawnX = MapCenterX + (math.random() - 0.5) * MapWidth * EdgeVariance
	end

	return Vector3.new(SpawnX, 0, SpawnZ)
end

local function GetDistributedMapPosition(Index: number, TotalCount: number): Vector3
	local BoundsMin, BoundsMax = GetBounds()
	local MapWidth = BoundsMax.X - BoundsMin.X
	local MapDepth = BoundsMax.Z - BoundsMin.Z
	local MapCenterX = (BoundsMin.X + BoundsMax.X) / 2
	local MapCenterZ = (BoundsMin.Z + BoundsMax.Z) / 2

	local GoldenAngle = math.pi * (3 - math.sqrt(5))
	local Angle = Index * GoldenAngle
	local Radius = math.sqrt(Index / TotalCount) * 0.8

	local OffsetX = math.cos(Angle) * Radius * (MapWidth / 2)
	local OffsetZ = math.sin(Angle) * Radius * (MapDepth / 2)

	local JitterX = (math.random() - 0.5) * MapWidth * 0.15
	local JitterZ = (math.random() - 0.5) * MapDepth * 0.15

	return Vector3.new(
		MapCenterX + OffsetX + JitterX,
		0,
		MapCenterZ + OffsetZ + JitterZ
	)
end

local function CreateFrontInstance(Front: FrontData): Configuration
	local Config = Instance.new("Configuration")
	Config.Name = Front.Id

	Config:SetAttribute("Type", Front.Type)
	Config:SetAttribute("CenterX", Front.Center.X)
	Config:SetAttribute("CenterY", Front.Center.Y)
	Config:SetAttribute("CenterZ", Front.Center.Z)
	Config:SetAttribute("RadiusX", Front.RadiusX)
	Config:SetAttribute("RadiusZ", Front.RadiusZ)
	Config:SetAttribute("Rotation", Front.Rotation)
	Config:SetAttribute("VelocityX", Front.Velocity.X)
	Config:SetAttribute("VelocityY", Front.Velocity.Y)
	Config:SetAttribute("VelocityZ", Front.Velocity.Z)
	Config:SetAttribute("Intensity", Front.Intensity)
	Config:SetAttribute("Age", Front.Age)
	Config:SetAttribute("Lifespan", Front.Lifespan)
	Config:SetAttribute("NoiseSeed", Front.NoiseSeed)

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

	Config:SetAttribute("CenterX", Front.Center.X)
	Config:SetAttribute("CenterY", Front.Center.Y)
	Config:SetAttribute("CenterZ", Front.Center.Z)
	Config:SetAttribute("VelocityX", Front.Velocity.X)
	Config:SetAttribute("VelocityY", Front.Velocity.Y)
	Config:SetAttribute("VelocityZ", Front.Velocity.Z)
	Config:SetAttribute("Age", Front.Age)
end

local function IsFrontOutOfBounds(Front: FrontData): boolean
	local BoundsMin, BoundsMax = GetBounds()
	local Config = WeatherConfig.Fronts
	local Buffer = Config.DespawnBuffer

	local MaxRadius = math.max(Front.RadiusX, Front.RadiusZ)

	return Front.Center.X < BoundsMin.X - Buffer - MaxRadius
		or Front.Center.X > BoundsMax.X + Buffer + MaxRadius
		or Front.Center.Z < BoundsMin.Z - Buffer - MaxRadius
		or Front.Center.Z > BoundsMax.Z + Buffer + MaxRadius
end

local function CheckFrontOverlap(NewCenter: Vector3, NewRadiusX: number, NewRadiusZ: number): boolean
	local MinSeparation = 200

	for _, Existing in pairs(ActiveFronts) do
		local Distance = (NewCenter - Existing.Center).Magnitude
		local CombinedRadius = math.max(NewRadiusX, NewRadiusZ) + math.max(Existing.RadiusX, Existing.RadiusZ)

		if Distance < CombinedRadius * 0.4 + MinSeparation then
			return true
		end
	end

	return false
end

local function SpawnFront(SpawnPosition: Vector3, InitialAge: number?, ForcedType: string?): FrontData?
	local Config = WeatherConfig.Fronts

	if GetActiveFrontCount() >= Config.MaxActiveFronts then
		return nil
	end

	local FrontType = ForcedType or WeatherFronts.SelectRandomFrontType()
	local TypeConfig = WeatherFronts.Types[FrontType]
	if not TypeConfig then
		return nil
	end

	local RadiusX = TypeConfig.MinRadiusX + math.random() * (TypeConfig.MaxRadiusX - TypeConfig.MinRadiusX)
	local RadiusZ = TypeConfig.MinRadiusZ + math.random() * (TypeConfig.MaxRadiusZ - TypeConfig.MinRadiusZ)

	if not IsInitializing and CheckFrontOverlap(SpawnPosition, RadiusX, RadiusZ) then
		return nil
	end

	local Lifespan = TypeConfig.MinLifespan + math.random() * (TypeConfig.MaxLifespan - TypeConfig.MinLifespan)
	local Intensity = TypeConfig.MinIntensity + math.random() * (TypeConfig.MaxIntensity - TypeConfig.MinIntensity)

	local Speed = Config.BaseSpeed + WindSpeed * Config.WindSpeedInfluence
	local Velocity = WindDirection * Speed

	local Age = InitialAge or 0
	local Rotation = (math.random() - 0.5) * math.pi * 0.4

	local Front: FrontData = {
		Id = GenerateId(),
		Type = FrontType,
		Center = SpawnPosition,
		RadiusX = RadiusX,
		RadiusZ = RadiusZ,
		Rotation = Rotation,
		Velocity = Velocity,
		Intensity = Intensity,
		Age = Age,
		Lifespan = Lifespan,
		NoiseSeed = math.random(1, 100000),
		Instance = nil,
	}

	Front.Instance = CreateFrontInstance(Front)
	ActiveFronts[Front.Id] = Front

	return Front
end

local function SpawnEdgeFront(): FrontData?
	local SpawnPos = GetEdgeSpawnPosition()
	return SpawnFront(SpawnPos, 0)
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
	Front.Center = Front.Center + Movement

	if IsFrontOutOfBounds(Front) then
		return false
	end

	UpdateFrontInstance(Front)
	return true
end

local function CalculateNextSpawnInterval(): number
	local Config = WeatherConfig.Fronts
	return Config.SpawnIntervalMin + math.random() * (Config.SpawnIntervalMax - Config.SpawnIntervalMin)
end

local function MaintainFrontPopulation(TimeElapsed: number)
	local Config = WeatherConfig.Fronts

	if not Config.Enabled then
		return
	end

	local CurrentCount = GetActiveFrontCount()

	if CurrentCount < Config.MinActiveFronts then
		SpawnEdgeFront()
		LastSpawnTime = TimeElapsed
		NextSpawnInterval = CalculateNextSpawnInterval()
		return
	end

	if CurrentCount >= Config.MaxActiveFronts then
		return
	end

	if TimeElapsed - LastSpawnTime >= NextSpawnInterval then
		local SpawnChance = 0.6 + (Config.MaxActiveFronts - CurrentCount) * 0.1
		if math.random() < SpawnChance then
			SpawnEdgeFront()
		end
		LastSpawnTime = TimeElapsed
		NextSpawnInterval = CalculateNextSpawnInterval()
	end
end

function FrontManager.Initialize()
	FrontsFolder = Instance.new("Folder")
	FrontsFolder.Name = "WeatherFronts"
	FrontsFolder.Parent = ReplicatedStorage

	StartTime = os.clock()
	UpdateWind(0)

	local Config = WeatherConfig.Fronts
	local InitialCount = Config.InitialFrontCount

	local TypeWeights: { { Type: string, Weight: number } } = {}
	for TypeName, TypeConfig in pairs(WeatherFronts.Types) do
		table.insert(TypeWeights, { Type = TypeName, Weight = TypeConfig.SpawnWeight })
	end

	IsInitializing = true

	for Index = 1, InitialCount do
		local SpawnPos = GetDistributedMapPosition(Index, InitialCount)

		local SelectedType: string? = nil
		local TotalWeight = 0
		for _, Entry in ipairs(TypeWeights) do
			TotalWeight = TotalWeight + Entry.Weight
		end
		local Roll = math.random() * TotalWeight
		local Accumulated = 0
		for _, Entry in ipairs(TypeWeights) do
			Accumulated = Accumulated + Entry.Weight
			if Roll <= Accumulated then
				SelectedType = Entry.Type
				break
			end
		end

		local TypeConfig = WeatherFronts.Types[SelectedType or "Rain"]
		local MaxAge = TypeConfig and TypeConfig.MinLifespan * 0.6 or 200
		local InitialAge = math.random() * MaxAge

		SpawnFront(SpawnPos, InitialAge, SelectedType)
	end

	IsInitializing = false

	LastSpawnTime = 0
	NextSpawnInterval = CalculateNextSpawnInterval()
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

	MaintainFrontPopulation(TimeElapsed)
end

function FrontManager.GetActiveFronts(): { [string]: FrontData }
	return ActiveFronts
end

function FrontManager.GetFrontAtPosition(Position: Vector3): FrontData?
	local StrongestFront: FrontData? = nil
	local HighestDepth = 0

	for _, Front in pairs(ActiveFronts) do
		local Depth = WeatherFronts.GetNormalizedDepth(
			Position,
			Front.Center,
			Front.RadiusX,
			Front.RadiusZ,
			Front.Rotation
		)

		if Depth > 0 then
			local EffectiveDepth = Depth * Front.Intensity

			if EffectiveDepth > HighestDepth then
				HighestDepth = EffectiveDepth
				StrongestFront = Front
			end
		end
	end

	return StrongestFront
end

function FrontManager.GetFrontsAffectingPosition(Position: Vector3): { { Front: FrontData, Depth: number } }
	local AffectingFronts: { { Front: FrontData, Depth: number } } = {}

	for _, Front in pairs(ActiveFronts) do
		local Depth = WeatherFronts.GetNormalizedDepth(
			Position,
			Front.Center,
			Front.RadiusX,
			Front.RadiusZ,
			Front.Rotation
		)

		if Depth > 0 then
			table.insert(AffectingFronts, { Front = Front, Depth = Depth })
		end
	end

	table.sort(AffectingFronts, function(EntryA, EntryB)
		return EntryA.Depth > EntryB.Depth
	end)

	return AffectingFronts
end

function FrontManager.GetWindDirection(): Vector3
	return WindDirection
end

function FrontManager.GetWindSpeed(): number
	return WindSpeed
end

return FrontManager