--!strict

export type LightningConfig = {
	Enabled: boolean,
	IntervalMin: number,
	IntervalMax: number,
	FlashBrightness: number,
	FlashDuration: number,
	ThunderDelayMin: number,
	ThunderDelayMax: number,
	BoltDuration: number,
	StrikeHeightMin: number,
	StrikeHeightMax: number,
	StrikeRadius: number,
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

export type WeatherStateEffects = {
	Clouds: {
		Cover: number,
		Density: number,
		Color: Color3,
	},
	Atmosphere: {
		Density: number,
		Offset: number,
		Color: Color3,
		Decay: Color3,
		Glare: number,
		Haze: number,
	},
	Lighting: {
		Ambient: Color3,
		Brightness: number,
		ExposureCompensation: number,
	},
	Particles: {
		Rain: ParticleConfig,
		Snow: ParticleConfig,
	},
	Sounds: {
		Rain: { Volume: number },
		Thunder: { Volume: number },
		WindBreeze: { Volume: number },
		WindGusty: { Volume: number },
	},
}

export type WeatherEffects = {
	TRANSITION_TIME: number,
	ZONE_CHANGE_TIME: number,
	Lightning: LightningConfig,
	NightMultipliers: NightMultiplierConfig,
	States: { [string]: WeatherStateEffects },
}

local WeatherEffects: WeatherEffects = {
	TRANSITION_TIME = 15,
	ZONE_CHANGE_TIME = 8,

	Lightning = {
		Enabled = true,
		IntervalMin = 8,
		IntervalMax = 25,

		StrikeHeightMin = 180,
		StrikeHeightMax = 500,
		StrikeRadius = 1000,

		MinimumStrikeDistance = 300,
		PreferDistantStrikes = true,
		FarStrikeChance = 0.75,
		FarStrikeRadiusMultiplier = 3,
		FarStrikeHeightMultiplier = 2,

		BoltDuration = 0.4,

		BranchCountMin = 2,
		BranchCountMax = 6,

		FlashBrightness = 4.5,
		FlashBrightnessMultiplier = 2.0,
		FlashExposureAdd = 2.2,
		FlashDuration = 0.12,
		FlashFadeTime = 0.15,

		ThunderDelayMin = 0.3,
		ThunderDelayMax = 2.5,
		
		CloseThunderEnabled = true,
		CloseThunderRadius = 450,
		CloseThunderDelayMin = 0.05,
		CloseThunderDelayMax = 0.35,
		CloseThunderVolumeMultiplier = 1.8,
		FarThunderVolumeMultiplier = 1.0,
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
				Cover = 0.2,
				Density = 0.15,
				Color = Color3.fromRGB(255, 255, 255),
			},
			Atmosphere = {
				Density = 0.3,
				Offset = 0.1,
				Color = Color3.fromRGB(199, 199, 199),
				Decay = Color3.fromRGB(92, 120, 150),
				Glare = 0.5,
				Haze = 1.5,
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
				Cover = 0.55,
				Density = 0.3,
				Color = Color3.fromRGB(230, 230, 230),
			},
			Atmosphere = {
				Density = 0.35,
				Offset = 0.15,
				Color = Color3.fromRGB(180, 180, 185),
				Decay = Color3.fromRGB(85, 100, 120),
				Glare = 0.3,
				Haze = 2,
			},
			Lighting = {
				Ambient = Color3.fromRGB(135, 135, 140),
				Brightness = 1.8,
				ExposureCompensation = 0.1,
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
				Cover = 0.85,
				Density = 0.5,
				Color = Color3.fromRGB(180, 180, 185),
			},
			Atmosphere = {
				Density = 0.4,
				Offset = 0.2,
				Color = Color3.fromRGB(160, 160, 165),
				Decay = Color3.fromRGB(70, 80, 95),
				Glare = 0.1,
				Haze = 2.5,
			},
			Lighting = {
				Ambient = Color3.fromRGB(115, 115, 120),
				Brightness = 1.5,
				ExposureCompensation = 0.2,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.15 },
				WindGusty = { Volume = 0.25 },
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
				Cover = 0.8,
				Density = 0.55,
				Color = Color3.fromRGB(170, 170, 175),
			},
			Atmosphere = {
				Density = 0.42,
				Offset = 0.22,
				Color = Color3.fromRGB(155, 158, 162),
				Decay = Color3.fromRGB(65, 75, 90),
				Glare = 0.08,
				Haze = 2.7,
			},
			Lighting = {
				Ambient = Color3.fromRGB(110, 110, 115),
				Brightness = 1.4,
				ExposureCompensation = 0.22,
			},
			Particles = {
				Rain = { Enabled = true, Rate = 80 },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0.3 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.15 },
				WindGusty = { Volume = 0.2 },
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
				Cover = 0.9,
				Density = 0.65,
				Color = Color3.fromRGB(150, 150, 155),
			},
			Atmosphere = {
				Density = 0.45,
				Offset = 0.25,
				Color = Color3.fromRGB(140, 145, 150),
				Decay = Color3.fromRGB(60, 70, 85),
				Glare = 0.05,
				Haze = 3,
			},
			Lighting = {
				Ambient = Color3.fromRGB(100, 100, 105),
				Brightness = 1.2,
				ExposureCompensation = 0.3,
			},
			Particles = {
				Rain = { Enabled = true, Rate = 450 },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0.6 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.15 },
				WindGusty = { Volume = 0.3 },
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
				Density = 0.85,
				Color = Color3.fromRGB(90, 90, 100),
			},
			Atmosphere = {
				Density = 0.5,
				Offset = 0.3,
				Color = Color3.fromRGB(100, 105, 115),
				Decay = Color3.fromRGB(40, 45, 55),
				Glare = 0,
				Haze = 4,
			},
			Lighting = {
				Ambient = Color3.fromRGB(70, 70, 80),
				Brightness = 0.9,
				ExposureCompensation = 0.4,
			},
			Particles = {
				Rain = { Enabled = true, Rate = 500 },
				Snow = { Enabled = false },
			},
			Sounds = {
				Rain = { Volume = 0.8 },
				Thunder = { Volume = 0.7 },
				WindBreeze = { Volume = 0 },
				WindGusty = { Volume = 0.7 },
			},
			Wind = {
				SpeedMin = 15,
				SpeedMax = 35,
			},
		},

		Snow = {
			Sky = {
				SunAngularSize = 8,
				MoonAngularSize = 4,
			},
			Clouds = {
				Cover = 0.8,
				Density = 0.45,
				Color = Color3.fromRGB(220, 220, 225),
			},
			Atmosphere = {
				Density = 0.5,
				Offset = 0.2,
				Color = Color3.fromRGB(200, 205, 215),
				Decay = Color3.fromRGB(150, 155, 170),
				Glare = 0.2,
				Haze = 3,
			},
			Lighting = {
				Ambient = Color3.fromRGB(140, 145, 155),
				Brightness = 1.4,
				ExposureCompensation = 0.15,
			},
			Particles = {
				Rain = { Enabled = false },
				Snow = { Enabled = true, Rate = 200 },
			},
			Sounds = {
				Rain = { Volume = 0 },
				Thunder = { Volume = 0 },
				WindBreeze = { Volume = 0.15 },
				WindGusty = { Volume = 0.4 },
			},
			Wind = {
				SpeedMin = 6,
				SpeedMax = 16,
			},
		},

		Fog = {
			Sky = {
				SunAngularSize = 21,
				MoonAngularSize = 11,
			},
			Clouds = {
				Cover = 0.6,
				Density = 0.25,
				Color = Color3.fromRGB(200, 200, 200),
			},
			Atmosphere = {
				Density = 0.7,
				Offset = 0.5,
				Color = Color3.fromRGB(180, 185, 190),
				Decay = Color3.fromRGB(170, 175, 180),
				Glare = 0,
				Haze = 6,
			},
			Lighting = {
				Ambient = Color3.fromRGB(130, 135, 140),
				Brightness = 1.3,
				ExposureCompensation = 0.25,
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
				SpeedMin = 1,
				SpeedMax = 4,
			},
		},
	},
}

return WeatherEffects
