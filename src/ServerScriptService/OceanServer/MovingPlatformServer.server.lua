--!strict

local CollectionService = game:GetService("CollectionService")

local BOAT_TAG = "Boat"
local MOVING_SURFACE_TAG = "MovingSurface"

local function TagBoat(BoatModel: Model): ()
	CollectionService:AddTag(BoatModel, MOVING_SURFACE_TAG)
end

local function SetupExistingBoats(): ()
	for _, Boat in CollectionService:GetTagged(BOAT_TAG) do
		if Boat:IsA("Model") then
			TagBoat(Boat)
		end
	end

	local BoatsFolder = workspace:FindFirstChild("Boats")
	if BoatsFolder then
		for _, Child in BoatsFolder:GetChildren() do
			if Child:IsA("Model") and Child.PrimaryPart then
				if not CollectionService:HasTag(Child, MOVING_SURFACE_TAG) then
					TagBoat(Child)
				end
			end
		end
	end
end

CollectionService:GetInstanceAddedSignal(BOAT_TAG):Connect(function(Instance)
	if Instance:IsA("Model") then
		TagBoat(Instance)
	end
end)

SetupExistingBoats()