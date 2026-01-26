--!strict
--[[
    TagBoatsForMovingSurface
    Server-side script that tags boats so the MovingSurface system works.

    Two options for tagging:
    1. Tag the entire boat Model - the system will use PrimaryPart as anchor
    2. Tag specific floor parts - useful if only certain parts should "stick" players

    You can also manually add tags in Studio via the Tag Editor plugin.
]]

local CollectionService = game:GetService("CollectionService")

local MOVING_SURFACE_TAG = "MovingSurface"

local function TagBoat(BoatModel: Model): ()
	CollectionService:AddTag(BoatModel, MOVING_SURFACE_TAG)
	print("[TagBoats] Tagged boat:", BoatModel:GetFullName())
end

local function SetupExistingBoats(): ()
	for _, Boat in pairs(CollectionService:GetTagged("Boat")) do
		if Boat:IsA("Model") then
			TagBoat(Boat)
		end
	end

	local BoatsFolder = workspace:FindFirstChild("Boats")
	if BoatsFolder then
		for _, Child in pairs(BoatsFolder:GetChildren()) do
			if Child:IsA("Model") and Child.PrimaryPart then
				if not CollectionService:HasTag(Child, MOVING_SURFACE_TAG) then
					TagBoat(Child)
				end
			end
		end
	end
end

CollectionService:GetInstanceAddedSignal("Boat"):Connect(function(Instance)
	if Instance:IsA("Model") then
		TagBoat(Instance)
	end
end)

SetupExistingBoats()