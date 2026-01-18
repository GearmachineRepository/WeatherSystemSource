--!strict

export type LightningConfig = {
	Enabled: boolean,
	IntervalMin: number,
	IntervalMax: number,
	FlashBrightness: number,
	FlashBrightnessMultiplier: number,
	FlashExposureAdd: number,
	FlashDuration: number,
	FlashFadeTime: number,
	ThunderDelayMin: number,
	ThunderDelayMax: number,
	BoltDuration: number,
	StrikeHeightMin: number,
	StrikeHeightMax: number,
	StrikeRadius: number,
	MinimumStrikeDistance: number,
	PreferDistantStrikes: boolean,
	FarStrikeChance: number,
	FarStrikeRadiusMultiplier: number,
	FarStrikeHeightMultiplier: number,
	BranchCountMin: number,
	BranchCountMax: number,
	CloseThunderEnabled: boolean,
	CloseThunderRadius: number,
	CloseThunderDelayMin: number,
	CloseThunderDelayMax: number,
	CloseThunderVolumeMultiplier: number,
	FarThunderVolumeMultiplier: number,
}

export type NightMultiplierConfig = {
	CloudColorDarken: number,
	AtmosphereColorDarken: number,
	AmbientDarken: number,
	BrightnessDarken: number,
}

export type ParticleConfig = {
	Enabled: boolean,
	Rate: number?,
}

export type SkyConfig = {
	SunAngularSize: number,
	MoonAngularSize: number,
}

export type CloudConfig = {
	Cover: number,
	Density: number,
	Color: Color3,
}

export type AtmosphereConfig = {
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
}

export type LightingConfig = {
	Ambient: Color3,
	Brightness: number,
	ExposureCompensation: number,
}

export type ParticlesConfig = {
	Rain: ParticleConfig,
	Snow: ParticleConfig,
}

export type SoundsConfig = {
	Rain: { Volume: number },
	Thunder: { Volume: number },
	WindBreeze: { Volume: number },
	WindGusty: { Volume: number },
}

export type WindConfig = {
	SpeedMin: number,
	SpeedMax: number,
}

export type WeatherStateEffects = {
	Sky: SkyConfig,
	Clouds: CloudConfig,
	Atmosphere: AtmosphereConfig,
	Lighting: LightingConfig,
	Particles: ParticlesConfig,
	Sounds: SoundsConfig,
	Wind: WindConfig,
}

export type WeatherEffectsType = {
	TRANSITION_TIME: number,
	ZONE_CHANGE_TIME: number,
	Lightning: LightningConfig,
	NightMultipliers: NightMultiplierConfig,
	States: { [string]: WeatherStateEffects },
}

