--[[
    BoatBuoyancy
    Makes boats float and tilt realistically on waves.

    Setup your boat model:
    1. Create a Model with a PrimaryPart (the main hull)
    2. Add a Folder called "Buoys" containing Parts at these positions:
       - "Bow" (front of boat)
       - "Stern" (back of boat)
       - "Port" (left side)
       - "Starboard" (right side)
       - Optional: More parts for better height averaging
    3. The buoy parts can be small and invisible (Transparency = 1)

    Usage:
        local BoatBuoyancy = require(path.to.BoatBuoyancy)
        local Controller = BoatBuoyancy.new(BoatModel, HeightSampler)
        Controller:Start()
]]

local RunService = game:GetService("RunService")

local WaveConfig = require(script.Parent.Parent.Shared.WaveConfig)

local BoatBuoyancy = {}
BoatBuoyancy.__index = BoatBuoyancy

--[[
    Create a new BoatBuoyancy controller.

    Parameters:
        BoatModel: Model - The boat model with buoy parts
        HeightSampler: WaveHeightSampler - The wave height sampler instance

    Returns:
        BoatBuoyancy instance
]]
function BoatBuoyancy.new(BoatModel, HeightSampler)
	local self = setmetatable({}, BoatBuoyancy)

	self.Model = BoatModel
	self.HeightSampler = HeightSampler
	self.Running = false
	self.Connection = nil
	self.CleanupConnection = nil  -- Add this

	self.HeightOffset = 0
	self.Smoothing = 0.15

	self.CurrentHeight = 0
	self.CurrentPitch = 0
	self.CurrentRoll = 0

	self:_FindBuoys()

	-- Auto-cleanup when model is destroyed
	self.CleanupConnection = BoatModel.AncestryChanged:Connect(function(_, Parent)
		if not Parent then
			self:Destroy()
		end
	end)

	return self
end

--[[
    Find and store references to buoy parts.
]]
function BoatBuoyancy:_FindBuoys()
    local BuoysFolder = self.Model:FindFirstChild("Buoys")

    if not BuoysFolder then
        warn("[BoatBuoyancy] No 'Buoys' folder found in boat model. Creating default buoys.")
        self:_CreateDefaultBuoys()
        BuoysFolder = self.Model:FindFirstChild("Buoys")
    end

    -- Move this AFTER potential creation of default buoys
    self.Bow = BuoysFolder:FindFirstChild("Bow")
    self.Stern = BuoysFolder:FindFirstChild("Stern")
    self.Port = BuoysFolder:FindFirstChild("Port")
    self.Starboard = BuoysFolder:FindFirstChild("Starboard")

    self.AllBuoys = {}
    for _, Child in pairs(BuoysFolder:GetChildren()) do
        if Child:IsA("BasePart") then
            table.insert(self.AllBuoys, Child)
        end
    end

	-- Validate required buoys
	if not (self.Bow and self.Stern and self.Port and self.Starboard) then
		warn("[BoatBuoyancy] Missing required buoys (Bow, Stern, Port, Starboard)")
	end
end

--[[
    Create default buoys based on the model's bounding box.
]]
function BoatBuoyancy:_CreateDefaultBuoys()
	local PrimaryPart = self.Model.PrimaryPart
	if not PrimaryPart then
		warn("[BoatBuoyancy] No PrimaryPart set on boat model")
		return
	end

	local Size = PrimaryPart.Size
	local HalfX = Size.X / 2 * 0.8
	local HalfZ = Size.Z / 2 * 0.8

	local BuoysFolder = Instance.new("Folder")
	BuoysFolder.Name = "Buoys"
	BuoysFolder.Parent = self.Model

	local function CreateBuoy(Name, Offset)
		local Buoy = Instance.new("Part")
		Buoy.Name = Name
		Buoy.Size = Vector3.new(1, 1, 1)
		Buoy.Transparency = 1
		Buoy.CanCollide = false
		Buoy.Anchored = false
		Buoy.Massless = true
		Buoy.CFrame = PrimaryPart.CFrame * CFrame.new(Offset)
		Buoy.Parent = BuoysFolder

		local Weld = Instance.new("WeldConstraint")
		Weld.Part0 = PrimaryPart
		Weld.Part1 = Buoy
		Weld.Parent = Buoy

		return Buoy
	end

	CreateBuoy("Bow", Vector3.new(0, 0, -HalfZ))
	CreateBuoy("Stern", Vector3.new(0, 0, HalfZ))
	CreateBuoy("Port", Vector3.new(-HalfX, 0, 0))
	CreateBuoy("Starboard", Vector3.new(HalfX, 0, 0))
end

--[[
    Calculate the average wave height at all buoy positions.

    Returns:
        number - Average wave height
]]
function BoatBuoyancy:_CalculateAverageHeight()
	if #self.AllBuoys == 0 then
		return WaveConfig.BaseWaterHeight
	end

	local TotalHeight = 0

	for _, Buoy in ipairs(self.AllBuoys) do
		local Pos = Buoy.Position
		local Height = self.HeightSampler:GetHeight(Pos.X, Pos.Z)
		TotalHeight = TotalHeight + Height
	end

	return TotalHeight / #self.AllBuoys
end

