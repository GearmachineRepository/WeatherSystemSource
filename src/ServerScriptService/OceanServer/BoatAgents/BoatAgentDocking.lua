--!strict

local BoatAgentTypes = require(script.Parent:WaitForChild("BoatAgentTypes"))
local BoatAgentUtils = require(script.Parent:WaitForChild("BoatAgentUtils"))

local BehaviorTypes = require(script.Parent:WaitForChild("Behaviors"):WaitForChild("BehaviorTypes"))

local BoatAgentDocking = {}

local DOCK_BUFFER = BehaviorTypes.DOCK_BUFFER
local DOCK_ALIGNMENT_THRESHOLD = BehaviorTypes.DOCK_ALIGNMENT_THRESHOLD
local DOCK_ARRIVAL_THRESHOLD = 8
local DOCK_ALIGN_THROTTLE = BehaviorTypes.DOCK_ALIGN_THROTTLE
local DOCK_APPROACH_THROTTLE = BehaviorTypes.DOCK_APPROACH_THROTTLE
local DOCK_UNDOCK_THROTTLE = BehaviorTypes.DOCK_UNDOCK_THROTTLE
local DOCK_STEER_CORRECTION_GAIN = BehaviorTypes.DOCK_STEER_CORRECTION_GAIN
local DOCK_MAX_STEER_CORRECTION = BehaviorTypes.DOCK_MAX_STEER_CORRECTION
local DEFAULT_APPROACH_DISTANCE = BehaviorTypes.DEFAULT_APPROACH_DISTANCE
local DOCK_OVERSHOOT_DOT_THRESHOLD = -0.3

local function CalculateFinalDockPosition(Agent: BoatAgentTypes.AgentData, DockPoint: BasePart): Vector3
	local BoatOffset = Agent.Geometry.BoundingLength * 0.5 + DOCK_BUFFER
	local DockPosition = DockPoint.Position
	local DockLookVector = DockPoint.CFrame.LookVector

	return Vector3.new(
		DockPosition.X + DockLookVector.X * BoatOffset,
		DockPosition.Y,
		DockPosition.Z + DockLookVector.Z * BoatOffset
	)
end

local function CalculateApproachPosition(DockPoint: BasePart, ApproachDistance: number): Vector3
	local DockPosition = DockPoint.Position
	local DockLookVector = DockPoint.CFrame.LookVector

	return Vector3.new(
		DockPosition.X + DockLookVector.X * ApproachDistance,
		DockPosition.Y,
		DockPosition.Z + DockLookVector.Z * ApproachDistance
	)
end

local function GetHorizontalAngleDifference(CurrentForward: Vector3, DesiredForward: Vector3): (number, number)
	local CrossY = CurrentForward.X * DesiredForward.Z - CurrentForward.Z * DesiredForward.X
	local DotForward = CurrentForward.X * DesiredForward.X + CurrentForward.Z * DesiredForward.Z
	local AngleRad = math.atan2(math.abs(CrossY), DotForward)
	local AngleDeg = math.deg(AngleRad)

	return AngleDeg, CrossY
end

function BoatAgentDocking.StartDocking(Agent: BoatAgentTypes.AgentData, DockPoint: BasePart, ApproachDistance: number?)
	local DockingState = Agent.State.BehaviorState.DockingState

	DockingState.Active = true
	DockingState.State = "APPROACHING"
	DockingState.DockPoint = DockPoint
	DockingState.ApproachDistance = ApproachDistance or DEFAULT_APPROACH_DISTANCE
	DockingState.FinalPosition = CalculateFinalDockPosition(Agent, DockPoint)
	DockingState.StartTime = os.clock()

	Agent.BoatModel:SetAttribute("DockingState", "APPROACHING")
end

function BoatAgentDocking.StartUndocking(Agent: BoatAgentTypes.AgentData)
	local DockingState = Agent.State.BehaviorState.DockingState

	if not DockingState.Active or DockingState.State ~= "DOCKED" then
		return
	end

	DockingState.State = "UNDOCKING"
	Agent.BoatModel:SetAttribute("DockingState", "UNDOCKING")
end

function BoatAgentDocking.CancelDocking(Agent: BoatAgentTypes.AgentData)
	local DockingState = Agent.State.BehaviorState.DockingState

	DockingState.Active = false
	DockingState.State = nil
	DockingState.DockPoint = nil
	DockingState.FinalPosition = nil

	Agent.BoatModel:SetAttribute("DockingState", "")
end

function BoatAgentDocking.IsDocked(Agent: BoatAgentTypes.AgentData): boolean
	local DockingState = Agent.State.BehaviorState.DockingState
	return DockingState.Active and DockingState.State == "DOCKED"
end

function BoatAgentDocking.IsDocking(Agent: BoatAgentTypes.AgentData): boolean
	local DockingState = Agent.State.BehaviorState.DockingState
	return DockingState.Active and DockingState.State ~= nil
