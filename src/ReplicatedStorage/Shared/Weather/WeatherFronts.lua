--!strict

local WeatherFronts = {}

export type FrontTypeConfig = {
	SpawnWeight: number,
	MinWidth: number,
	MaxWidth: number,
	MinLifespan: number,
	MaxLifespan: number,
	MinIntensity: number,
	MaxIntensity: number,
	BaseCloudHeight: number,
	CloudHeightVariance: number,
	BaseCloudScale: Vector3,
	CloudScaleVariance: number,
	CloudCount: number,
	CoreColor: Color3,
	EdgeColor: Color3,
	ColorVariance: number,
	HasLightning: boolean,
	LightningThreshold: number?,
	WeatherWeak: string,
	WeatherMedium: string,
	WeatherStrong: string,
	BiomeOverrides: { [string]: { Weak: string, Medium: string, Strong: string } }?,
}

export type FrontData = {
	Id: string,
	Type: string,
	PointA: Vector3,
	PointB: Vector3,
	Width: number,
	Velocity: Vector3,
	Intensity: number,
	Age: number,
	Lifespan: number,
}

WeatherFronts.Types = {
	Storm = {
		SpawnWeight = 20,
		MinWidth = 600,
		MaxWidth = 1000,
		MinLifespan = 600,
		MaxLifespan = 1100,
		MinIntensity = 0.55,
		MaxIntensity = 1.0,
		BaseCloudHeight = 400,
		CloudHeightVariance = 100,
		BaseCloudScale = Vector3.new(350, 200, 320),
		CloudScaleVariance = 0.3,
		CloudCount = 18,
		CoreColor = Color3.fromRGB(75, 75, 85),
		EdgeColor = Color3.fromRGB(160, 160, 170),
		ColorVariance = 0.06,
		HasLightning = true,
		LightningThreshold = 0.6,
		WeatherWeak = "Overcast",
		WeatherMedium = "Rain",
		WeatherStrong = "Thunderstorm",
		BiomeOverrides = {
			Desert = { Weak = "Cloudy", Medium = "Overcast", Strong = "Rain" },
			Arctic = { Weak = "Overcast", Medium = "Snow", Strong = "Snow" },
			Tropical = { Weak = "Rain", Medium = "Thunderstorm", Strong = "Thunderstorm" },
			Mountain = { Weak = "Overcast", Medium = "Snow", Strong = "Thunderstorm" },
		},
	} :: FrontTypeConfig,

	Rain = {
		SpawnWeight = 35,
		MinWidth = 450,
		MaxWidth = 750,
		MinLifespan = 450,
		MaxLifespan = 800,
		MinIntensity = 0.35,
		MaxIntensity = 0.85,
		BaseCloudHeight = 350,
		CloudHeightVariance = 80,
		BaseCloudScale = Vector3.new(280, 120, 260),
		CloudScaleVariance = 0.28,
		CloudCount = 14,
		CoreColor = Color3.fromRGB(130, 130, 140),
		EdgeColor = Color3.fromRGB(190, 190, 200),
		ColorVariance = 0.05,
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Drizzle",
		WeatherStrong = "Rain",
		BiomeOverrides = {
			Desert = { Weak = "Cloudy", Medium = "Cloudy", Strong = "Drizzle" },
			Arctic = { Weak = "Cloudy", Medium = "Snow", Strong = "Snow" },
		},
	} :: FrontTypeConfig,

	Snow = {
		SpawnWeight = 15,
		MinWidth = 500,
		MaxWidth = 800,
		MinLifespan = 550,
		MaxLifespan = 900,
		MinIntensity = 0.4,
		MaxIntensity = 0.9,
		BaseCloudHeight = 380,
		CloudHeightVariance = 70,
		BaseCloudScale = Vector3.new(260, 100, 240),
		CloudScaleVariance = 0.25,
		CloudCount = 12,
		CoreColor = Color3.fromRGB(200, 200, 210),
		EdgeColor = Color3.fromRGB(235, 235, 245),
		ColorVariance = 0.04,
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Overcast",
		WeatherStrong = "Snow",
		BiomeOverrides = {
			Desert = { Weak = "Clear", Medium = "Cloudy", Strong = "Cloudy" },
			Tropical = { Weak = "Cloudy", Medium = "Rain", Strong = "Rain" },
		},
	} :: FrontTypeConfig,

	Fog = {
		SpawnWeight = 12,
		MinWidth = 400,
		MaxWidth = 600,
		MinLifespan = 350,
		MaxLifespan = 600,
		MinIntensity = 0.5,
		MaxIntensity = 0.9,
		BaseCloudHeight = 150,
		CloudHeightVariance = 40,
		BaseCloudScale = Vector3.new(320, 50, 300),
		CloudScaleVariance = 0.22,
		CloudCount = 10,
		CoreColor = Color3.fromRGB(210, 210, 215),
		EdgeColor = Color3.fromRGB(230, 230, 235),
		ColorVariance = 0.03,
		HasLightning = false,
		WeatherWeak = "Fog",
		WeatherMedium = "Fog",
		WeatherStrong = "Fog",
		BiomeOverrides = {
			Desert = { Weak = "Clear", Medium = "Cloudy", Strong = "Cloudy" },
		},
	} :: FrontTypeConfig,

	Fair = {
		SpawnWeight = 40,
		MinWidth = 350,
		MaxWidth = 600,
		MinLifespan = 400,
		MaxLifespan = 700,
		MinIntensity = 0.2,
		MaxIntensity = 0.5,
		BaseCloudHeight = 500,
		CloudHeightVariance = 100,
		BaseCloudScale = Vector3.new(180, 80, 160),
		CloudScaleVariance = 0.35,
		CloudCount = 8,
		CoreColor = Color3.fromRGB(245, 245, 250),
		EdgeColor = Color3.fromRGB(255, 255, 255),
		ColorVariance = 0.02,
		HasLightning = false,
		WeatherWeak = "Clear",
		WeatherMedium = "Cloudy",
		WeatherStrong = "Cloudy",
	} :: FrontTypeConfig,
}

