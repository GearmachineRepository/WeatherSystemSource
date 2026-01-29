--!strict

local BoatAgentDebug = {}

local RAY_LIFETIME = 0.08
local VECTOR_LIFETIME = 0.08
local WAYPOINT_LIFETIME = 0.08

local COLOR_CLEAR = Color3.fromRGB(0, 255, 0)
local COLOR_BLOCKED = Color3.fromRGB(255, 0, 0)
local COLOR_OBSTACLE_VECTOR = Color3.fromRGB(255, 165, 0)
local COLOR_SEPARATION = Color3.fromRGB(255, 0, 255)
local COLOR_WAYPOINT = Color3.fromRGB(0, 200, 255)
local COLOR_FORWARD = Color3.fromRGB(255, 255, 255)
local COLOR_DESIRED = Color3.fromRGB(255, 255, 0)

local DebugFolder: Folder? = nil

local function GetOrCreateDebugFolder(): Folder
	if DebugFolder and DebugFolder.Parent then
		return DebugFolder
	end

	local Existing = workspace:FindFirstChild("BoatAgentDebug")
	if Existing and Existing:IsA("Folder") then
		DebugFolder = Existing
		return Existing
	end

	local NewFolder = Instance.new("Folder")
	NewFolder.Name = "BoatAgentDebug"
	NewFolder.Parent = workspace
	DebugFolder = NewFolder
	return NewFolder
end

local function CreateRayPart(Origin: Vector3, Direction: Vector3, Distance: number, PartColor: Color3, Lifetime: number)
	local Folder = GetOrCreateDebugFolder()

	local EndPoint = Origin + Direction * Distance
	local MidPoint = (Origin + EndPoint) / 2

	local Part = Instance.new("Part")
	Part.Anchored = true
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.CastShadow = false
	Part.Size = Vector3.new(0.15, 0.15, Distance)
	Part.CFrame = CFrame.lookAt(MidPoint, EndPoint)
	Part.Color = PartColor
	Part.Material = Enum.Material.Neon
	Part.Transparency = 0.3
	Part.Parent = Folder

	task.delay(Lifetime, function()
		Part:Destroy()
	end)
end

local function CreateSphere(Position: Vector3, Radius: number, SphereColor: Color3, Lifetime: number)
	local Folder = GetOrCreateDebugFolder()

	local Part = Instance.new("Part")
	Part.Shape = Enum.PartType.Ball
	Part.Anchored = true
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.CastShadow = false
	Part.Size = Vector3.one * Radius * 2
	Part.Position = Position
	Part.Color = SphereColor
	Part.Material = Enum.Material.Neon
	Part.Transparency = 0.5
	Part.Parent = Folder

	task.delay(Lifetime, function()
		Part:Destroy()
	end)
end

local function LerpColor(ColorA: Color3, ColorB: Color3, Alpha: number): Color3
	local ClampedAlpha = math.clamp(Alpha, 0, 1)
	return Color3.new(
		ColorA.R + (ColorB.R - ColorA.R) * ClampedAlpha,
		ColorA.G + (ColorB.G - ColorA.G) * ClampedAlpha,
		ColorA.B + (ColorB.B - ColorA.B) * ClampedAlpha
	)
end

function BoatAgentDebug.DrawRayWithScore(
	Origin: Vector3,
	Direction: Vector3,
	Distance: number,
	ClearScore: number,
	DidHit: boolean,
	HitPosition: Vector3?
)
	local RayColor = LerpColor(COLOR_BLOCKED, COLOR_CLEAR, ClearScore)

	if DidHit and HitPosition then
		local HitDistance = (HitPosition - Origin).Magnitude
		CreateRayPart(Origin, Direction, HitDistance, RayColor, RAY_LIFETIME)
		CreateSphere(HitPosition, 0.5, COLOR_BLOCKED, RAY_LIFETIME)
	else
		CreateRayPart(Origin, Direction, Distance, RayColor, RAY_LIFETIME)
	end
end

function BoatAgentDebug.DrawObstacleVector(Position: Vector3, ObstacleVector: Vector3)
	local Magnitude = ObstacleVector.Magnitude
	if Magnitude < 0.001 then
		return
	end

	local DrawOrigin = Position + Vector3.new(0, 5, 0)
	local DrawLength = math.min(Magnitude * 10, 20)
	local NormalizedDirection = ObstacleVector / Magnitude

	CreateRayPart(DrawOrigin, NormalizedDirection, DrawLength, COLOR_OBSTACLE_VECTOR, VECTOR_LIFETIME)
end

function BoatAgentDebug.DrawSeparationVector(Position: Vector3, SeparationVector: Vector3)
	local Magnitude = SeparationVector.Magnitude
	if Magnitude < 0.1 then
		return
	end

	local DrawOrigin = Position + Vector3.new(0, 6, 0)
	local DrawLength = math.min(Magnitude * 5, 15)
	local NormalizedDirection = SeparationVector / Magnitude

	CreateRayPart(DrawOrigin, NormalizedDirection, DrawLength, COLOR_SEPARATION, VECTOR_LIFETIME)
end

function BoatAgentDebug.DrawWaypoint(BoatPosition: Vector3, TargetX: number, TargetZ: number)
	local TargetPosition = Vector3.new(TargetX, BoatPosition.Y + 2, TargetZ)
	CreateSphere(TargetPosition, 2, COLOR_WAYPOINT, WAYPOINT_LIFETIME)
end

function BoatAgentDebug.DrawForward(Position: Vector3, Forward: Vector3)
	local DrawOrigin = Position + Vector3.new(0, 4, 0)
	CreateRayPart(DrawOrigin, Forward, 8, COLOR_FORWARD, VECTOR_LIFETIME)
end

function BoatAgentDebug.DrawDesiredDirection(Position: Vector3, DesiredDirection: Vector3)
	local Magnitude = DesiredDirection.Magnitude
	if Magnitude < 0.001 then
		return
	end

	local DrawOrigin = Position + Vector3.new(0, 7, 0)
	local NormalizedDirection = DesiredDirection / Magnitude

	CreateRayPart(DrawOrigin, NormalizedDirection, 12, COLOR_DESIRED, VECTOR_LIFETIME)
end

return BoatAgentDebug