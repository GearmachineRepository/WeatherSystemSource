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
	CloudFolder: string,
	CloudHeight: number,
	CloudHeightVariance: number,
	CloudScale: Vector3,
	CloudScaleVariance: number,
	LeadingColor: Color3,
	CoreColor: Color3,
	TrailingColor: Color3,
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
		MinWidth = 400,
		MaxWidth = 700,
		MinLifespan = 500,
		MaxLifespan = 900,
		MinIntensity = 0.5,
		MaxIntensity = 1.0,
		CloudFolder = "Storm",
		CloudHeight = 520,
		CloudHeightVariance = 80,
		CloudScale = Vector3.new(500, 220, 450),
		CloudScaleVariance = 0.25,
		LeadingColor = Color3.fromRGB(160, 160, 170),
		CoreColor = Color3.fromRGB(55, 55, 70),
		TrailingColor = Color3.fromRGB(120, 120, 135),
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
	},

	Rain = {
		SpawnWeight = 35,
		MinWidth = 300,
		MaxWidth = 550,
		MinLifespan = 400,
		MaxLifespan = 700,
		MinIntensity = 0.3,
		MaxIntensity = 0.85,
		CloudFolder = "Rain",
		CloudHeight = 380,
		CloudHeightVariance = 60,
		CloudScale = Vector3.new(160, 60, 140),
		CloudScaleVariance = 0.35,
		LeadingColor = Color3.fromRGB(180, 180, 190),
		CoreColor = Color3.fromRGB(110, 110, 125),
		TrailingColor = Color3.fromRGB(150, 150, 165),
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Drizzle",
		WeatherStrong = "Rain",
		BiomeOverrides = {
			Desert = { Weak = "Cloudy", Medium = "Cloudy", Strong = "Drizzle" },
			Arctic = { Weak = "Cloudy", Medium = "Snow", Strong = "Snow" },
		},
	},

	Snow = {
		SpawnWeight = 15,
		MinWidth = 350,
		MaxWidth = 600,
		MinLifespan = 500,
		MaxLifespan = 800,
		MinIntensity = 0.4,
		MaxIntensity = 0.9,
		CloudFolder = "Light",
		CloudHeight = 400,
		CloudHeightVariance = 70,
		CloudScale = Vector3.new(180, 55, 160),
		CloudScaleVariance = 0.3,
		LeadingColor = Color3.fromRGB(220, 225, 235),
		CoreColor = Color3.fromRGB(190, 195, 210),
		TrailingColor = Color3.fromRGB(205, 210, 220),
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Overcast",
		WeatherStrong = "Snow",
		BiomeOverrides = {
			Desert = { Weak = "Clear", Medium = "Cloudy", Strong = "Cloudy" },
			Tropical = { Weak = "Cloudy", Medium = "Rain", Strong = "Rain" },
		},
	},

	Fog = {
		SpawnWeight = 12,
		MinWidth = 250,
		MaxWidth = 400,
		MinLifespan = 300,
		MaxLifespan = 500,
		MinIntensity = 0.5,
		MaxIntensity = 0.9,
		CloudFolder = "Light",
		CloudHeight = 180,
		CloudHeightVariance = 50,
		CloudScale = Vector3.new(220, 35, 200),
		CloudScaleVariance = 0.3,
		LeadingColor = Color3.fromRGB(210, 210, 215),
		CoreColor = Color3.fromRGB(195, 195, 200),
		TrailingColor = Color3.fromRGB(200, 200, 205),
		HasLightning = false,
		WeatherWeak = "Fog",
		WeatherMedium = "Fog",
		WeatherStrong = "Fog",
		BiomeOverrides = {
			Desert = { Weak = "Clear", Medium = "Cloudy", Strong = "Cloudy" },
		},
	},

	Fair = {
		SpawnWeight = 40,
		MinWidth = 200,
		MaxWidth = 400,
		MinLifespan = 350,
		MaxLifespan = 600,
		MinIntensity = 0.2,
		MaxIntensity = 0.5,
		CloudFolder = "Light",
		CloudHeight = 500,
		CloudHeightVariance = 100,
		CloudScale = Vector3.new(150, 45, 130),
		CloudScaleVariance = 0.4,
		LeadingColor = Color3.fromRGB(250, 250, 255),
		CoreColor = Color3.fromRGB(240, 240, 248),
		TrailingColor = Color3.fromRGB(245, 245, 252),
		HasLightning = false,
		WeatherWeak = "Clear",
		WeatherMedium = "Cloudy",
		WeatherStrong = "Cloudy",
	},
}

WeatherFronts.CalmWeather = {
	Temperate = { Clear = 55, Cloudy = 30, Fog = 15 },
	Desert = { Clear = 85, Cloudy = 15 },
	Arctic = { Clear = 40, Cloudy = 40, Fog = 20 },
	Tropical = { Clear = 30, Cloudy = 50, Drizzle = 20 },
	Swamp = { Cloudy = 35, Fog = 45, Drizzle = 20 },
	Mountain = { Clear = 45, Cloudy = 35, Fog = 20 },
}

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