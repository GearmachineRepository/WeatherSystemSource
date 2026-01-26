local WaveConfig = {}

WaveConfig.OceanPath = "workspace/Ocean/Plane"

WaveConfig.BaseWaterHeight = 12

WaveConfig.GridSpacing = 10

--[[
    Balanced Wave Configuration

    Strategy: 5 Gerstner waves for rolling motion + noise for detail
    - Gerstner handles large/medium swells (organized motion)
    - Noise handles small chop (chaotic detail)

    This gives Sea of Thieves-like results with reasonable performance.
]]

WaveConfig.Waves = {
	{
		Wavelength = 150,
		Direction = Vector2.new(1, 0),
		Steepness = 0.12,
		Gravity = 9.8,
	},
	{
		Wavelength = 80,
		Direction = Vector2.new(0.5, 0.87),
		Steepness = 0.10,
		Gravity = 9.8,
	},
	{
		Wavelength = 45,
		Direction = Vector2.new(-0.71, 0.71),
		Steepness = 0.08,
		Gravity = 9.8,
	},
	{
		Wavelength = 25,
		Direction = Vector2.new(-0.5, -0.87),
		Steepness = 0.06,
		Gravity = 9.8,
	},
	{
		Wavelength = 12,
		Direction = Vector2.new(0.87, -0.5),
		Steepness = 0.04,
		Gravity = 9.8,
	},
}

--[[
    Noise Settings

    Adds chaotic surface detail that breaks up Gerstner patterns.
    Synced via math.noise (deterministic for same inputs).

    Amplitude: Height of noise displacement
    Scale: Spatial frequency (higher = smaller features)
    Speed: How fast noise moves
    Octaves: Layers of detail (more = finer detail, more cost)
    Lacunarity: Scale multiplier per octave
    Persistence: Amplitude multiplier per octave
    HorizontalDisplacement: Adds XZ movement (more realistic, slightly more cost)
]]
WaveConfig.NoiseSettings = {
	Enabled = true,
	Amplitude = 0.4,
	Scale = 0.02,
	Speed = 0.5,
	Octaves = 3,
	Lacunarity = 2.0,
	Persistence = 0.5,
	HorizontalDisplacement = true,
}

WaveConfig.MaxUpdateDistance = 500
WaveConfig.UpdateEveryNFrames = 1
WaveConfig.TimeModifier = 5

WaveConfig.WaterDensity = 1000
WaveConfig.BuoyancyMultiplier = 1.0

return WaveConfig