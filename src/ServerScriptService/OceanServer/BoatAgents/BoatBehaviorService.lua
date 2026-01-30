--!strict

local BoatBehaviorService = {}

local BehaviorsFolder: Folder? = nil
local BehaviorModules: {[string]: any} = {}
local ActiveAgentsRef: {[Model]: any}? = nil

local function GetBehaviorsFolder(): Folder?
	if BehaviorsFolder then
		return BehaviorsFolder
	end

	local BoatAgentsScript = script.Parent:FindFirstChild("BoatAgents")
	if BoatAgentsScript then
		BehaviorsFolder = BoatAgentsScript:FindFirstChild("Behaviors") :: Folder?
	end

	return BehaviorsFolder
end

local function GetBehaviorModule(BehaviorName: string): any?
	if BehaviorModules[BehaviorName] then
		return BehaviorModules[BehaviorName]
	end

	local Folder = GetBehaviorsFolder()
	if not Folder then
		return nil
	end

	local ModuleName = "Behavior" .. BehaviorName
	local Module = Folder:FindFirstChild(ModuleName)

	if Module and Module:IsA("ModuleScript") then
		local Success, Result = pcall(function()
			return require(Module) :: ModuleScript
		end)

		if Success then
			BehaviorModules[BehaviorName] = Result
			return Result
		else
			warn("[BoatBehaviorService] Failed to load behavior module:", ModuleName, Result)
		end
	end

	return nil
end

function BoatBehaviorService.Initialize(ActiveAgents: {[Model]: any}, BehaviorsFolderRef: Folder?)
	ActiveAgentsRef = ActiveAgents

	if BehaviorsFolderRef then
		BehaviorsFolder = BehaviorsFolderRef
	end
end

function BoatBehaviorService.GetAgent(BoatModel: Model): any?
	if not ActiveAgentsRef then
		return nil
	end

	return ActiveAgentsRef[BoatModel]
end

function BoatBehaviorService.SetBehavior(BoatModel: Model, BehaviorName: string, Config: any?): boolean
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		warn("[BoatBehaviorService] No agent found for boat:", BoatModel:GetFullName())
		return false
	end

	local BehaviorModule = GetBehaviorModule(BehaviorName)
	if not BehaviorModule then
		warn("[BoatBehaviorService] Unknown behavior:", BehaviorName)
		return false
	end

	if BehaviorModule.Initialize then
		BehaviorModule.Initialize(Agent, Config)
	end

	BoatModel:SetAttribute("Behavior", BehaviorName)

	return true
end

function BoatBehaviorService.SetRoute(BoatModel: Model, RouteName: string): boolean
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		warn("[BoatBehaviorService] No agent found for boat:", BoatModel:GetFullName())
		return false
	end

	local CurrentBehavior = Agent.State.BehaviorState.Name

	if CurrentBehavior == "Patrol" or CurrentBehavior == "Ferry" then
		local BehaviorModule = GetBehaviorModule(CurrentBehavior)
		if BehaviorModule and BehaviorModule.Initialize then
			BehaviorModule.Initialize(Agent, { RouteName = RouteName })
		end
	else
		BoatBehaviorService.SetBehavior(BoatModel, "Patrol", { RouteName = RouteName })
	end

	BoatModel:SetAttribute("Route", RouteName)

	return true
end

function BoatBehaviorService.SetAttackTarget(BoatModel: Model, Target: Model?): boolean
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		warn("[BoatBehaviorService] No agent found for boat:", BoatModel:GetFullName())
		return false
	end

	local CurrentBehavior = Agent.State.BehaviorState.Name

	if CurrentBehavior ~= "Attack" then
		BoatBehaviorService.SetBehavior(BoatModel, "Attack", { Target = Target, AutoTarget = Target == nil })
	else
		local BehaviorModule = GetBehaviorModule("Attack")
		if BehaviorModule and BehaviorModule.SetTarget then
			BehaviorModule.SetTarget(Agent, Target)
		end
	end

	return true
end

