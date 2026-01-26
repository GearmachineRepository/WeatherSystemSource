--!strict
--[[
    MovingSurface
    Keeps the player anchored to CFrame-manipulated surfaces (boats, platforms, etc.)

    Place in: StarterPlayer/StarterCharacterScripts

    How it works:
    1. Raycasts downward to detect what the player is standing on
    2. If standing on a tagged "MovingSurface" part (or descendant of tagged Model)
    3. Calculates how much the surface MOVED since last frame
    4. Applies that same movement delta to the player's current position

    This allows the player to walk freely while still moving with the surface.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local MOVING_SURFACE_TAG = "MovingSurface"
local RAYCAST_DISTANCE = 15
local RAYCAST_ORIGIN_OFFSET = Vector3.new(0, 1, 0)
local RENDER_STEP_NAME = "MovingSurfaceUpdate"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value - 1

local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
local RootPart = Character:WaitForChild("HumanoidRootPart") :: BasePart

local RaycastParameters = RaycastParams.new()
RaycastParameters.FilterType = Enum.RaycastFilterType.Exclude
RaycastParameters.FilterDescendantsInstances = { Character }

local PreviousSurfacePart: BasePart? = nil
local PreviousSurfaceCFrame: CFrame? = nil

--[[
    Check if a part or any of its ancestors is tagged as a MovingSurface.
]]
local function IsMovingSurface(Part: BasePart): boolean
	if CollectionService:HasTag(Part, MOVING_SURFACE_TAG) then
		return true
	end

	local Current: Instance? = Part.Parent
	while Current do
		if CollectionService:HasTag(Current, MOVING_SURFACE_TAG) then
			return true
		end
		Current = Current.Parent
	end

	return false
end

--[[
    Get the "anchor" part for a moving surface.
    If the part itself is tagged, use it.
    If an ancestor Model is tagged, use the Model's PrimaryPart or the hit part.
]]
local function GetAnchorPart(HitPart: BasePart): BasePart
	if CollectionService:HasTag(HitPart, MOVING_SURFACE_TAG) then
		return HitPart
	end

	local Current: Instance? = HitPart.Parent
	while Current do
		if CollectionService:HasTag(Current, MOVING_SURFACE_TAG) then
			if Current:IsA("Model") and (Current :: Model).PrimaryPart then
				return (Current :: Model).PrimaryPart :: BasePart
			end
			return HitPart
		end
		Current = Current.Parent
	end

	return HitPart
end

--[[
    Perform a raycast to find what the player is standing on.
]]
local function GetSurfaceBelow(): BasePart?
	local Origin = RootPart.Position + RAYCAST_ORIGIN_OFFSET
	local Direction = Vector3.new(0, -RAYCAST_DISTANCE, 0)

	local Result = workspace:Raycast(Origin, Direction, RaycastParameters)

	if Result then
		return Result.Instance :: BasePart
	end

	return nil
end

--[[
    Main update loop - runs every frame before camera updates.
]]
local function OnRenderStep(): ()
	if Humanoid.Health <= 0 then
		return
	end

	if Humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return
	end

	local HitPart = GetSurfaceBelow()

	if not HitPart or not IsMovingSurface(HitPart) then
		PreviousSurfacePart = nil
		PreviousSurfaceCFrame = nil
		return
	end

	local AnchorPart = GetAnchorPart(HitPart)
	local CurrentAnchorCFrame = AnchorPart.CFrame

	if AnchorPart == PreviousSurfacePart and PreviousSurfaceCFrame then
		local SurfaceDelta = CurrentAnchorCFrame * PreviousSurfaceCFrame:Inverse()

		local DeltaPosition = SurfaceDelta.Position
		local HasMoved = DeltaPosition.Magnitude > 0.001

		local _, _, DeltaYaw = SurfaceDelta:ToEulerAnglesYXZ()
		local HasRotated = math.abs(DeltaYaw) > 0.0001

		if HasMoved or HasRotated then
			local CurrentPlayerCFrame = RootPart.CFrame
			local NewPlayerCFrame = SurfaceDelta * CurrentPlayerCFrame
			RootPart.CFrame = NewPlayerCFrame
		end
	end

	PreviousSurfacePart = AnchorPart
	PreviousSurfaceCFrame = CurrentAnchorCFrame
end

local function Start(): ()
	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, OnRenderStep)
end

local function Stop(): ()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	PreviousSurfacePart = nil
	PreviousSurfaceCFrame = nil
end

Humanoid.Died:Connect(Stop)

Character.AncestryChanged:Connect(function(_, Parent)
	if not Parent then
		Stop()
	end
end)

Start()