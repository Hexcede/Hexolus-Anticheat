local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local equipEvent = ReplicatedStorage:WaitForChild("Hexolus_ToolEquipEvent")
local player = Players.LocalPlayer

local character = script.Parent

local localCharacter = Instance.new("Model")
localCharacter.Archivable = character.Archivable
localCharacter.PrimaryPart = character.PrimaryPart
character:GetPropertyChangedSignal("Archivable"):Connect(function()
	localCharacter.Archivable = character.Archivable
end)
character:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
	localCharacter.PrimaryPart = character.PrimaryPart
end)
localCharacter.Name = player.Name
localCharacter.Parent = player

local doNotEquip = {}
local function handleChild(child)
	if child:IsA("Tool") then
		local tool = child
		
		doNotEquip[tool] = true
	end
	
	child:WaitForChild("\0", 1e-6) -- Hacky way to yield for a very very tiny amount of time
	child.Parent = localCharacter
end

local humanoid = character:WaitForChild("Humanoid")
humanoid.RequiresNeck = false

for _, child in ipairs(character:GetChildren()) do
	coroutine.wrap(handleChild)(child)
end
character.ChildAdded:Connect(handleChild)

ContextActionService.LocalToolEquipped:Connect(function(tool)
	if not doNotEquip[tool] then
		equipEvent:InvokeServer(tool, true)
	else
		doNotEquip[tool] = nil
	end
end)
ContextActionService.LocalToolUnequipped:Connect(function(tool)
	if tool.Parent ~= character then
		equipEvent:InvokeServer(tool, false)
	end
end)

localCharacter.Parent = workspace
player.Character = localCharacter

character.AncestryChanged:Connect(function(oldParent, newParent)
	localCharacter.Parent = newParent
end)