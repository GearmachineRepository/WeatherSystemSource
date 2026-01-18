--!strict

local WeatherFronts = {}

export type CloudFormation = {
	MinClouds: number,
	MaxClouds: number,
	CoreDensity: number,
	EdgeDensity: number,
	NoiseScale: number,
	NoiseThreshold: number,
	LayerCount: number,
	VerticalSpread: number,
}

export type FrontTypeConfig = {
	SpawnWeight: number,
	MinRadiusX: number,
	MaxRadiusX: number,
	MinRadiusZ: number,
	MaxRadiusZ: number,
	MinLifespan: number,
	MaxLifespan: number,
	MinIntensity: number,
	MaxIntensity: number,
	BaseCloudHeight: number,
	CloudHeightVariance: number,
	BaseCloudScale: Vector3,
	CloudScaleVariance: number,
	CoreColor: Color3,
	EdgeColor: Color3,
	ColorVariance: number,
	HasLightning: boolean,
	LightningThreshold: number?,
	LightningDepthThreshold: number?,
	WeatherWeak: string,
	WeatherMedium: string,
	WeatherStrong: string,
	BiomeOverrides: { [string]: { Weak: string, Medium: string, Strong: string } }?,
	Formation: CloudFormation,
}

export type FrontData = {
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
}