--[[
    Calculate the pitch angle (front-to-back tilt).

    Returns:
        number - Pitch angle in radians
]]
function BoatBuoyancy:_CalculatePitch()
	if not (self.Bow and self.Stern) then return 0 end

	local BowPos = self.Bow.Position
	local SternPos = self.Stern.Position

	local BowHeight = self.HeightSampler:GetHeight(BowPos.X, BowPos.Z)
	local SternHeight = self.HeightSampler:GetHeight(SternPos.X, SternPos.Z)

	local Distance = (Vector2.new(BowPos.X, BowPos.Z) - Vector2.new(SternPos.X, SternPos.Z)).Magnitude

	if Distance < 0.01 then return 0 end

	local HeightDiff = BowHeight - SternHeight

	return math.atan2(HeightDiff, Distance)
end

--[[
    Calculate the roll angle (side-to-side tilt).

    Returns:
        number - Roll angle in radians
]]
function BoatBuoyancy:_CalculateRoll()
	if not (self.Port and self.Starboard) then return 0 end

	local PortPos = self.Port.Position
	local StarboardPos = self.Starboard.Position

	local PortHeight = self.HeightSampler:GetHeight(PortPos.X, PortPos.Z)
	local StarboardHeight = self.HeightSampler:GetHeight(StarboardPos.X, StarboardPos.Z)

	local Distance = (Vector2.new(PortPos.X, PortPos.Z) - Vector2.new(StarboardPos.X, StarboardPos.Z)).Magnitude

	if Distance < 0.01 then return 0 end

	local HeightDiff = StarboardHeight - PortHeight

	return math.atan2(HeightDiff, Distance)
end

--[[
    Lerp helper function.
]]
local function Lerp(A, B, T)
	return A + (B - A) * T
end

--[[
    Update the boat's position and rotation.
]]
function BoatBuoyancy:_Update(DeltaTime)
	local PrimaryPart = self.Model.PrimaryPart
	if not PrimaryPart then return end

	-- Calculate target values
	local TargetHeight = self:_CalculateAverageHeight() + self.HeightOffset
	local TargetPitch = self:_CalculatePitch()
	local TargetRoll = self:_CalculateRoll()

	-- Smooth the values
	local SmoothFactor = math.min(self.Smoothing * DeltaTime * 60, 1)
	self.CurrentHeight = Lerp(self.CurrentHeight, TargetHeight, SmoothFactor)
	self.CurrentPitch = Lerp(self.CurrentPitch, TargetPitch, SmoothFactor)
	self.CurrentRoll = Lerp(self.CurrentRoll, TargetRoll, SmoothFactor)

	-- Get current position and look direction
	local CurrentCFrame = PrimaryPart.CFrame
	local Position = CurrentCFrame.Position
	local LookVector = CurrentCFrame.LookVector

	-- Flatten the look vector (keep heading, remove vertical component)
	local FlatLook = Vector3.new(LookVector.X, 0, LookVector.Z)
	if FlatLook.Magnitude < 0.01 then
		FlatLook = Vector3.new(0, 0, -1)
	else
		FlatLook = FlatLook.Unit
	end

	-- Build new CFrame
	local NewPosition = Vector3.new(Position.X, self.CurrentHeight, Position.Z)
	local NewCFrame = CFrame.new(NewPosition, NewPosition + FlatLook)

	-- Apply pitch and roll
	NewCFrame = NewCFrame * CFrame.Angles(self.CurrentPitch, 0, self.CurrentRoll)

	-- Apply to model
	self.Model:PivotTo(NewCFrame)
end

--[[
    Start the buoyancy simulation.
]]
function BoatBuoyancy:Start()
	if self.Running then
		warn("[BoatBuoyancy] Already running")
		return
	end

	self.Running = true

	-- Initialize current values
	self.CurrentHeight = self:_CalculateAverageHeight() + self.HeightOffset
	self.CurrentPitch = 0
	self.CurrentRoll = 0

	self.Connection = RunService.RenderStepped:Connect(function(DeltaTime)
		self:_Update(DeltaTime)
	end)
end

--[[
    Stop the buoyancy simulation.
]]
function BoatBuoyancy:Stop()
	if not self.Running then return end

	self.Running = false

	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

--Controller:SetHeightOffset(2)   -- Float higher
--Controller:SetHeightOffset(-1)  -- Sit lower in water

--[[
    Set the height offset (how high above waves the boat floats).

    Parameters:
        Offset: number
]]
function BoatBuoyancy:SetHeightOffset(Offset)
	self.HeightOffset = Offset
end

--Controller:SetSmoothing(0.05)  -- Smoother, slower response
--Controller:SetSmoothing(0.2)   -- Snappier, more reactive

--[[
    Set the smoothing factor.

    Parameters:
        Smoothing: number (0-1, lower = smoother)
]]
function BoatBuoyancy:SetSmoothing(Smoothing)
	self.Smoothing = math.clamp(Smoothing, 0.01, 1)
end

--[[
    Clean up all connections and references.
]]
function BoatBuoyancy:Destroy()
	self:Stop()

	if self.CleanupConnection then
		self.CleanupConnection:Disconnect()
		self.CleanupConnection = nil
	end

	self.Model = nil
	self.HeightSampler = nil
	self.Bow = nil
	self.Stern = nil
	self.Port = nil
	self.Starboard = nil
	self.AllBuoys = {}
end

return BoatBuoyancy