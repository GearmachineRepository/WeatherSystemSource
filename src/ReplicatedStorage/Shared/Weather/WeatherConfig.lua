--!strict

export type WeatherBaseline = {
	Temperature: number,
	Humidity: number,
	Pressure: number,
}

export type WeatherBiome = {
	TemperatureBias: number,
	HumidityBias: number,
	PressureBias: number,
}

export type WeatherState = {
	Severity: number,
	MinimumDuration: number,
	NeedsHumidityAbove: number?,
	NeedsHumidityBelow: number?,
	NeedsPressureAbove: number?,
	NeedsPressureBelow: number?,
	NeedsTemperatureAbove: number?,
	NeedsTemperatureBelow: number?,
	BonusAfter: { string }?,
}

export type DayNightConfig = {
	Enabled: boolean,
	NightTemperatureBias: number,
	NoonHour: number,
}

export type WindConfig = {
	NoiseTimeScale: number,
	GustNoiseScale: number,
	BaseDirection: Vector3,
	DirectionVariance: number,
	GustIntensity: number,
}

export type WindSoundThresholdsConfig = {
	BreezeMax: number,
	GustyMin: number,
}

export type FrontConfig = {
	Enabled: boolean,
	MapBoundsMin: Vector3,
	MapBoundsMax: Vector3,
	MaxActiveFronts: number,
	BaseSpeed: number,
	WindSpeedInfluence: number,
	DespawnBuffer: number,
	MaxRenderDistance: number,
	DistantLightningMaxDistance: number,
	DistantThunderMaxDistance: number,
	ThunderDelayPerStud: number,
}

export type WeatherConfigType = {
	NOISE_TIME_SCALE: number,
	TICK_RATE: number,
	ZONE_CHECK_INTERVAL: number,
	SEVERITY_RANGE: number,
	DEFAULT_BIOME: string,
	Baseline: WeatherBaseline,
	Biomes: { [string]: WeatherBiome },
	States: { [string]: WeatherState },
	DayNight: DayNightConfig,
	Wind: WindConfig,
	WindSoundThresholds: WindSoundThresholdsConfig,
	Fronts: FrontConfig,
}

local WeatherConfig: WeatherConfigType = {
	NOISE_TIME_SCALE = 0.00008,
	TICK_RATE = 8,
	ZONE_CHECK_INTERVAL = 0.5,
	SEVERITY_RANGE = 1.5,

	DEFAULT_BIOME = "Temperate",

	Baseline = {
		Temperature = 15,
		Humidity = 0.5,
		Pressure = 0.5,
	},

	Biomes = {
		Temperate = {
			TemperatureBias = 0,
			HumidityBias = 0,
			PressureBias = -0.05,
		},
		Desert = {
			TemperatureBias = 20,
			HumidityBias = -0.2,
			PressureBias = -0.08,
		},
		Arctic = {
			TemperatureBias = -30,
			HumidityBias = 0.1,
			PressureBias = 0,
		},
		Tropical = {
			TemperatureBias = 10,
			HumidityBias = 0.25,
			PressureBias = -0.1,
		},
		Swamp = {
			TemperatureBias = 5,
			HumidityBias = 0.35,
			PressureBias = -0.05,
		},
		Mountain = {
			TemperatureBias = -10,
			HumidityBias = 0.15,
			PressureBias = -0.15,
		},
	},

	States = {
		Clear = {
			Severity = 1,
			MinimumDuration = 60,
		},
		Cloudy = {
			Severity = 2,
			MinimumDuration = 45,
		},
		Overcast = {
			Severity = 3,
			MinimumDuration = 40,
		},
		Drizzle = {
			Severity = 3.5,
			MinimumDuration = 35,
			NeedsHumidityAbove = 0.4,
		},
		Rain = {
			Severity = 4,
			MinimumDuration = 50,
			NeedsHumidityAbove = 0.5,
		},
		Thunderstorm = {
			Severity = 5,
			MinimumDuration = 40,
			NeedsHumidityAbove = 0.55,
			NeedsPressureBelow = 0.45,
		},
		Snow = {
			Severity = 4,
			MinimumDuration = 55,
			NeedsHumidityAbove = 0.4,
			NeedsTemperatureBelow = 2,
		},
		DustStorm = {
			Severity = 4,
			MinimumDuration = 35,
			NeedsHumidityBelow = 0.35,
			NeedsPressureBelow = 0.4,
		},
		Fog = {
			Severity = 2,
			MinimumDuration = 30,
			NeedsHumidityAbove = 0.55,
			BonusAfter = { "Rain", "Drizzle", "Snow" },
		},
	},

	DayNight = {
		Enabled = true,
		NightTemperatureBias = -8,
		NoonHour = 12,
	},

	Wind = {
		NoiseTimeScale = 0.0003,
		GustNoiseScale = 0.002,
		BaseDirection = Vector3.new(1, 0, 0.3).Unit,
		DirectionVariance = 0.4,
		GustIntensity = 0.6,
	},

	WindSoundThresholds = {
		BreezeMax = 12,
		GustyMin = 8,
	},

	Fronts = {
		Enabled = true,
		MapBoundsMin = Vector3.new(-2000, 0, -2000),
		MapBoundsMax = Vector3.new(2000, 500, 2000),
		MaxActiveFronts = 4,
		BaseSpeed = 5,
		WindSpeedInfluence = 0.15,
		DespawnBuffer = 900,
		MaxRenderDistance = 3500,
		DistantLightningMaxDistance = 2200,
		DistantThunderMaxDistance = 1200,
		ThunderDelayPerStud = 0.0028,
	},
}

return WeatherConfig