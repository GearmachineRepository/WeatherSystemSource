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
	Lighting: {
		Ambient: Color3,
		Brightness: number,
		ExposureCompensation: number,
	}?,
	Atmosphere: {
		Density: number,
		Offset: number,
		Color: Color3,
		Decay: Color3,
		Glare: number,
		Haze: number,
	}?,
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
	MinActiveFronts: number,
	BaseSpeed: number,
	WindSpeedInfluence: number,
	SpawnBuffer: number,
	DespawnBuffer: number,
	MaxRenderDistance: number,
	CloudFadeDistance: number,
	DistantLightningMaxDistance: number,
	DistantThunderMaxDistance: number,
	ThunderDelayPerStud: number,
	SpawnIntervalMin: number,
	SpawnIntervalMax: number,
	InitialFrontCount: number,
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
			Lighting = {
				Ambient = Color3.fromRGB(165, 150, 130),
				Brightness = 2.2,
				ExposureCompensation = 0.1,
			},
			Atmosphere = {
				Density = 0.35,
				Offset = 0.15,
				Color = Color3.fromRGB(210, 195, 170),
				Decay = Color3.fromRGB(140, 115, 85),
				Glare = 0.6,
				Haze = 2.2,
			},
		},
		Arctic = {
			TemperatureBias = -30,
			HumidityBias = 0.1,
			PressureBias = 0,
			Lighting = {
				Ambient = Color3.fromRGB(170, 175, 190),
				Brightness = 2.3,
				ExposureCompensation = 0.05,
			},
			Atmosphere = {
				Density = 0.25,
				Offset = 0.05,
				Color = Color3.fromRGB(210, 220, 235),
				Decay = Color3.fromRGB(130, 150, 180),
				Glare = 0.45,
				Haze = 1.2,
			},
		},
		Tropical = {
			TemperatureBias = 10,
			HumidityBias = 0.25,
			PressureBias = -0.1,
			Lighting = {
				Ambient = Color3.fromRGB(145, 160, 140),
				Brightness = 1.9,
				ExposureCompensation = -0.05,
			},
			Atmosphere = {
				Density = 0.38,
				Offset = 0.12,
				Color = Color3.fromRGB(180, 195, 175),
				Decay = Color3.fromRGB(85, 110, 95),
				Glare = 0.4,
				Haze = 2.0,
			},
		},
		Swamp = {
			TemperatureBias = 5,
			HumidityBias = 0.35,
			PressureBias = -0.05,
			Lighting = {
				Ambient = Color3.fromRGB(125, 135, 120),
				Brightness = 1.6,
				ExposureCompensation = 0.15,
			},
			Atmosphere = {
				Density = 0.48,
				Offset = 0.25,
				Color = Color3.fromRGB(160, 170, 155),
				Decay = Color3.fromRGB(75, 90, 70),
				Glare = 0.2,
				Haze = 3.5,
			},
		},
		Mountain = {
			TemperatureBias = -10,
			HumidityBias = 0.15,
			PressureBias = -0.15,
			Lighting = {
				Ambient = Color3.fromRGB(155, 155, 165),
				Brightness = 2.1,
				ExposureCompensation = 0,
			},
			Atmosphere = {
				Density = 0.22,
				Offset = 0.05,
				Color = Color3.fromRGB(195, 200, 210),
				Decay = Color3.fromRGB(100, 115, 140),
				Glare = 0.55,
				Haze = 1.0,
			},
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
		MapBoundsMin = Vector3.new(-3000, 0, -3000),
		MapBoundsMax = Vector3.new(3000, 500, 3000),
		MaxActiveFronts = 16,
		MinActiveFronts = 8,
		BaseSpeed = 8,
		WindSpeedInfluence = 0.2,
		SpawnBuffer = 800,
		DespawnBuffer = 1200,
		MaxRenderDistance = 4500,
		CloudFadeDistance = 800,
		DistantLightningMaxDistance = 2500,
		DistantThunderMaxDistance = 1500,
		ThunderDelayPerStud = 0.0028,
		SpawnIntervalMin = 15,
		SpawnIntervalMax = 60,
		InitialFrontCount = 8,
		WeakIntensityMax = 0.35,
		MediumIntensityMax = 0.6,
		DepthIntensityInfluence = 0.5,
	},
}

return WeatherConfig