function BoatBehaviorService.SetAttackTargetPlayer(BoatModel: Model, Player: Player?): boolean
	if not Player then
		return BoatBehaviorService.SetAttackTarget(BoatModel, nil)
	end

	local Character = Player.Character
	if not Character then
		warn("[BoatBehaviorService] Player has no character:", Player.Name)
		return false
	end

	return BoatBehaviorService.SetAttackTarget(BoatModel, Character)
end

function BoatBehaviorService.StartDocking(BoatModel: Model, DockName: string): boolean
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		warn("[BoatBehaviorService] No agent found for boat:", BoatModel:GetFullName())
		return false
	end

	local DocksFolder = workspace:FindFirstChild("Docks")
	if not DocksFolder then
		warn("[BoatBehaviorService] No Docks folder found in workspace")
		return false
	end

	local DockFolder = DocksFolder:FindFirstChild(DockName)
	if not DockFolder then
		warn("[BoatBehaviorService] Dock not found:", DockName)
		return false
	end

	local DockPoint = DockFolder:FindFirstChild("DockPoint")
	if not DockPoint or not DockPoint:IsA("BasePart") then
		warn("[BoatBehaviorService] DockPoint not found in dock:", DockName)
		return false
	end

	local DockingState = Agent.State.BehaviorState.DockingState
	DockingState.Active = true
	DockingState.State = "APPROACHING"
	DockingState.DockPoint = DockPoint
	DockingState.ApproachDistance = DockPoint:GetAttribute("ApproachDistance") or 100

	BoatModel:SetAttribute("DockingState", "APPROACHING")

	return true
end

function BoatBehaviorService.StartUndocking(BoatModel: Model): boolean
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		warn("[BoatBehaviorService] No agent found for boat:", BoatModel:GetFullName())
		return false
	end

	local DockingState = Agent.State.BehaviorState.DockingState

	if not DockingState.Active or DockingState.State ~= "DOCKED" then
		warn("[BoatBehaviorService] Boat is not docked:", BoatModel:GetFullName())
		return false
	end

	DockingState.State = "UNDOCKING"
	BoatModel:SetAttribute("DockingState", "UNDOCKING")

	return true
end

function BoatBehaviorService.StopBoat(BoatModel: Model): boolean
	return BoatBehaviorService.SetBehavior(BoatModel, "Idle")
end

function BoatBehaviorService.ResumeWander(BoatModel: Model): boolean
	return BoatBehaviorService.SetBehavior(BoatModel, "Wander")
end

function BoatBehaviorService.GetBehaviorState(BoatModel: Model): string?
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		return nil
	end

	return Agent.State.BehaviorState.Name
end

function BoatBehaviorService.IsDocked(BoatModel: Model): boolean
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		return false
	end

	local DockingState = Agent.State.BehaviorState.DockingState
	return DockingState.Active and DockingState.State == "DOCKED"
end

function BoatBehaviorService.GetFerryState(BoatModel: Model): string?
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		return nil
	end

	return Agent.State.BehaviorState.FerryState
end

function BoatBehaviorService.GetAttackState(BoatModel: Model): string?
	local Agent = BoatBehaviorService.GetAgent(BoatModel)
	if not Agent then
		return nil
	end

	return Agent.State.BehaviorState.AttackState
end

function BoatBehaviorService.GetAllAgentBoats(): {Model}
	if not ActiveAgentsRef then
		return {}
	end

	local Boats: {Model} = {}
	for BoatModel, _ in pairs(ActiveAgentsRef) do
		table.insert(Boats, BoatModel)
	end

	return Boats
end

function BoatBehaviorService.GetBoatsByBehavior(BehaviorName: string): {Model}
	if not ActiveAgentsRef then
		return {}
	end

	local Boats: {Model} = {}
	for BoatModel, Agent in pairs(ActiveAgentsRef) do
		if Agent.State.BehaviorState.Name == BehaviorName then
			table.insert(Boats, BoatModel)
		end
	end

	return Boats
end

return BoatBehaviorService