--!strict

local Players = game:GetService("Players")

local BehaviorTypes = require(script.Parent:WaitForChild("BehaviorTypes"))
local BehaviorPatrol = require(script.Parent:WaitForChild("BehaviorPatrol"))

local BehaviorFerry = {}

local DEFAULT_WAIT_TIME = BehaviorTypes.FERRY_DEFAULT_WAIT_TIME
local DEPARTURE_DELAY = BehaviorTypes.FERRY_DEPARTURE_DELAY
local MIN_PASSENGERS_TO_DEPART = BehaviorTypes.FERRY_MIN_PASSENGERS_TO_DEPART
local WAYPOINT_ARRIVAL_RADIUS = BehaviorTypes.PATROL_WAYPOINT_ARRIVAL_RADIUS
local DEFAULT_APPROACH_DISTANCE = BehaviorTypes.DEFAULT_APPROACH_DISTANCE

export type FerryConfig = {
	RouteName: string?,
	RouteFolder: Folder?,
	WaitTime: number?,
	DepartureDelay: number?,
	MinPassengers: number?,
}

local function CountPassengersInZone(Agent: any): number
	local Zone = Agent.BoatModel:FindFirstChild("Zone")
	if not Zone or not Zone:IsA("BasePart") then
		return 0
	end

	local Count = 0
	local _ZonePosition = Zone.Position
	local ZoneSize = Zone.Size

	local HalfX = ZoneSize.X * 0.5
	local HalfY = ZoneSize.Y * 0.5
	local HalfZ = ZoneSize.Z * 0.5

	for _, Player in ipairs(Players:GetPlayers()) do
		local Character = Player.Character
		if Character then
			local RootPart = Character:FindFirstChild("HumanoidRootPart")
			if RootPart and RootPart:IsA("BasePart") then
				local RelativePosition = Zone.CFrame:PointToObjectSpace(RootPart.Position)

				if math.abs(RelativePosition.X) <= HalfX and
				   math.abs(RelativePosition.Y) <= HalfY and
				   math.abs(RelativePosition.Z) <= HalfZ then
					Count = Count + 1
				end
			end
		end
	end

	return Count
end

function BehaviorFerry.Initialize(Agent: any, Config: FerryConfig?)
	BehaviorPatrol.Initialize(Agent, {
		RouteName = Config and Config.RouteName,
		RouteFolder = Config and Config.RouteFolder,
		Loop = false,
	})

	local State = Agent.State.BehaviorState
	State.Name = "Ferry"
	State.FerryState = "TRAVELING"

	local FerryData: BehaviorTypes.FerryPassengerData = {
		WaitStartTime = 0,
		DepartureTime = nil,
		PassengerCount = 0,
		AnnouncedDeparture = false,
	}

	State.FerryData = FerryData

	local WaitTime = DEFAULT_WAIT_TIME
	local DepartureDelay = DEPARTURE_DELAY
	local MinPassengers = MIN_PASSENGERS_TO_DEPART

	if Config then
		WaitTime = Config.WaitTime or WaitTime
		DepartureDelay = Config.DepartureDelay or DepartureDelay
		MinPassengers = Config.MinPassengers or MinPassengers
	end

	Agent.Config.FerryWaitTime = WaitTime
	Agent.Config.FerryDepartureDelay = DepartureDelay
	Agent.Config.FerryMinPassengers = MinPassengers

	Agent.BoatModel:SetAttribute("FerryState", "TRAVELING")
end