WeatherFronts.Types = {
	Storm = {
		SpawnWeight = 15,
		MinRadiusX = 800,
		MaxRadiusX = 1400,
		MinRadiusZ = 700,
		MaxRadiusZ = 1200,
		MinLifespan = 600,
		MaxLifespan = 1100,
		MinIntensity = 0.6,
		MaxIntensity = 1.0,
		BaseCloudHeight = 500,
		CloudHeightVariance = 180,
		BaseCloudScale = Vector3.new(350, 320, 330),
		CloudScaleVariance = 0.4,
		CoreColor = Color3.fromRGB(45, 45, 58),
		EdgeColor = Color3.fromRGB(120, 120, 138),
		ColorVariance = 0.07,
		HasLightning = true,
		LightningThreshold = 0.55,
		LightningDepthThreshold = 0.35,
		WeatherWeak = "Overcast",
		WeatherMedium = "Rain",
		WeatherStrong = "Thunderstorm",
		BiomeOverrides = {
			Desert = { Weak = "Cloudy", Medium = "Overcast", Strong = "DustStorm" },
			Arctic = { Weak = "Overcast", Medium = "Snow", Strong = "Snow" },
			Tropical = { Weak = "Rain", Medium = "Thunderstorm", Strong = "Thunderstorm" },
			Mountain = { Weak = "Overcast", Medium = "Snow", Strong = "Thunderstorm" },
		},
		Formation = {
			MinClouds = 180,
			MaxClouds = 280,
			CoreDensity = 0.98,
			EdgeDensity = 0.5,
			NoiseScale = 0.005,
			NoiseThreshold = 0.1,
			LayerCount = 8,
			VerticalSpread = 600,
		},
	} :: FrontTypeConfig,

	Rain = {
		SpawnWeight = 30,
		MinRadiusX = 600,
		MaxRadiusX = 1100,
		MinRadiusZ = 500,
		MaxRadiusZ = 900,
		MinLifespan = 500,
		MaxLifespan = 850,
		MinIntensity = 0.4,
		MaxIntensity = 0.85,
		BaseCloudHeight = 350,
		CloudHeightVariance = 120,
		BaseCloudScale = Vector3.new(280, 220, 260),
		CloudScaleVariance = 0.32,
		CoreColor = Color3.fromRGB(100, 100, 118),
		EdgeColor = Color3.fromRGB(165, 165, 180),
		ColorVariance = 0.05,
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Drizzle",
		WeatherStrong = "Rain",
		BiomeOverrides = {
			Desert = { Weak = "Cloudy", Medium = "Cloudy", Strong = "Drizzle" },
			Arctic = { Weak = "Cloudy", Medium = "Snow", Strong = "Snow" },
		},
		Formation = {
			MinClouds = 120,
			MaxClouds = 200,
			CoreDensity = 0.9,
			EdgeDensity = 0.45,
			NoiseScale = 0.007,
			NoiseThreshold = 0.15,
			LayerCount = 5,
			VerticalSpread = 380,
		},
	} :: FrontTypeConfig,

	Snow = {
		SpawnWeight = 12,
		MinRadiusX = 700,
		MaxRadiusX = 1200,
		MinRadiusZ = 600,
		MaxRadiusZ = 1000,
		MinLifespan = 550,
		MaxLifespan = 900,
		MinIntensity = 0.45,
		MaxIntensity = 0.9,
		BaseCloudHeight = 360,
		CloudHeightVariance = 110,
		BaseCloudScale = Vector3.new(260, 180, 240),
		CloudScaleVariance = 0.28,
		CoreColor = Color3.fromRGB(180, 180, 198),
		EdgeColor = Color3.fromRGB(215, 215, 232),
		ColorVariance = 0.04,
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Overcast",
		WeatherStrong = "Snow",
		BiomeOverrides = {
			Desert = { Weak = "Clear", Medium = "Cloudy", Strong = "Cloudy" },
			Tropical = { Weak = "Cloudy", Medium = "Rain", Strong = "Rain" },
		},
		Formation = {
			MinClouds = 130,
			MaxClouds = 220,
			CoreDensity = 0.85,
			EdgeDensity = 0.5,
			NoiseScale = 0.008,
			NoiseThreshold = 0.15,
			LayerCount = 5,
			VerticalSpread = 320,
		},
	} :: FrontTypeConfig,

	Drizzle = {
		SpawnWeight = 25,
		MinRadiusX = 350,
		MaxRadiusX = 600,
		MinRadiusZ = 300,
		MaxRadiusZ = 500,
		MinLifespan = 350,
		MaxLifespan = 550,
		MinIntensity = 0.3,
		MaxIntensity = 0.6,
		BaseCloudHeight = 340,
		CloudHeightVariance = 80,
		BaseCloudScale = Vector3.new(200, 130, 190),
		CloudScaleVariance = 0.32,
		CoreColor = Color3.fromRGB(140, 140, 155),
		EdgeColor = Color3.fromRGB(190, 190, 205),
		ColorVariance = 0.04,
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Drizzle",
		WeatherStrong = "Drizzle",
		BiomeOverrides = {
			Desert = { Weak = "Clear", Medium = "Cloudy", Strong = "Cloudy" },
			Arctic = { Weak = "Cloudy", Medium = "Snow", Strong = "Snow" },
		},
		Formation = {
			MinClouds = 60,
			MaxClouds = 100,
			CoreDensity = 0.75,
			EdgeDensity = 0.4,
			NoiseScale = 0.01,
			NoiseThreshold = 0.2,
			LayerCount = 4,
			VerticalSpread = 200,
		},
	} :: FrontTypeConfig,

	Overcast = {
		SpawnWeight = 20,
		MinRadiusX = 1200,
		MaxRadiusX = 2000,
		MinRadiusZ = 1000,
		MaxRadiusZ = 1800,
		MinLifespan = 700,
		MaxLifespan = 1200,
		MinIntensity = 0.35,
		MaxIntensity = 0.65,
		BaseCloudHeight = 400,
		CloudHeightVariance = 100,
		BaseCloudScale = Vector3.new(380, 160, 360),
		CloudScaleVariance = 0.28,
		CoreColor = Color3.fromRGB(155, 155, 168),
		EdgeColor = Color3.fromRGB(195, 195, 210),
		ColorVariance = 0.03,
		HasLightning = false,
		WeatherWeak = "Cloudy",
		WeatherMedium = "Overcast",
		WeatherStrong = "Overcast",
		Formation = {
			MinClouds = 250,
			MaxClouds = 400,
			CoreDensity = 0.98,
			EdgeDensity = 0.6,
			NoiseScale = 0.004,
			NoiseThreshold = 0.08,
			LayerCount = 4,
			VerticalSpread = 250,
		},
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

function WeatherFronts.SmoothStep(Edge0: number, Edge1: number, Value: number): number
	local Clamped = math.clamp((Value - Edge0) / (Edge1 - Edge0), 0, 1)
	return Clamped * Clamped * (3 - 2 * Clamped)
end

function WeatherFronts.GetWeatherForFront(FrontType: string, Intensity: number, Biome: string, Depth: number?): string
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

	local WeatherConfig = require(script.Parent.WeatherConfig)
	local FrontConfig = WeatherConfig.Fronts

	local EffectiveDepth = Depth or 0
	local DepthBonus = EffectiveDepth * FrontConfig.DepthIntensityInfluence
	local EffectiveIntensity = Intensity + DepthBonus

	if EffectiveIntensity < FrontConfig.WeakIntensityMax then
		return WeatherTable.Weak
	elseif EffectiveIntensity < FrontConfig.MediumIntensityMax then
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

	return "Rain"
end

function WeatherFronts.GetNormalizedDepth(
	Position: Vector3,
	Center: Vector3,
	RadiusX: number,
	RadiusZ: number,
	Rotation: number
): number
	local Offset = Position - Center
	local FlatOffset = Vector3.new(Offset.X, 0, Offset.Z)

	local CosRot = math.cos(-Rotation)
	local SinRot = math.sin(-Rotation)
	local RotatedX = FlatOffset.X * CosRot - FlatOffset.Z * SinRot
	local RotatedZ = FlatOffset.X * SinRot + FlatOffset.Z * CosRot

	local NormalizedX = RotatedX / RadiusX
	local NormalizedZ = RotatedZ / RadiusZ
	local EllipseDistance = math.sqrt(NormalizedX * NormalizedX + NormalizedZ * NormalizedZ)

	if EllipseDistance >= 1 then
		return 0
	end

	return 1 - EllipseDistance
end

function WeatherFronts.IsInsideFront(
	Position: Vector3,
	Center: Vector3,
	RadiusX: number,
	RadiusZ: number,
	Rotation: number
): boolean
	return WeatherFronts.GetNormalizedDepth(Position, Center, RadiusX, RadiusZ, Rotation) > 0
end

function WeatherFronts.GetDistanceToFrontEdge(
	Position: Vector3,
	Center: Vector3,
	RadiusX: number,
	RadiusZ: number,
	Rotation: number
): number
	local Offset = Position - Center
	local FlatOffset = Vector3.new(Offset.X, 0, Offset.Z)

	local CosRot = math.cos(-Rotation)
	local SinRot = math.sin(-Rotation)
	local RotatedX = FlatOffset.X * CosRot - FlatOffset.Z * SinRot
	local RotatedZ = FlatOffset.X * SinRot + FlatOffset.Z * CosRot

	local NormalizedX = RotatedX / RadiusX
	local NormalizedZ = RotatedZ / RadiusZ
	local EllipseDistance = math.sqrt(NormalizedX * NormalizedX + NormalizedZ * NormalizedZ)

	if EllipseDistance <= 0.001 then
		return math.min(RadiusX, RadiusZ)
	end

	local EdgeX = RotatedX / EllipseDistance
	local EdgeZ = RotatedZ / EllipseDistance
	local EdgeWorldX = EdgeX * RadiusX
	local EdgeWorldZ = EdgeZ * RadiusZ

	local EdgeDistance = math.sqrt(EdgeWorldX * EdgeWorldX + EdgeWorldZ * EdgeWorldZ)
	local CurrentDistance = FlatOffset.Magnitude

	return EdgeDistance - CurrentDistance
end

return WeatherFronts