local WeatherEffects: WeatherEffectsType = {
	TRANSITION_TIME = 12,
	ZONE_CHANGE_TIME = 6,

	Lightning = {
		Enabled = true,
		IntervalMin = 6,
		IntervalMax = 20,
		StrikeHeightMin = 200,
		StrikeHeightMax = 550,
		StrikeRadius = 1200,
		MinimumStrikeDistance = 250,
		PreferDistantStrikes = true,
		FarStrikeChance = 0.7,
		FarStrikeRadiusMultiplier = 2.5,
		FarStrikeHeightMultiplier = 1.8,
		BoltDuration = 0.35,
		BranchCountMin = 2,
		BranchCountMax = 5,
		FlashBrightness = 4.0,
		FlashBrightnessMultiplier = 1.8,
		FlashExposureAdd = 2.0,
		FlashDuration = 0.1,
		FlashFadeTime = 0.12,
		ThunderDelayMin = 0.4,
		ThunderDelayMax = 2.2,
		CloseThunderEnabled = true,
		CloseThunderRadius = 500,
		CloseThunderDelayMin = 0.08,
		CloseThunderDelayMax = 0.4,
		CloseThunderVolumeMultiplier = 1.6,
		FarThunderVolumeMultiplier = 0.9,
	},

	NightMultipliers = {
		CloudColorDarken = 0.7,
		AtmosphereColorDarken = 0.6,
		AmbientDarken = 0.5,
		BrightnessDarken = 0.4,
	},

	States = {
		Clear = {
			Sky = {
				SunAngularSize = 21,
				MoonAngularSize = 11,
			},
			Clouds = {
				Cover = 0.35,
				Density = 0.22,
				Color = Color3.fromRGB(255, 255, 255),
			},
			Atmosphere = {
				Density = 0.28,
				Offset = 0.08,
				Color = Color3.fromRGB(199, 199, 199),
				Decay = Color3.fromRGB(92, 120, 150),
				Glare = 0.5,
				Haze = 1.4,
			},
			Lighting = {
				Ambient = Color3.fromRGB(150, 150, 150),
				Brightness = 2,
				ExposureCompensation = 0,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.15 },
				WindGusty = { Volume = 0 },
			},
			Wind = {
				SpeedMin = 2,
				SpeedMax = 6,
			},
		},

		Cloudy = {
			Sky = {
				SunAngularSize = 21,
				MoonAngularSize = 11,
			},
			Clouds = {
				Cover = 0.7,
				Density = 0.42,
				Color = Color3.fromRGB(225, 225, 228),
			},
			Atmosphere = {
				Density = 0.35,
				Offset = 0.15,
				Color = Color3.fromRGB(180, 180, 185),
				Decay = Color3.fromRGB(85, 100, 120),
				Glare = 0.28,
				Haze = 2.0,
			},
			Lighting = {
				Ambient = Color3.fromRGB(135, 135, 140),
				Brightness = 1.75,
				ExposureCompensation = 0.1,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.18 },
				WindGusty = { Volume = 0.05 },
			},
			Wind = {
				SpeedMin = 4,
				SpeedMax = 10,
			},
		},

		Overcast = {
			Sky = {
				SunAngularSize = 21,
				MoonAngularSize = 11,
			},
			Clouds = {
				Cover = 0.95,
				Density = 0.65,
				Color = Color3.fromRGB(165, 165, 172),
			},
			Atmosphere = {
				Density = 0.42,
				Offset = 0.2,
				Color = Color3.fromRGB(160, 160, 165),
				Decay = Color3.fromRGB(70, 80, 95),
				Glare = 0.08,
				Haze = 2.6,
			},
			Lighting = {
				Ambient = Color3.fromRGB(112, 112, 118),
				Brightness = 1.45,
				ExposureCompensation = 0.2,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.12 },
				WindGusty = { Volume = 0.28 },
			},
			Wind = {
				SpeedMin = 6,
				SpeedMax = 14,
			},
		},

		Drizzle = {
			Sky = {
				SunAngularSize = 21,
				MoonAngularSize = 11,
			},
			Clouds = {
				Cover = 0.82,
				Density = 0.55,
				Color = Color3.fromRGB(168, 168, 174),
			},
			Atmosphere = {
				Density = 0.44,
				Offset = 0.22,
				Color = Color3.fromRGB(155, 158, 162),
				Decay = Color3.fromRGB(65, 75, 90),
				Glare = 0.06,
				Haze = 2.8,
			},
			Lighting = {
				Ambient = Color3.fromRGB(108, 108, 114),
				Brightness = 1.35,
				ExposureCompensation = 0.22,
			},
			Particles = {
				Rain = { Enabled = true, Rate = 100 },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0.35 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.12 },
				WindGusty = { Volume = 0.22 },
			},
			Wind = {
				SpeedMin = 5,
				SpeedMax = 12,
			},
		},

		Rain = {
			Sky = {
				SunAngularSize = 8,
				MoonAngularSize = 4,
			},
			Clouds = {
				Cover = 0.92,
				Density = 0.68,
				Color = Color3.fromRGB(145, 145, 152),
			},
			Atmosphere = {
				Density = 0.48,
				Offset = 0.26,
				Color = Color3.fromRGB(138, 142, 148),
				Decay = Color3.fromRGB(58, 68, 82),
				Glare = 0.04,
				Haze = 3.2,
			},
			Lighting = {
				Ambient = Color3.fromRGB(98, 98, 104),
				Brightness = 1.15,
				ExposureCompensation = 0.3,
			},
			Particles = {
				Rain = { Enabled = true, Rate = 500 },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0.65 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.08 },
				WindGusty = { Volume = 0.35 },
			},
			Wind = {
				SpeedMin = 8,
				SpeedMax = 18,
			},
		},

		Thunderstorm = {
			Sky = {
				SunAngularSize = 5,
				MoonAngularSize = 2,
			},
			Clouds = {
				Cover = 1,
				Density = 0.88,
				Color = Color3.fromRGB(85, 85, 95),
			},
			Atmosphere = {
				Density = 0.52,
				Offset = 0.32,
				Color = Color3.fromRGB(95, 100, 112),
				Decay = Color3.fromRGB(38, 42, 52),
				Glare = 0,
				Haze = 4.2,
			},
			Lighting = {
				Ambient = Color3.fromRGB(68, 68, 78),
				Brightness = 0.85,
				ExposureCompensation = 0.42,
			},
			Particles = {
				Rain = { Enabled = true, Rate = 650 },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0.85 },
				Thunder = { Volume = 0.75 },
				WindBreeze = { Volume = 0 },
				WindGusty = { Volume = 0.75 },
			},
			Wind = {
				SpeedMin = 16,
				SpeedMax = 38,
			},
		},

		Snow = {
			Sky = {
				SunAngularSize = 8,
				MoonAngularSize = 4,
			},
			Clouds = {
				Cover = 0.82,
				Density = 0.48,
				Color = Color3.fromRGB(218, 218, 224),
			},
			Atmosphere = {
				Density = 0.52,
				Offset = 0.22,
				Color = Color3.fromRGB(198, 202, 212),
				Decay = Color3.fromRGB(148, 152, 168),
				Glare = 0.18,
				Haze = 3.2,
			},
			Lighting = {
				Ambient = Color3.fromRGB(138, 142, 154),
				Brightness = 1.35,
				ExposureCompensation = 0.15,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = true, Rate = 250 },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.12 },
				WindGusty = { Volume = 0.42 },
			},
			Wind = {
				SpeedMin = 6,
				SpeedMax = 16,
			},
		},

		DustStorm = {
			Sky = {
				SunAngularSize = 12,
				MoonAngularSize = 6,
			},
			Clouds = {
				Cover = 0.7,
				Density = 0.4,
				Color = Color3.fromRGB(180, 165, 140),
			},
			Atmosphere = {
				Density = 0.65,
				Offset = 0.35,
				Color = Color3.fromRGB(185, 160, 130),
				Decay = Color3.fromRGB(140, 115, 85),
				Glare = 0.02,
				Haze = 5.5,
			},
			Lighting = {
				Ambient = Color3.fromRGB(145, 130, 105),
				Brightness = 1.1,
				ExposureCompensation = 0.35,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0 },
				WindGusty = { Volume = 0.8 },
			},
			Wind = {
				SpeedMin = 18,
				SpeedMax = 40,
			},
		},

		Fog = {
			Sky = {
				SunAngularSize = 21,
				MoonAngularSize = 11,
			},
			Clouds = {
				Cover = 0.58,
				Density = 0.28,
				Color = Color3.fromRGB(198, 198, 198),
			},
			Atmosphere = {
				Density = 0.72,
				Offset = 0.52,
				Color = Color3.fromRGB(178, 182, 188),
				Decay = Color3.fromRGB(168, 172, 178),
				Glare = 0,
				Haze = 6.5,
			},
			Lighting = {
				Ambient = Color3.fromRGB(128, 132, 138),
				Brightness = 1.25,
				ExposureCompensation = 0.25,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.1 },
				WindGusty = { Volume = 0 },
			},
			Wind = {
				SpeedMin = 1,
				SpeedMax = 4,
			},
		},
	},
}

return WeatherEffects