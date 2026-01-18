--!strict

local WeatherConfig = require(script.Parent.WeatherConfig)

local WeatherCalculator = {}

local BONUS_AFTER_MULTIPLIER = 2.5
local CONDITION_MATCH_BONUS = 1.5
local RANDOM_SEED = math.random(1, 10000)

local function GetNoiseValue(TimeElapsed: number, Offset: number): number
	local NoiseValue = math.noise(
		TimeElapsed * WeatherConfig.NOISE_TIME_SCALE,
		Offset,
		RANDOM_SEED
	)
	return math.clamp(NoiseValue + 0.5, 0, 1)
end

function WeatherCalculator.GetGlobalConditions(TimeElapsed: number): {
	Temperature: number,
	Humidity: number,
	Pressure: number,
	}
	local TemperatureNoise = GetNoiseValue(TimeElapsed, 0) * 40 - 10
	local HumidityNoise = GetNoiseValue(TimeElapsed, 100)
	local PressureNoise = GetNoiseValue(TimeElapsed, 200)

	return {
		Temperature = WeatherConfig.Baseline.Temperature + TemperatureNoise,
		Humidity = math.clamp(WeatherConfig.Baseline.Humidity + (HumidityNoise - 0.5), 0, 1),
		Pressure = math.clamp(WeatherConfig.Baseline.Pressure + (PressureNoise - 0.5), 0, 1),
	}
end

function WeatherCalculator.ApplyBiomeModifiers(
	Conditions: { Temperature: number, Humidity: number, Pressure: number },
	BiomeName: string
): { Temperature: number, Humidity: number, Pressure: number }
	local Biome = WeatherConfig.Biomes[BiomeName]
	if not Biome then
		Biome = WeatherConfig.Biomes[WeatherConfig.DEFAULT_BIOME]
	end

	return {
		Temperature = Conditions.Temperature + Biome.TemperatureBias,
		Humidity = math.clamp(Conditions.Humidity + Biome.HumidityBias, 0, 1),
		Pressure = math.clamp(Conditions.Pressure + Biome.PressureBias, 0, 1),
	}
end

function WeatherCalculator.ApplyTimeOfDayModifier(
	Conditions: { Temperature: number, Humidity: number, Pressure: number },
	ClockTime: number
): { Temperature: number, Humidity: number, Pressure: number }
	if not WeatherConfig.DayNight.Enabled then
		return Conditions
	end

	local NoonHour = WeatherConfig.DayNight.NoonHour
	local TimeMultiplier = math.cos((ClockTime - NoonHour) / 24 * 2 * math.pi)
	local TemperatureOffset = WeatherConfig.DayNight.NightTemperatureBias * (1 - TimeMultiplier) / 2

	return {
		Temperature = Conditions.Temperature + TemperatureOffset,
		Humidity = Conditions.Humidity,
		Pressure = Conditions.Pressure,
	}
end

local function CheckConditionsMet(
	StateName: string,
	Conditions: { Temperature: number, Humidity: number, Pressure: number }
): boolean
	local StateConfig = WeatherConfig.States[StateName]
	if not StateConfig then
		return false
	end

	if StateConfig.NeedsHumidityAbove and Conditions.Humidity <= StateConfig.NeedsHumidityAbove then
		return false
	end

	if StateConfig.NeedsHumidityBelow and Conditions.Humidity >= StateConfig.NeedsHumidityBelow then
		return false
	end

	if StateConfig.NeedsPressureAbove and Conditions.Pressure <= StateConfig.NeedsPressureAbove then
		return false
	end

	if StateConfig.NeedsPressureBelow and Conditions.Pressure >= StateConfig.NeedsPressureBelow then
		return false
	end

	if StateConfig.NeedsTemperatureAbove and Conditions.Temperature <= StateConfig.NeedsTemperatureAbove then
		return false
	end

	if StateConfig.NeedsTemperatureBelow and Conditions.Temperature >= StateConfig.NeedsTemperatureBelow then
		return false
	end

	return true
end