end

function BoatAgentDocking.Update(Agent: BoatAgentTypes.AgentData, _DeltaTime: number): (number, number, boolean)
	local DockingState = Agent.State.BehaviorState.DockingState

	if not DockingState.Active or not DockingState.DockPoint then
		return 0, 0, false
	end

	local DockPoint = DockingState.DockPoint
	local BoatPosition = Agent.PrimaryPart.Position
	local CurrentForward = BoatAgentUtils.GetHorizontalLookVector(Agent.PrimaryPart)

	local DesiredForward = Vector3.new(-DockPoint.CFrame.LookVector.X, 0, -DockPoint.CFrame.LookVector.Z).Unit

	local Throttle = 0
	local Steer = 0
	local Handled = true

	if DockingState.State == "APPROACHING" then
		local ApproachPosition = CalculateApproachPosition(DockPoint, DockingState.ApproachDistance)
		local ToApproach = Vector3.new(ApproachPosition.X - BoatPosition.X, 0, ApproachPosition.Z - BoatPosition.Z)
		local DistanceToApproach = ToApproach.Magnitude

		if DistanceToApproach < 30 then
			DockingState.State = "ALIGNING"
			Agent.BoatModel:SetAttribute("DockingState", "ALIGNING")
		else
			local ToApproachNormalized = ToApproach / DistanceToApproach
			local _, CrossY = GetHorizontalAngleDifference(CurrentForward, ToApproachNormalized)

			Steer = math.clamp(CrossY * DOCK_STEER_CORRECTION_GAIN, -1, 1)
			Throttle = math.clamp(DistanceToApproach / 100, 0.4, 0.8)
		end

	elseif DockingState.State == "ALIGNING" then
		local AngleDeg, CrossY = GetHorizontalAngleDifference(CurrentForward, DesiredForward)

		if AngleDeg < DOCK_ALIGNMENT_THRESHOLD then
			DockingState.State = "DOCKING"
			Agent.BoatModel:SetAttribute("DockingState", "DOCKING")
		else
			Steer = math.sign(CrossY) * math.clamp(AngleDeg / 30, 0.3, 1)
			Throttle = DOCK_ALIGN_THROTTLE
		end

	elseif DockingState.State == "DOCKING" then
		local FinalPosition = DockingState.FinalPosition :: Vector3
		if not FinalPosition then
			FinalPosition = CalculateFinalDockPosition(Agent, DockPoint)
			DockingState.FinalPosition = FinalPosition
		end

		local ToFinal = Vector3.new(FinalPosition.X - BoatPosition.X, 0, FinalPosition.Z - BoatPosition.Z)
		local DistanceToFinal = ToFinal.Magnitude

		local ShouldDock = false

		if DistanceToFinal < DOCK_ARRIVAL_THRESHOLD then
			ShouldDock = true
		elseif DistanceToFinal < DOCK_ARRIVAL_THRESHOLD * 3 then
			local ToFinalNormalized = ToFinal.Unit
			local ForwardDot = CurrentForward:Dot(ToFinalNormalized)
			if ForwardDot < DOCK_OVERSHOOT_DOT_THRESHOLD then
				ShouldDock = true
			end
		end

		if ShouldDock then
			DockingState.State = "DOCKED"
			Agent.BoatModel:SetAttribute("DockingState", "DOCKED")
			Throttle = 0
			Steer = 0
		else
			local ToFinalNormalized = ToFinal / DistanceToFinal
			local _, CrossY = GetHorizontalAngleDifference(CurrentForward, ToFinalNormalized)

			Steer = math.clamp(CrossY * DOCK_STEER_CORRECTION_GAIN, -DOCK_MAX_STEER_CORRECTION, DOCK_MAX_STEER_CORRECTION)
			Throttle = math.clamp(DistanceToFinal / 50, 0.1, DOCK_APPROACH_THROTTLE)
		end

	elseif DockingState.State == "DOCKED" then
		Throttle = 0
		Steer = 0

	elseif DockingState.State == "UNDOCKING" then
		local DockPosition = DockPoint.Position
		local DistanceFromDock = (Vector3.new(DockPosition.X, 0, DockPosition.Z) - Vector3.new(BoatPosition.X, 0, BoatPosition.Z)).Magnitude

		if DistanceFromDock > DockingState.ApproachDistance then
			DockingState.Active = false
			DockingState.State = nil
			DockingState.DockPoint = nil
			DockingState.FinalPosition = nil
			Agent.BoatModel:SetAttribute("DockingState", "")
			Handled = false
		else
			Throttle = -DOCK_UNDOCK_THROTTLE
			Steer = 0
		end
	end

	return Throttle, Steer, Handled
end

return BoatAgentDocking