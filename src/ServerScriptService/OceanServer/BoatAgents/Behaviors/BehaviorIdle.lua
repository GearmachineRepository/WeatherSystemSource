--!strict

local BehaviorTypes = require(script.Parent:WaitForChild("BehaviorTypes"))

local BehaviorIdle = {}

function BehaviorIdle.Initialize(Agent: any, _Config: any?)
	local State = Agent.State.BehaviorState
	State.Name = "Idle"
	State.CurrentWaypointIndex = 0
	State.RouteData = nil

	local BoatPosition = Agent.PrimaryPart.Position
	Agent.State.TargetX = BoatPosition.X
	Agent.State.TargetZ = BoatPosition.Z
end

function BehaviorIdle.Update(Agent: any, _DeltaTime: number): BehaviorTypes.BehaviorOutput
	local BoatPosition = Agent.PrimaryPart.Position

	return {
		TargetX = BoatPosition.X,
		TargetZ = BoatPosition.Z,
		ThrottleOverride = 0,
		SteerOverride = 0,
		ShouldStop = true,
		ObstacleAvoidanceMultiplier = 0,
		DockingTarget = nil,
		Priority = 0,
	}
end

return BehaviorIdle