local function CalculateConditionMatchScore(
	StateName: string,
	Conditions: { Temperature: number, Humidity: number, Pressure: number }
): number
	local StateConfig = WeatherConfig.States[StateName]
	if not StateConfig then
		return 0
	end

	local Score = 1

	if StateConfig.NeedsHumidityAbove then
		local Excess = Conditions.Humidity - StateConfig.NeedsHumidityAbove
		Score = Score + math.max(0, Excess) * CONDITION_MATCH_BONUS
	end

	if StateConfig.NeedsPressureBelow then
		local Excess = StateConfig.NeedsPressureBelow - Conditions.Pressure
		Score = Score + math.max(0, Excess) * CONDITION_MATCH_BONUS
	end

	if StateConfig.NeedsTemperatureBelow then
		local Excess = StateConfig.NeedsTemperatureBelow - Conditions.Temperature
		Score = Score + math.max(0, Excess / 10) * CONDITION_MATCH_BONUS
	end

	return Score
end

local function GetValidTransitions(
	CurrentState: string,
	PreviousState: string,
	Conditions: { Temperature: number, Humidity: number, Pressure: number }
): { [string]: number }
	local CurrentConfig = WeatherConfig.States[CurrentState]
	if not CurrentConfig then
		return { Clear = 1 }
	end

	local CurrentSeverity = CurrentConfig.Severity
	local ValidStates: { [string]: number } = {}

	for StateName, StateConfig in pairs(WeatherConfig.States) do
		local SeverityDifference = math.abs(StateConfig.Severity - CurrentSeverity)

		if SeverityDifference <= WeatherConfig.SEVERITY_RANGE then
			if CheckConditionsMet(StateName, Conditions) then
				local Weight = CalculateConditionMatchScore(StateName, Conditions)

				if StateName == CurrentState then
					Weight = Weight * 1.5
				end

				if StateConfig.BonusAfter then
					for _, BonusState in ipairs(StateConfig.BonusAfter) do
						if PreviousState == BonusState or CurrentState == BonusState then
							Weight = Weight * BONUS_AFTER_MULTIPLIER
							break
						end
					end
				end

				ValidStates[StateName] = Weight
			end
		end
	end

	if next(ValidStates) == nil then
		ValidStates[CurrentState] = 1
	end

	return ValidStates
end

local function WeightedRandomSelect(Weights: { [string]: number }): string
	local TotalWeight = 0
	for _, Weight in pairs(Weights) do
		TotalWeight = TotalWeight + Weight
	end

	local RandomValue = math.random() * TotalWeight
	local Accumulated = 0

	for StateName, Weight in pairs(Weights) do
		Accumulated = Accumulated + Weight
		if RandomValue <= Accumulated then
			return StateName
		end
	end

	for StateName, _ in pairs(Weights) do
		return StateName
	end

	return "Clear"
end

function WeatherCalculator.DetermineNextState(
	CurrentState: string,
	PreviousState: string,
	TimeInState: number,
	Conditions: { Temperature: number, Humidity: number, Pressure: number }
): (string, boolean)
	local CurrentConfig = WeatherConfig.States[CurrentState]

	if CurrentConfig and TimeInState < CurrentConfig.MinimumDuration then
		return CurrentState, false
	end

	if not CheckConditionsMet(CurrentState, Conditions) then
		local ValidTransitions = GetValidTransitions(CurrentState, PreviousState, Conditions)
		ValidTransitions[CurrentState] = nil

		if next(ValidTransitions) then
			return WeightedRandomSelect(ValidTransitions), true
		end
	end

	local TransitionChance = 0.15 + (TimeInState - (CurrentConfig and CurrentConfig.MinimumDuration or 30)) * 0.005
	TransitionChance = math.clamp(TransitionChance, 0.15, 0.6)

	if math.random() < TransitionChance then
		local ValidTransitions = GetValidTransitions(CurrentState, PreviousState, Conditions)
		local NewState = WeightedRandomSelect(ValidTransitions)
		return NewState, NewState ~= CurrentState
	end

	return CurrentState, false
end

function WeatherCalculator.GetInitialState(
	Conditions: { Temperature: number, Humidity: number, Pressure: number }
): string
	local ValidStates: { [string]: number } = {}

	for StateName, _ in pairs(WeatherConfig.States) do
		if CheckConditionsMet(StateName, Conditions) then
			local Score = CalculateConditionMatchScore(StateName, Conditions)
			ValidStates[StateName] = Score
		end
	end

	if next(ValidStates) == nil then
		return "Clear"
	end

	return WeightedRandomSelect(ValidStates)
end

return WeatherCalculator