WeatherFronts.CalmWeather = {
	Temperate = { Clear = 55, Cloudy = 30, Fog = 15 },
	Desert = { Clear = 85, Cloudy = 15 },
	Arctic = { Clear = 40, Cloudy = 40, Fog = 20 },
	Tropical = { Clear = 30, Cloudy = 50, Drizzle = 20 },
	Swamp = { Cloudy = 35, Fog = 45, Drizzle = 20 },
	Mountain = { Clear = 45, Cloudy = 35, Fog = 20 },
}

function WeatherFronts.LerpColor3(ColorA: Color3, ColorB: Color3, Alpha: number): Color3
	return Color3.new(
		ColorA.R + (ColorB.R - ColorA.R) * Alpha,
		ColorA.G + (ColorB.G - ColorA.G) * Alpha,
		ColorA.B + (ColorB.B - ColorA.B) * Alpha
	)
end

function WeatherFronts.GetWeatherForFront(FrontType: string, Intensity: number, Biome: string): string
	local TypeConfig = WeatherFronts.Types[FrontType]
	if not TypeConfig then
		return "Clear"
	end

	local WeatherTable = {
		Weak = TypeConfig.WeatherWeak,
		Medium = TypeConfig.WeatherMedium,
		Strong = TypeConfig.WeatherStrong,
	}

	if TypeConfig.BiomeOverrides and TypeConfig.BiomeOverrides[Biome] then
		WeatherTable = TypeConfig.BiomeOverrides[Biome]
	end

	if Intensity < 0.4 then
		return WeatherTable.Weak
	elseif Intensity < 0.7 then
		return WeatherTable.Medium
	else
		return WeatherTable.Strong
	end
end

function WeatherFronts.GetCalmWeather(Biome: string): string
	local BiomeCalm = WeatherFronts.CalmWeather[Biome]
	if not BiomeCalm then
		BiomeCalm = WeatherFronts.CalmWeather.Temperate
	end

	local TotalWeight = 0
	for _, Weight in pairs(BiomeCalm) do
		TotalWeight = TotalWeight + Weight
	end

	local Roll = math.random() * TotalWeight
	local Accumulated = 0

	for State, Weight in pairs(BiomeCalm) do
		Accumulated = Accumulated + Weight
		if Roll <= Accumulated then
			return State
		end
	end

	return "Clear"
end

function WeatherFronts.SelectRandomFrontType(): string
	local TotalWeight = 0
	for _, Config in pairs(WeatherFronts.Types) do
		TotalWeight = TotalWeight + Config.SpawnWeight
	end

	local Roll = math.random() * TotalWeight
	local Accumulated = 0

	for TypeName, Config in pairs(WeatherFronts.Types) do
		Accumulated = Accumulated + Config.SpawnWeight
		if Roll <= Accumulated then
			return TypeName
		end
	end

	return "Fair"
end

function WeatherFronts.GetDistanceToFront(Position: Vector3, PointA: Vector3, PointB: Vector3): number
	local LineVec = PointB - PointA
	local PointVec = Position - PointA

	local LineLength = LineVec.Magnitude
	if LineLength < 0.001 then
		return (Position - PointA).Magnitude
	end

	local LineDir = LineVec / LineLength
	local Projection = PointVec:Dot(LineDir)
	Projection = math.clamp(Projection, 0, LineLength)

	local ClosestPoint = PointA + LineDir * Projection
	return Vector3.new(Position.X - ClosestPoint.X, 0, Position.Z - ClosestPoint.Z).Magnitude
end

function WeatherFronts.IsInsideFront(Position: Vector3, PointA: Vector3, PointB: Vector3, Width: number): boolean
	return WeatherFronts.GetDistanceToFront(Position, PointA, PointB) <= Width / 2
end

return WeatherFronts