function BehaviorFerry.Update(Agent: any, DeltaTime: number): BehaviorTypes.BehaviorOutput
	local State = Agent.State.BehaviorState
	local FerryData = State.FerryData
	local DockingState = State.DockingState

	if not FerryData then
		return BehaviorPatrol.Update(Agent, DeltaTime)
	end

	local BoatPosition = Agent.PrimaryPart.Position
	local CurrentTime = os.clock()

	local WaitTime = Agent.Config.FerryWaitTime or DEFAULT_WAIT_TIME
	local DepartureDelay = Agent.Config.FerryDepartureDelay or DEPARTURE_DELAY
	local MinPassengers = Agent.Config.FerryMinPassengers or MIN_PASSENGERS_TO_DEPART

	FerryData.PassengerCount = CountPassengersInZone(Agent)
	Agent.BoatModel:SetAttribute("PassengerCount", FerryData.PassengerCount)

	if State.FerryState == "TRAVELING" then
		local DeltaX = Agent.State.TargetX - BoatPosition.X
		local DeltaZ = Agent.State.TargetZ - BoatPosition.Z
		local Distance = math.sqrt(DeltaX * DeltaX + DeltaZ * DeltaZ)

		local CurrentWaypoint = BehaviorPatrol.GetCurrentWaypoint(Agent)

		if CurrentWaypoint and CurrentWaypoint.DockPoint then
			if Distance <= DEFAULT_APPROACH_DISTANCE then
				State.FerryState = "APPROACHING_DOCK"
				Agent.BoatModel:SetAttribute("FerryState", "APPROACHING_DOCK")

				DockingState.Active = true
				DockingState.State = "APPROACHING"
				DockingState.DockPoint = CurrentWaypoint.DockPoint
				DockingState.ApproachDistance = DEFAULT_APPROACH_DISTANCE
			end
		elseif Distance <= WAYPOINT_ARRIVAL_RADIUS then
			BehaviorPatrol.AdvanceWaypoint(Agent)
		end

		return {
			TargetX = Agent.State.TargetX,
			TargetZ = Agent.State.TargetZ,
			ThrottleOverride = nil,
			ShouldStop = false,
			ObstacleAvoidanceMultiplier = 1.0,
			WaypointBias = 0.6,
			Priority = 2,
		}

	elseif State.FerryState == "APPROACHING_DOCK" then
		if DockingState.State == "ALIGNING" or DockingState.State == "DOCKING" then
			State.FerryState = "DOCKING"
			Agent.BoatModel:SetAttribute("FerryState", "DOCKING")
		end

		return {
			TargetX = Agent.State.TargetX,
			TargetZ = Agent.State.TargetZ,
			ThrottleOverride = 0.6,
			ShouldStop = false,
			ObstacleAvoidanceMultiplier = 0.3,
			DockingTarget = DockingState.DockPoint,
			Priority = 2,
		}

	elseif State.FerryState == "DOCKING" then
		if DockingState.State == "DOCKED" then
			State.FerryState = "WAITING"
			FerryData.WaitStartTime = CurrentTime
			FerryData.DepartureTime = nil
			FerryData.AnnouncedDeparture = false
			Agent.BoatModel:SetAttribute("FerryState", "WAITING")
		end

		return {
			TargetX = Agent.State.TargetX,
			TargetZ = Agent.State.TargetZ,
			ThrottleOverride = nil,
			ShouldStop = false,
			ObstacleAvoidanceMultiplier = 0,
			DockingTarget = DockingState.DockPoint,
			Priority = 2,
		}

	elseif State.FerryState == "WAITING" then
		local TimeWaited = CurrentTime - FerryData.WaitStartTime
		local TimeRemaining = WaitTime - TimeWaited

		Agent.BoatModel:SetAttribute("TimeRemaining", math.ceil(math.max(0, TimeRemaining)))

		local ShouldDepart = false

		if TimeRemaining <= 0 then
			ShouldDepart = true
		end

		if FerryData.PassengerCount >= MinPassengers and TimeWaited >= DepartureDelay then
			if not FerryData.AnnouncedDeparture then
				FerryData.AnnouncedDeparture = true
				FerryData.DepartureTime = CurrentTime + DepartureDelay
				Agent.BoatModel:SetAttribute("DepartureIn", DepartureDelay)
			end

			if FerryData.DepartureTime and CurrentTime >= FerryData.DepartureTime then
				ShouldDepart = true
			end
		end

		if ShouldDepart then
			State.FerryState = "DEPARTING"
			Agent.BoatModel:SetAttribute("FerryState", "DEPARTING")
		end

		return {
			TargetX = BoatPosition.X,
			TargetZ = BoatPosition.Z,
			ThrottleOverride = 0,
			SteerOverride = 0,
			ShouldStop = true,
			ObstacleAvoidanceMultiplier = 0,
			Priority = 2,
		}

	elseif State.FerryState == "DEPARTING" then
		DockingState.State = "UNDOCKING"
		State.FerryState = "UNDOCKING"
		Agent.BoatModel:SetAttribute("FerryState", "UNDOCKING")
		Agent.BoatModel:SetAttribute("DockingState", "UNDOCKING")

		return {
			TargetX = BoatPosition.X,
			TargetZ = BoatPosition.Z,
			ThrottleOverride = 0,
			ShouldStop = true,
			ObstacleAvoidanceMultiplier = 0,
			Priority = 2,
		}

	elseif State.FerryState == "UNDOCKING" then
		if not DockingState.Active or DockingState.State == nil then
			BehaviorPatrol.AdvanceWaypoint(Agent)
			State.FerryState = "TRAVELING"
			Agent.BoatModel:SetAttribute("FerryState", "TRAVELING")
		end

		return {
			TargetX = Agent.State.TargetX,
			TargetZ = Agent.State.TargetZ,
			ThrottleOverride = nil,
			ShouldStop = false,
			ObstacleAvoidanceMultiplier = 0,
			DockingTarget = DockingState.DockPoint,
			Priority = 2,
		}
	end

	return BehaviorPatrol.Update(Agent, DeltaTime)
end

return BehaviorFerry