--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = Shared:WaitForChild("Weather")
local WeatherConfig = require(Weather:WaitForChild("WeatherConfig"))
local FrontManager = require(Weather:WaitForChild("FrontManager"))

local ZonesFolder = workspace:WaitForChild("Zones")

type ZoneData = {
	Name: string,
	Biome: string,
	Parts: { BasePart },
	Priority: number,
	Volume: number,
	Center: Vector3,
}

local Zones: { [string]: ZoneData } = {}
local LastTickTime = 0

local function CalculateVolume(Part: BasePart): number
	local Size = Part.Size
	return Size.X * Size.Y * Size.Z
end

local function CalculateZoneCenter(Parts: { BasePart }): Vector3
	if #Parts == 0 then
		return Vector3.zero
	end

	local TotalPosition = Vector3.zero
	local TotalVolume = 0

	for _, Part in ipairs(Parts) do
		local Volume = CalculateVolume(Part)
		TotalPosition = TotalPosition + Part.Position * Volume
		TotalVolume = TotalVolume + Volume
	end

	if TotalVolume > 0 then
		return TotalPosition / TotalVolume
	end

	return Parts[1].Position
end

local function InitializeZone(ZoneInstance: Instance): ZoneData?
	local ZoneName = ZoneInstance.Name
	local Biome: string
	local Parts: { BasePart } = {}
	local Priority = 0
	local TotalVolume = 0

	if ZoneInstance:IsA("Folder") then
		Biome = ZoneInstance:GetAttribute("Biome") or WeatherConfig.DEFAULT_BIOME
		Priority = ZoneInstance:GetAttribute("Priority") or 0

		for _, Child in ipairs(ZoneInstance:GetChildren()) do
			if Child:IsA("BasePart") then
				table.insert(Parts, Child)
				TotalVolume = TotalVolume + CalculateVolume(Child)
			end
		end
	elseif ZoneInstance:IsA("BasePart") then
		Biome = ZoneInstance:GetAttribute("Biome") or WeatherConfig.DEFAULT_BIOME
		Priority = ZoneInstance:GetAttribute("Priority") or 0
		table.insert(Parts, ZoneInstance)
		TotalVolume = CalculateVolume(ZoneInstance)
	else
		return nil
	end

	if #Parts == 0 then
		return nil
	end

	local Center = CalculateZoneCenter(Parts)

	return {
		Name = ZoneName,
		Biome = Biome,
		Parts = Parts,
		Priority = Priority,
		Volume = TotalVolume,
		Center = Center,
	}
end

local function SetZoneAttributes(ZoneInstance: Instance, ZoneData: ZoneData)
	ZoneInstance:SetAttribute("Biome", ZoneData.Biome)
	ZoneInstance:SetAttribute("Priority", ZoneData.Priority)
end

local function InitializeAllZones()
	for _, Child in ipairs(ZonesFolder:GetChildren()) do
		local ZoneData = InitializeZone(Child)
		if ZoneData then
			Zones[ZoneData.Name] = ZoneData
			SetZoneAttributes(Child, ZoneData)
		end
	end
end

local function OnZoneAdded(ZoneInstance: Instance)
	local ZoneData = InitializeZone(ZoneInstance)
	if ZoneData then
		Zones[ZoneData.Name] = ZoneData
		SetZoneAttributes(ZoneInstance, ZoneData)
	end
end

local function OnZoneRemoved(ZoneInstance: Instance)
	Zones[ZoneInstance.Name] = nil
end

local function ServerTick()
	local CurrentTime = os.clock()
	local DeltaTime = CurrentTime - LastTickTime
	LastTickTime = CurrentTime

	FrontManager.Update(DeltaTime)
end

FrontManager.Initialize()
InitializeAllZones()

ZonesFolder.ChildAdded:Connect(OnZoneAdded)
ZonesFolder.ChildRemoved:Connect(OnZoneRemoved)

LastTickTime = os.clock()

while true do
	task.wait(WeatherConfig.TICK_RATE)
	ServerTick()
end