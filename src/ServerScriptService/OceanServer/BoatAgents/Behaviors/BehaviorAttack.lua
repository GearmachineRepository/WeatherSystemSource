--!strict

local Players = game:GetService("Players")

local BehaviorTypes = require(script.Parent:WaitForChild("BehaviorTypes"))

local BehaviorAttack = {}

local CIRCLE_RADIUS = BehaviorTypes.ATTACK_CIRCLE_RADIUS
local CIRCLE_THROTTLE = BehaviorTypes.ATTACK_CIRCLE_THROTTLE
local PURSUIT_THROTTLE = BehaviorTypes.ATTACK_PURSUIT_THROTTLE
local TARGET_STATIONARY_SPEED = BehaviorTypes.ATTACK_TARGET_STATIONARY_SPEED
local TARGET_STATIONARY_TIME = BehaviorTypes.ATTACK_TARGET_STATIONARY_TIME
local CIRCLE_ANGULAR_SPEED = BehaviorTypes.ATTACK_CIRCLE_ANGULAR_SPEED
local DETECTION_RANGE = BehaviorTypes.ATTACK_DETECTION_RANGE
local LOSE_TARGET_RANGE = BehaviorTypes.ATTACK_LOSE_TARGET_RANGE

export type AttackConfig = {
	Target: Model?,
	TargetPlayer: Player?,
	AutoTarget: boolean?,
	CircleRadius: number?,
	DetectionRange: number?,
}

local function GetTargetPart(Target: Model): BasePart?
	if Target.PrimaryPart then
		return Target.PrimaryPart
	end

	local HumanoidRootPart = Target:FindFirstChild("HumanoidRootPart")
	if HumanoidRootPart and HumanoidRootPart:IsA("BasePart") then
		return HumanoidRootPart
	end

	for _, Child in ipairs(Target:GetDescendants()) do
		if Child:IsA("BasePart") then
			return Child
		end
	end

	return nil
end

local function FindNearestTarget(Agent: any, DetectionRange: number): (Model?, BasePart?)
	local BoatPosition = Agent.PrimaryPart.Position
	local NearestTarget: Model? = nil
	local NearestPart: BasePart? = nil
	local NearestDistance = DetectionRange

	for _, Player in ipairs(Players:GetPlayers()) do
		local Character = Player.Character
		if Character then
			local TargetPart = GetTargetPart(Character)
			if TargetPart then
				local Distance = (TargetPart.Position - BoatPosition).Magnitude
				if Distance < NearestDistance then
					NearestDistance = Distance
					NearestTarget = Character
					NearestPart = TargetPart
				end
			end
		end
	end

	return NearestTarget, NearestPart
end

function BehaviorAttack.Initialize(Agent: any, Config: AttackConfig?)
	local State = Agent.State.BehaviorState
	State.Name = "Attack"
	State.AttackState = "PURSUING"

	local AttackData: BehaviorTypes.AttackTargetData = {
		Target = nil,
		TargetPart = nil,
		LastTargetPosition = nil,
		LastTargetVelocity = nil,
		TargetStationaryTime = 0,
		CircleAngle = 0,
		CircleDirection = 1,
	}

	State.AttackData = AttackData

	local CircleRadius = CIRCLE_RADIUS
	local DetectionRange = DETECTION_RANGE
	local AutoTarget = true

	if Config then
		CircleRadius = Config.CircleRadius or CircleRadius
		DetectionRange = Config.DetectionRange or DetectionRange

		if Config.AutoTarget ~= nil then
			AutoTarget = Config.AutoTarget
		end

		if Config.Target then
			AttackData.Target = Config.Target
			AttackData.TargetPart = GetTargetPart(Config.Target)
		elseif Config.TargetPlayer then
			local Character = Config.TargetPlayer.Character
			if Character then
				AttackData.Target = Character
				AttackData.TargetPart = GetTargetPart(Character)
			end
		end
	end

	Agent.Config.AttackCircleRadius = CircleRadius
	Agent.Config.AttackDetectionRange = DetectionRange
	Agent.Config.AttackAutoTarget = AutoTarget

	if Agent.RandomGenerator:NextNumber() > 0.5 then
		AttackData.CircleDirection = -1
	end

	local BoatPosition = Agent.PrimaryPart.Position
	Agent.State.TargetX = BoatPosition.X
	Agent.State.TargetZ = BoatPosition.Z
end

function BehaviorAttack.SetTarget(Agent: any, Target: Model?)
	local State = Agent.State.BehaviorState
	local AttackData = State.AttackData

	if not AttackData then
		return
	end

	if Target then
		AttackData.Target = Target
		AttackData.TargetPart = GetTargetPart(Target)
		AttackData.TargetStationaryTime = 0
		State.AttackState = "PURSUING"
	else
		AttackData.Target = nil
		AttackData.TargetPart = nil
		AttackData.LastTargetPosition = nil
		AttackData.LastTargetVelocity = nil
	end
end

local function EstimateTargetVelocity(AttackData: BehaviorTypes.AttackTargetData, CurrentPosition: Vector3, DeltaTime: number): Vector3
	if not AttackData.LastTargetPosition or DeltaTime <= 0 then
		AttackData.LastTargetPosition = CurrentPosition
		return Vector3.zero
	end

	local Delta = CurrentPosition - AttackData.LastTargetPosition
	local Velocity = Delta / DeltaTime

	AttackData.LastTargetPosition = CurrentPosition

	if AttackData.LastTargetVelocity then
		Velocity = AttackData.LastTargetVelocity:Lerp(Velocity, 0.3)
	end

	AttackData.LastTargetVelocity = Velocity

	return Velocity
