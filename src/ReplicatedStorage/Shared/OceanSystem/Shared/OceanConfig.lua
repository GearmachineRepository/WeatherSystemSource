--!strict

local OceanConfig = {}

OceanConfig.OCEAN_PATH = "workspace/Ocean/Plane"
OceanConfig.BASE_WATER_HEIGHT = 12
OceanConfig.GRID_SPACING = 10
OceanConfig.MAX_UPDATE_DISTANCE = 500
OceanConfig.UPDATE_EVERY_N_FRAMES = 1
OceanConfig.WATER_DENSITY = 1000
OceanConfig.BUOYANCY_MULTIPLIER = 1.0

export type NoiseSettings = {
	Enabled: boolean,
	Amplitude: number,
	Scale: number,
	Speed: number,
	Octaves: number,
	Lacunarity: number,
	Persistence: number,
	HorizontalDisplacement: boolean,
}

OceanConfig.Noise = {
	Enabled = true,
	Amplitude = 0.4,
	Scale = 0.02,
	Speed = 0.5,
	Octaves = 3,
	Lacunarity = 2.0,
	Persistence = 0.5,
	HorizontalDisplacement = true,
} :: NoiseSettings

return OceanConfig