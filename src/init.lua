--[[
	[Hexolus Anticheat]
	  Built for game version: 1.7.2-TA
	 Description:
	   Server-only movement checking & prevention of some bad Roblox behaviours
	 Extra features:
	   Listens for server-sided teleportation (.CFrame)
	   Listens for server-sided movement updates (.Velocity/.LinearAssemblyVelocity)
	 Todo:
	   Limited BodyMover support
	    - BodyVelocity
		- BodyForce
	   Redo flight detection prevention method (The current ground placement is extremely undesirable, along with detection)
	 Todo (Non movement):
	   Prevent undesirable Humanoid state behaviour
	   Make all non-connected character body parts server owned
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Set to true to enable debug output, set to RunService:IsStudio() to enable it only in studio
local DEBUG = true

local Linker, LocalLinker
-- Get the Linker or fallback
do
	LocalLinker = ReplicatedStorage:FindFirstChild("LocalLinker")

	if not LocalLinker then
		-- Assign a fallback object for running the anticheat outside of Hexolus' framework
		Linker = {
			TrackConnection = function(connection)
				return connection
			end,
			GetService = function()

			end
		}

		-- Spawn a new thread
		coroutine.wrap(function()
			-- Attempt to wait for the linker
			LocalLinker = ReplicatedStorage:WaitForChild("LocalLinker", 1)

			if LocalLinker then
				Linker = require(LocalLinker)
				warn("[Hexolus Anticheat] Loaded before Linker?")
			end
		end)()
	else
		Linker = require(LocalLinker)
	end
end

local Anticheat = {
	Checks = (function()
		local checks = {}
		
		local function addModule(child)
			if child:IsA("ModuleScript") then
				local check = require(child)
				
				local priority = check.Priority or 1
				checks[priority] = checks[priority] or {}
				
				checks[priority][child.Name] = check
			end
		end
		
		for _, child in ipairs(script:GetChildren()) do
			addModule(child)
		end
		script.ChildAdded:Connect(addModule)
		
		return checks
	end)()
}

function Anticheat:TestPlayers(PlayerManager, delta)
	local function resetData(playerData)
		local state = {
			InstanceAddedQueue = {}
		}

		playerData.ACState = state

		return state
	end

	local reasons_DEBUG = {}
	for player, playerData in pairs(PlayerManager.Players) do
		coroutine.wrap(function()
			local frameState = {}
			local reason_DEBUG = {}

			local state = playerData.ACState
			local function characterAdded(character)
				state = resetData(playerData)

				local activeHumanoidConnection_Death
				local activeHumanoidConnection_Seat
				local activeHumanoid
				local function trackHumanoid()
					if activeHumanoid then
						if state.TrackUniqueHumanoidOnly then
							return
						end
					end

					if activeHumanoidConnection_Death then
						activeHumanoidConnection_Death:Disconnect()
						activeHumanoidConnection_Death = nil
					end
					if activeHumanoidConnection_Seat then
						activeHumanoidConnection_Seat:Disconnect()
						activeHumanoidConnection_Seat = nil
					end

					local humanoid = character:FindFirstChildWhichIsA("Humanoid")

					if humanoid then
						activeHumanoid = humanoid

						activeHumanoidConnection_Death = humanoid.Died:Connect(function()
							state = resetData(playerData)
						end)
						activeHumanoidConnection_Seat = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
							if humanoid.SeatPart then
								state.IsSitting = true
							else
								state.IsSitting = false
							end
						end)
					end
				end

				local stillConnected = setmetatable({}, {__mode="kv"})
				character.ChildAdded:Connect(function(child)
					if child:IsA("Humanoid") then
						trackHumanoid()
					end

					table.insert(state.InstanceAddedQueue, child)
				end)
				trackHumanoid()

				-- An enormous thanks to grilme99 for letting me know that CFrame changed events fire when CFrame is set on the server					
				local rootPart = character.PrimaryPart or character:WaitForChild("HumanoidRootPart")
				rootPart:GetPropertyChangedSignal("CFrame"):Connect(function()
					state.ServerCFrame = rootPart.CFrame
				end)

				-- Listen for scripted Velocity changes on the server
				local function updateServerVelocity()
					state.ServerVelocity = rootPart.AssemblyLinearVelocity
				end
				rootPart:GetPropertyChangedSignal("Velocity"):Connect(updateServerVelocity)
				rootPart:GetPropertyChangedSignal("AssemblyLinearVelocity"):Connect(updateServerVelocity)
			end
			
			local rootPart
			local character = player.Character
			if character then
				rootPart = character.PrimaryPart
			end

			if rootPart then
				state.RootPart = rootPart
				local init = state.Init
				for priority, group in pairs(self.Checks) do
					for checkName, check in pairs(group) do
						if check.Enabled then
							if not init then
								if check.Init then
									check:Init(state)
								end
							end
							if check.PreTick then
								check:PreTick(frameState, state)
							end
							if check.Tick then
								check:Tick(frameState, state)
							end
							if check.PostTick then
								check:PostTick(frameState, state)
							end
							if check.InstanceAdded then
								for _, inst in ipairs(state.InstanceAddedQueue) do
									check:InstanceAdded(frameState, state, inst)
								end
							end
						end
					end
				end
				if not init then
					state.Init = true
				end
				table.clear(state.InstanceAddedQueue)
			end
			
			if not playerData.CharacterAddedEvent then
				playerData.CharacterAddedEvent = Linker:TrackConnection(player.CharacterAdded:Connect(characterAdded))
			end

			if DEBUG then
				if #reason_DEBUG > 0 then
					table.insert(reasons_DEBUG, table.concat({tostring(player)..":", table.concat(reason_DEBUG, "\n")}, " "))
				end
			end
		end)()
	end

	if DEBUG then
		if #reasons_DEBUG > 0 then
			warn("[Hexolus Anticheat] Summary of detections:\n  ", table.concat(reasons_DEBUG, "\n  "))
		end
	end
end

function Anticheat:Start()
	local PlayerManager = Linker:GetService("PlayerManager")

	-- Code for running outside of Hexolus' environment
	if not PlayerManager then
		local players = {}
		PlayerManager = {Players = players}

		local Players = game:GetService("Players")

		local function setupPlayer(player)
			players[player] = {}
		end

		for _, player in ipairs(Players:GetPlayers()) do
			setupPlayer(player)
		end
		Players.PlayerAdded:Connect(setupPlayer)
	end

	self:Stop()

	self.Heartbeat = Linker:TrackConnection(RunService.Heartbeat:Connect(function(delta)
		self:TestPlayers(PlayerManager, delta)
	end))
end

function Anticheat:Stop()
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
	end
	if self.Stepped then
		self.Stepped:Disconnect()
	end
end

return function()
	if Linker and Linker.Flags then
		DEBUG = Linker.Flags.DEBUG
	end

	if DEBUG then
		warn("[Hexolus Anticheat] Running in DEBUG mode.")

		if not LocalLinker then
			warn("[Hexolus Anticheat] Running outside of a Hexolus environment.")
		end
	end

	Anticheat:Start()
	return Anticheat
end