end

local function CalculateCirclePosition(TargetPosition: Vector3, CircleAngle: number, CircleRadius: number): Vector3
	local OffsetX = math.cos(CircleAngle) * CircleRadius
	local OffsetZ = math.sin(CircleAngle) * CircleRadius

	return Vector3.new(
		TargetPosition.X + OffsetX,
		TargetPosition.Y,
		TargetPosition.Z + OffsetZ
	)
end

function BehaviorAttack.Update(Agent: any, DeltaTime: number): BehaviorTypes.BehaviorOutput
	local State = Agent.State.BehaviorState
	local AttackData = State.AttackData

	if not AttackData then
		return {
			TargetX = Agent.State.TargetX,
			TargetZ = Agent.State.TargetZ,
			ShouldStop = true,
			Priority = 3,
		}
	end

	local BoatPosition = Agent.PrimaryPart.Position
	local DetectionRange = Agent.Config.AttackDetectionRange or DETECTION_RANGE
	local CircleRadius = Agent.Config.AttackCircleRadius or CIRCLE_RADIUS
	local AutoTarget = Agent.Config.AttackAutoTarget

	if not AttackData.Target or not AttackData.TargetPart or not AttackData.TargetPart.Parent then
		if AutoTarget then
			local NewTarget, NewPart = FindNearestTarget(Agent, DetectionRange)
			if NewTarget then
				AttackData.Target = NewTarget
				AttackData.TargetPart = NewPart
				AttackData.TargetStationaryTime = 0
				AttackData.LastTargetPosition = nil
				AttackData.LastTargetVelocity = nil
				State.AttackState = "PURSUING"
			else
				return {
					TargetX = BoatPosition.X,
					TargetZ = BoatPosition.Z,
					ThrottleOverride = 0.3,
					ShouldStop = false,
					ObstacleAvoidanceMultiplier = 1.0,
					Priority = 3,
				}
			end
		else
			return {
				TargetX = BoatPosition.X,
				TargetZ = BoatPosition.Z,
				ShouldStop = true,
				Priority = 3,
			}
		end
	end

	local TargetPosition = AttackData.TargetPart.Position
	local DistanceToTarget = (Vector3.new(TargetPosition.X, 0, TargetPosition.Z) - Vector3.new(BoatPosition.X, 0, BoatPosition.Z)).Magnitude

	if DistanceToTarget > LOSE_TARGET_RANGE then
		AttackData.Target = nil
		AttackData.TargetPart = nil
		return {
			TargetX = BoatPosition.X,
			TargetZ = BoatPosition.Z,
			ThrottleOverride = 0.3,
			ShouldStop = false,
			ObstacleAvoidanceMultiplier = 1.0,
			Priority = 3,
		}
	end

	local TargetVelocity = EstimateTargetVelocity(AttackData, TargetPosition, DeltaTime)
	local TargetSpeed = TargetVelocity.Magnitude

	if TargetSpeed < TARGET_STATIONARY_SPEED then
		AttackData.TargetStationaryTime = AttackData.TargetStationaryTime + DeltaTime
	else
		AttackData.TargetStationaryTime = 0
		State.AttackState = "PURSUING"
	end

	local TargetX: number
	local TargetZ: number
	local ThrottleOverride: number?

	if AttackData.TargetStationaryTime >= TARGET_STATIONARY_TIME then
		State.AttackState = "CIRCLING"

		AttackData.CircleAngle = AttackData.CircleAngle + (CIRCLE_ANGULAR_SPEED * AttackData.CircleDirection * DeltaTime)

		if AttackData.CircleAngle > math.pi * 2 then
			AttackData.CircleAngle = AttackData.CircleAngle - math.pi * 2
		elseif AttackData.CircleAngle < 0 then
			AttackData.CircleAngle = AttackData.CircleAngle + math.pi * 2
		end

		local CirclePosition = CalculateCirclePosition(TargetPosition, AttackData.CircleAngle, CircleRadius)
		TargetX = CirclePosition.X
		TargetZ = CirclePosition.Z
		ThrottleOverride = CIRCLE_THROTTLE

	else
		State.AttackState = "PURSUING"

		local PredictionTime = math.clamp(DistanceToTarget / 30, 0, 3)
		local PredictedPosition = TargetPosition + TargetVelocity * PredictionTime

		TargetX = PredictedPosition.X
		TargetZ = PredictedPosition.Z
		ThrottleOverride = PURSUIT_THROTTLE
	end

	Agent.State.TargetX = TargetX
	Agent.State.TargetZ = TargetZ

	Agent.BoatModel:SetAttribute("AttackState", State.AttackState)
	Agent.BoatModel:SetAttribute("TargetDistance", math.floor(DistanceToTarget))

	return {
		TargetX = TargetX,
		TargetZ = TargetZ,
		ThrottleOverride = ThrottleOverride,
		SteerOverride = nil,
		ShouldStop = false,
		ObstacleAvoidanceMultiplier = 0.7,
		DockingTarget = nil,
		Priority = 3,
	}
end

return BehaviorAttack