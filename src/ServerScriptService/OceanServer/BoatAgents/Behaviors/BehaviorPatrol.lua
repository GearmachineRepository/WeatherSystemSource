--!strict

local BehaviorTypes = require(script.Parent:WaitForChild("BehaviorTypes"))

local BehaviorPatrol = {}

local WAYPOINT_ARRIVAL_RADIUS = BehaviorTypes.PATROL_WAYPOINT_ARRIVAL_RADIUS

export type PatrolConfig = {
	RouteName: string?,
	RouteFolder: Folder?,
	Loop: boolean?,
}

local function LoadRouteFromFolder(RouteFolder: Folder): BehaviorTypes.RouteData
	local Waypoints: {BehaviorTypes.WaypointData} = {}

	local Children = RouteFolder:GetChildren()
	table.sort(Children, function(PartA, PartB)
		local NumA = tonumber(PartA.Name) or 999
		local NumB = tonumber(PartB.Name) or 999
		return NumA < NumB
	end)

	for _, Child in ipairs(Children) do
		if Child:IsA("BasePart") then
			local WaypointData = {
				Position = Child.Position,
				WaitTime = Child:GetAttribute("WaitTime"),
				IsEndpoint = Child:GetAttribute("IsEndpoint"),
				DepartureDelay = Child:GetAttribute("DepartureDelay"),
				DockPoint = nil,
			} :: BehaviorTypes.WaypointData

			local DockPointName = Child:GetAttribute("DockPoint")
			if DockPointName then
				local DocksFolder = workspace:FindFirstChild("Docks")
				if DocksFolder then
					local DockFolder = DocksFolder:FindFirstChild(DockPointName)
					if DockFolder then
						local DockPoint = DockFolder:FindFirstChild("DockPoint")
						if DockPoint and DockPoint:IsA("BasePart") then
							WaypointData.DockPoint = DockPoint
						end
					end
				end
			end

			table.insert(Waypoints, WaypointData)
		end
	end

	local Loop = RouteFolder:GetAttribute("Loop")
	if Loop == nil then
		Loop = true
	end

	return {
		Name = RouteFolder.Name,
		Waypoints = Waypoints,
		Loop = Loop,
	} :: BehaviorTypes.RouteData
end

local function FindRouteFolder(RouteName: string): Folder?
	local WaypointsFolder = workspace:FindFirstChild("Waypoints")
	if not WaypointsFolder then
		return nil
	end

	return WaypointsFolder:FindFirstChild(RouteName) :: Folder?
end

function BehaviorPatrol.Initialize(Agent: any, Config: PatrolConfig?)
	local State = Agent.State.BehaviorState
	State.Name = "Patrol"
	State.CurrentWaypointIndex = 1
	State.RouteDirection = 1

	local RouteFolder: Folder? = nil

	if Config then
		if Config.RouteFolder then
			RouteFolder = Config.RouteFolder
		elseif Config.RouteName then
			RouteFolder = FindRouteFolder(Config.RouteName)
		end
	end

	if not RouteFolder then
		local RouteName = Agent.BoatModel:GetAttribute("Route")
		if RouteName then
			RouteFolder = FindRouteFolder(RouteName)
		end
	end

	if RouteFolder then
		State.RouteData = LoadRouteFromFolder(RouteFolder)

		if Config and Config.Loop ~= nil then
			State.RouteData.Loop = Config.Loop
		end
	else
		State.RouteData = {
			Name = "Empty",
			Waypoints = {},
			Loop = true,
		}
		warn("[BehaviorPatrol] No route found for boat:", Agent.BoatModel:GetFullName())
	end

	BehaviorPatrol.UpdateTargetFromWaypoint(Agent)
end

function BehaviorPatrol.UpdateTargetFromWaypoint(Agent: any)
	local State = Agent.State.BehaviorState
	local RouteData = State.RouteData

	if not RouteData or #RouteData.Waypoints == 0 then
		return
	end

	local WaypointIndex = State.CurrentWaypointIndex
	WaypointIndex = math.clamp(WaypointIndex, 1, #RouteData.Waypoints)

	local Waypoint = RouteData.Waypoints[WaypointIndex]
	Agent.State.TargetX = Waypoint.Position.X
	Agent.State.TargetZ = Waypoint.Position.Z
end

function BehaviorPatrol.AdvanceWaypoint(Agent: any): boolean
	local State = Agent.State.BehaviorState
	local RouteData = State.RouteData

	if not RouteData or #RouteData.Waypoints == 0 then
		return false
	end

	local WaypointCount = #RouteData.Waypoints
	local CurrentIndex = State.CurrentWaypointIndex
	local Direction = State.RouteDirection

	local NextIndex = CurrentIndex + Direction

	if RouteData.Loop then
		if NextIndex > WaypointCount then
			NextIndex = 1
		elseif NextIndex < 1 then
			NextIndex = WaypointCount
		end
	else
		if NextIndex > WaypointCount or NextIndex < 1 then
			State.RouteDirection = -Direction
			NextIndex = CurrentIndex + State.RouteDirection
		end
	end

	State.CurrentWaypointIndex = NextIndex
	BehaviorPatrol.UpdateTargetFromWaypoint(Agent)

	return true
end

function BehaviorPatrol.GetCurrentWaypoint(Agent: any): BehaviorTypes.WaypointData?
	local State = Agent.State.BehaviorState
	local RouteData = State.RouteData

	if not RouteData or #RouteData.Waypoints == 0 then
		return nil
	end

	local WaypointIndex = math.clamp(State.CurrentWaypointIndex, 1, #RouteData.Waypoints)
	return RouteData.Waypoints[WaypointIndex]
end

function BehaviorPatrol.Update(Agent: any, _DeltaTime: number): BehaviorTypes.BehaviorOutput
	local BoatPosition = Agent.PrimaryPart.Position
	local DeltaX = Agent.State.TargetX - BoatPosition.X
	local DeltaZ = Agent.State.TargetZ - BoatPosition.Z
	local Distance = math.sqrt(DeltaX * DeltaX + DeltaZ * DeltaZ)

	if Distance <= WAYPOINT_ARRIVAL_RADIUS then
		BehaviorPatrol.AdvanceWaypoint(Agent)
	end

	return {
		TargetX = Agent.State.TargetX,
		TargetZ = Agent.State.TargetZ,
		ThrottleOverride = nil,
		SteerOverride = nil,
		ShouldStop = false,
		ObstacleAvoidanceMultiplier = 1.0,
		WaypointBias = 0.6,
		DockingTarget = nil,
		Priority = 2,
	}
end

return BehaviorPatrol