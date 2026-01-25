
local WaveConfig = {}

WaveConfig.OceanPath = "workspace/Ocean/Plane"

WaveConfig.BaseWaterHeight = 20

WaveConfig.GridSpacing = 10

--[[
	Steepness = 0.02  -- Lower = calmer
	Steepness = 0.15  -- Higher = rougher

	TimeModifier = 8  -- Higher = slower
	TimeModifier = 2  -- Lower = faster
]]

WaveConfig.Waves = {
	{
		Wavelength = 150,
		Direction = Vector2.new(1, 0),
		Steepness = 0.08,
		Gravity = 9.8,
	},
	{
		Wavelength = 100,
		Direction = Vector2.new(0.7, 0.7),
		Steepness = 0.06,
		Gravity = 9.8,
	},
	{
		Wavelength = 50,
		Direction = Vector2.new(-0.3, 1),
		Steepness = 0.04,
		Gravity = 9.8,
	},
	{
		Wavelength = 25,
		Direction = Vector2.new(0.5, -0.5),
		Steepness = 0.02,
		Gravity = 9.8,
	},
}

-- Performance settings
WaveConfig.MaxUpdateDistance = 500  -- Only update bones within this distance of camera
WaveConfig.UpdateEveryNFrames = 1   -- 1 = every frame, 2 = every other frame, etc.
WaveConfig.TimeModifier = 8         -- Higher = slower waves (default from reference is 4)

-- Boat buoyancy settings
WaveConfig.WaterDensity = 1000      -- kg/m3 (real water is ~1000)
WaveConfig.BuoyancyMultiplier = 1.0 -- Makes boats float higher/lower

return WaveConfig