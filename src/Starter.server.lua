local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalLinker = ReplicatedStorage:FindFirstChild("LocalLinker")

-- Run outside of Hexolus environment
if not LocalLinker then
	require(script.Parent)()
end