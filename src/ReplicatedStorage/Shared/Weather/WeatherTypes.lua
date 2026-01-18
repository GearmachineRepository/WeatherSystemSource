--!strict

export type AtmosphericConditions = {
	Temperature: number,
	Humidity: number,
	Pressure: number,
}

export type BiomeConfig = {
	TemperatureBias: number,
	HumidityBias: number,
	PressureBias: number,
}

export type WeatherStateConfig = {
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

export type ZoneState = {
	CurrentState: string,
	PreviousState: string,
	TimeInState: number,
	Conditions: AtmosphericConditions,
}

export type CloudsTarget = {
	Cover: number,
	Density: number,
	Color: Color3,
}

export type AtmosphereTarget = {
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
}

export type LightingTarget = {
	Ambient: Color3,
	Brightness: number,
	ExposureCompensation: number,
}

export type ParticleTarget = {
	Enabled: boolean,
	Rate: number?,
}

export type SoundTarget = {
	Volume: number,
}

export type WeatherEffectState = {
	Clouds: CloudsTarget,
	Atmosphere: AtmosphereTarget,
	Lighting: LightingTarget,
	Particles: {
		Rain: ParticleTarget,
		Snow: ParticleTarget,
	},
	Sounds: {
		Rain: SoundTarget,
		Thunder: SoundTarget,
		Wind: SoundTarget,
	},
}

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

export type InterpolationState = {
	StartTime: number,
	Duration: number,
	FromClouds: CloudsTarget,
	ToClouds: CloudsTarget,
	FromAtmosphere: AtmosphereTarget,
	ToAtmosphere: AtmosphereTarget,
	FromLighting: LightingTarget,
	ToLighting: LightingTarget,
	FromParticles: { Rain: ParticleTarget, Snow: ParticleTarget },
	ToParticles: { Rain: ParticleTarget, Snow: ParticleTarget },
	FromSounds: { Rain: SoundTarget, Thunder: SoundTarget, Wind: SoundTarget },
	ToSounds: { Rain: SoundTarget, Thunder: SoundTarget, Wind: SoundTarget },
}

return nil