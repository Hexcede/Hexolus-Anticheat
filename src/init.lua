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
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

-- Set to true to enable debug output, set to RunService:IsStudio() to enable it only in studio
local DEBUG = false

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

local Anticheat = {}

Anticheat.ChecksEnabled = {
	-- Experimental - You may not wish to turn these on, but, I encourage you to test them out
	Experimental__LocalCharacter = false, -- Prevents clients from deleting descendants of the character by creating a local container
	-- Must use some custom tool sync code as well
	-- Some replication quirks exist, so, use this at your own risk
	-- (e.g. tools are equipped, then dequipped, then equipped again on the client due to how the replication works)

	-- Basic checks
	Teleportation = true, -- Changing your position, or otherwise moving faster than humanly possible in a single instant
	Speed = true, -- Zoom
	Noclip = true, -- Going ghost
	VerticalSpeed = true, -- Zooming up or down (Speed and vertical speed are both done as separate checks)

	-- Non movement related checks
	MultiTool = true, -- Equipping multiple tools at once
	InvalidDrop = true, -- Dropping tools that don't have CanBeDropped
	ToolDeletion = true, -- Stop the client from deleting tools (Incompatible with any usage of tool.Parent = nil, use :Destroy() instead)
	FEGodMode = true, -- God mod achieved by deleting their Humanoid on the server and creating a fake one on the client

	-- Upcoming checks
	--ServerOwnedLimbs = true, -- Make sure limbs are server owned when detached from the player
	--HumanoidStateValidation = true, -- Validate humanoid states and make sure things such as Swimming, Climbing, etc happen when they make sense to


	-- Unstable - DO NOT USE IN PRODUCTION
	-- TDOO: Rewrite
	Flight = false
}

Anticheat.Thresholds = {
	Acceleration = 0.85, -- Maximum vertical acceleration above expected
	Speed = 0.35, -- Maximum speed above expected
	SpeedPercent = 4.5, -- Percentage threshold (E.g. 6.5 = 6.5% faster than expected)
	VerticalSpeed = 1, -- Maximum vertical speed above expected
	VerticalSpeedPercent = 5, -- Percentage threshold (E.g. 15 = 15% faster than expected)
	VerticalSpeedCap = workspace.Gravity * 0.65, -- Maximum positive vertical speed
	Teleportation = 5, -- Maximum teleport distance above expected
	TeleportationPercent = 20, -- Percentage leeway (E.g. 25 = 25% further than expected)
	VerticalTeleportation = 2, -- Maximum teleport distance above expected (vertical)
	VerticalTeleportationPercent = 30, -- Percentage leeway (E.g. 40 = 40% further than expected)

	-- TODO: Rewrite
	GroundThreshold = 1, -- Distance from the ground to be considered on the ground
	FlightTimeThreshold = 1 -- A threshold to determine how long a player can be off the ground for
}

local SMALL_DECIMAL = 1e-3
function Anticheat:TestPlayers(PlayerManager, delta)
	local function checkCast(results, root)
		if not results then
			return false
		end

		return results.Instance:CanCollideWith(root)
	end

	local function performCast(pos, dir, raycastParams, root)
		local results
		repeat
			results = workspace:Raycast(pos, dir, raycastParams)
			pos = results and results.Position + dir.Unit * 0.01
		until not pos or not results or checkCast(results, root)

		return results
	end

	local function dualCast(pos, dir, raycastParams, root)
		return performCast(pos, dir, raycastParams, root) or performCast(pos + dir, -dir, raycastParams, root)
	end

	local function resetData(playerData)
		local physicsData = {}

		playerData.PhysicsData = physicsData

		return physicsData
	end

	local reasons_DEBUG = {}
	for player, playerData in pairs(PlayerManager.Players) do
		coroutine.wrap(function()
			local reason_DEBUG = {}

			local physicsData = playerData.PhysicsData
			if not playerData.CharacterAddedEvent then
				playerData.CharacterAddedEvent = Linker:TrackConnection(player.CharacterAdded:Connect(function(character)
					physicsData = resetData(playerData)

					local activeHumanoidConnection_Death
					local activeHumanoidConnection_Seat
					local activeHumanoid
					local function trackHumanoid()
						if activeHumanoid then
							if Anticheat.ChecksEnabled.FEGodMode then
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

							activeHumanoidConnection_Death = Linker:TrackConnection(humanoid.Died:Connect(function()
								physicsData = resetData(playerData)
							end))

							-- Check if Humanoid is removed from the character
							if Anticheat.ChecksEnabled.FEGodMode then
								humanoid.AncestryChanged:Connect(function(_, parent)
									-- Make sure the Humanoid is part of the character
									if game:IsAncestorOf(character) then
										-- Make sure the player has a PrimaryPart
										if character.PrimaryPart and character:IsAncestorOf(character.PrimaryPart) then
											-- If the humanoid isn't part of the DataModel (was deleted)
											if not parent or not game:IsAncestorOf(humanoid) then
												-- If the humanoid was :Destroyed() from the server, this check will not fire
												-- If the humanoid was set with .Parent = nil (which is still possible) or the humanoid was :Destroyed() from the client, this will fire and the humanoid will be replaced
												-- This might interfere with server code that happens to set the humanoid's parent to nil and then somehow is effected by the humanoid actually not being there
												-- That case is unlikely, and would suggest bad code if it causes some sort of error (But, that's what the enabled switch is for anyway)
												pcall(function()
													humanoid:WaitForChild("\0", 1e-6) -- Hacky way to yield for a very very tiny amount of time
													humanoid.Parent = character
												end)
											end
										end
									end
								end)
							end

							activeHumanoidConnection_Seat = Linker:TrackConnection(humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
								if humanoid.SeatPart then
									physicsData.Sitting = true
								else
									physicsData.Sitting = false
								end
							end))
						end
					end

					local stillConnected = setmetatable({}, {__mode="kv"})
					character.ChildAdded:Connect(function(child)
						if child:IsA("Humanoid") then
							trackHumanoid()
						end

						if child:IsA("BackpackItem") then
							if not stillConnected[child] then
								local connection
								connection = child.AncestryChanged:Connect(function(_, parent)
									-- Yeah, AncestryChanged fires after ChildAdded... Makes sense to me!
									if parent == character then
										return
									end

									if parent == workspace then
										-- Tool is being dropped
										if Anticheat.ChecksEnabled.InvalidDrop then
											-- If the tool can't be dropped and it wasn't dropped from the server
											if not child.CanBeDropped then
												-- Prevent the drop
												child:WaitForChild("\0", 1e-6) -- Hacky way to yield for a very very tiny amount of time
												child.Parent = player:FindFirstChildWhichIsA("Backpack") or Instance.new("Backpack", player)
											end
										end
									elseif not parent then
										if Anticheat.ChecksEnabled.ToolDeletion then
											-- Stop the tool from being deleted
											-- Will fail if done on the server via :Destroy()
											pcall(function()
												child:WaitForChild("\0", 1e-6) -- Hacky way to yield for a very very tiny amount of time
												child.Parent = player:FindFirstChildWhichIsA("Backpack") or Instance.new("Backpack", player)
											end)
										end
									else
										stillConnected[child] = nil
										connection:Disconnect()
										connection = nil
									end
								end)
								stillConnected[child] = connection
							end

							if Anticheat.ChecksEnabled.MultiTool then
								-- Count the number of tools in the character
								local toolCount = 0
								for _, child in ipairs(character:GetChildren()) do
									if child:IsA("BackpackItem") then
										toolCount += 1

										if toolCount > 1 then
											child:WaitForChild("\0", 1e-6) -- Hacky way to yield for a very very tiny amount of time
											-- If we already have a tool, we want to move this one back to the player's backpack
											-- This also avoids conflicts where a tool is given to the player by the server
											child.Parent = player:FindFirstChildWhichIsA("Backpack") or Instance.new("Backpack", player)
										end
									end
								end
							end
						end
					end)

					trackHumanoid()

					-- An enormous thanks to grilme99 for letting me know that CFrame changed events fire when CFrame is set on the server					
					local rootPart = character.PrimaryPart or character:WaitForChild("HumanoidRootPart")
					rootPart:GetPropertyChangedSignal("CFrame"):Connect(function()
						local cframe = rootPart.CFrame

						physicsData.InitialCFrame = cframe
					end)

					-- Listen for scripted Velocity changes on the server
					rootPart:GetPropertyChangedSignal("Velocity"):Connect(function()
						local velocity = rootPart:GetVelocityAtPosition(rootPart.Position)

						physicsData.VelocityMemory = velocity
					end)
					rootPart:GetPropertyChangedSignal("AssemblyLinearVelocity"):Connect(function()
						local AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity

						physicsData.VelocityMemory = AssemblyLinearVelocity
					end)
				end))
			end

			local character = physicsData and player.Character
			if character then
				local root = character.PrimaryPart

				-- Make sure they have a root
				if root then
					if not physicsData.Sitting then
						local updateJumpSpeed = false
						-- Positional checking
						do
							local flagForUpdate = false
							-- Don't check them if they're server-owned
							local networkCheck = root:CanSetNetworkOwnership()
							if not networkCheck or root:GetNetworkOwner() ~= player then
								if networkCheck then
									physicsData.VelocityMemory = root.AssemblyLinearVelocity
								end
								physicsData.InitialCFrame = root.CFrame
								physicsData.Acceleration = root.AssemblyLinearVelocity - (physicsData.InitialVelocity or Vector3.new())
								physicsData.InitialVelocity = root.AssemblyLinearVelocity
								return
							end

							-- Create raycast parameters for noclip, they'll reset upon respawn
							local raycastParams = physicsData and physicsData.RaycastParams or (function()
								local params = RaycastParams.new()

								params.FilterDescendantsInstances = {
									player.Character
								}
								params.IgnoreWater = true
								params.CollisionGroup = PhysicsService:GetCollisionGroupName(root.CollisionGroupId)
								params.FilterType = Enum.RaycastFilterType.Blacklist

								return params
							end)()

							-- Get their previous AssemblyLinearVelocity
							local AssemblyLinearVelocity = physicsData.InitialVelocity or root.AssemblyLinearVelocity
							-- Get only the horizontal component
							local horizontalVelocity = AssemblyLinearVelocity * Vector3.new(1, 0, 1)
							-- Get only the vertical component
							local verticalSpeed = AssemblyLinearVelocity.Y

							-- Get memorized AssemblyLinearVelocity
							local velocityMemory = physicsData.VelocityMemory or Vector3.new()
							-- Get only the horizontal component
							local memHorizontal = velocityMemory * Vector3.new(1, 0, 1)
							-- Get only the vertical component
							local memVertical = velocityMemory.Y

							local function sign(num)
								local sign = math.sign(num)

								if sign == 0 then
									sign = 1
								end

								return sign
							end
							local updatedVelocity = Vector3.new(sign(velocityMemory.X) * math.max(math.abs(AssemblyLinearVelocity.X), math.abs(velocityMemory.X)), sign(velocityMemory.Y) * math.max(math.abs(AssemblyLinearVelocity.Y), math.abs(velocityMemory.Y)), sign(velocityMemory.Z) * math.max(math.abs(AssemblyLinearVelocity.Z), math.abs(velocityMemory.Z)))--AssemblyLinearVelocity--horizontalVelocity + Vector3.new(0, verticalSpeed, 0)
							velocityMemory = updatedVelocity

							--local updatedVelocity = horizontalVelocity + Vector3.new(0, verticalSpeed, 0)

							-- Get the initial position of their character, and calculate the delta
							local initialPos = (physicsData.InitialCFrame and physicsData.InitialCFrame.p) or root.CFrame.p
							local localDelta = ((physicsData.InitTime and os.clock() - physicsData.InitTime) or 1)--delta)
							if localDelta == 0 then
								localDelta = delta
							end
							local realDiff = root.CFrame.p - initialPos

							-- If they had a previous speed
							if physicsData.InitialVelocity then
								--local expectedDiff = updatedVelocity * (localDelta * 2)
								local expectedDiff = updatedVelocity * (localDelta + 1/workspace:GetRealPhysicsFPS())--(localDelta * 2)

								-- General teleport check
								if Anticheat.ChecksEnabled.Teleportation then
									-- Check if they moved faster than expected
									local magFail = realDiff.Magnitude > (expectedDiff.Magnitude + self.Thresholds.Teleportation + self.Thresholds.TeleportationPercent/100 * expectedDiff.Magnitude)

									if magFail then
										table.insert(reason_DEBUG, "Teleport ("..realDiff.Magnitude.." studs, expected "..expectedDiff.Magnitude.." "..(expectedDiff.Magnitude + self.Thresholds.Teleportation + self.Thresholds.TeleportationPercent/100 * expectedDiff.Magnitude)..")\n  AssemblyLinearVelocity: "..tostring(updatedVelocity).."\n  Delta: "..tostring(localDelta).."\n  IPos: "..tostring(initialPos).."\n  Pos: "..tostring(root.CFrame.p))

										-- Change their position to what was expected
										realDiff = realDiff.Unit * (expectedDiff.Magnitude + self.Thresholds.Teleportation + self.Thresholds.TeleportationPercent/100 * expectedDiff.Magnitude)
										flagForUpdate = true
									end
								end

								-- On ground
								local _, charSize = character:GetBoundingBox()
								local height = charSize.Y

								local footDir = Vector3.new(0, -height/2 + 0.1, 0)
								local down = footDir + Vector3.new(0, -self.Thresholds.GroundThreshold, 0)
								local results = performCast(initialPos, down, raycastParams, root)

								if results then
									if not physicsData.OnGround then
										physicsData.OnGround = true
									end
								elseif physicsData.OnGround then
									physicsData.OnGround = false
									physicsData.LastOnGround = os.clock()
									updateJumpSpeed = true
									physicsData.JumpSpeed = root.AssemblyLinearVelocity.Y
								end

								-- Flight check
								-- TODO: Rewrite
								if Anticheat.ChecksEnabled.Flight then
									if not physicsData.OnGround and root.AssemblyLinearVelocity.Y >= 0  then
										if physicsData.LastOnGround then
											local g = workspace.Gravity / (root.AssemblyMass or root.Mass)
											local v = physicsData.JumpSpeed or 0
											local jumpTime = v / g

											local jumpingTime = os.clock() - physicsData.LastOnGround
											if jumpingTime > jumpTime + self.Thresholds.FlightTimeThreshold then
												physicsData.OnGround = true

												local results = performCast(initialPos, footDir + Vector3.new(0, -10000, 0), raycastParams, root)
												if results then
													table.insert(reason_DEBUG, "Flight (Jump time: "..jumpingTime.." Expected: "..jumpTime..")")
													local cf = root.CFrame
													realDiff = results.Position - (cf.p + footDir)
													flagForUpdate = true

													root.AssemblyLinearVelocity *= Vector3.new(1, 0, 1)
													root.AssemblyLinearVelocity -= Vector3.new(0, workspace.Gravity, 0)
												end
											end
										end
									end
								end
							end

							-- Noclip check
							-- Wouldn't it be so hot if we had Boxcasting for this so we can cast their whole root part? ("Yes!" https://devforum.roblox.com/t/worldroot-spherecast-in-engine-spherecasting/959899)
							if Anticheat.ChecksEnabled.Noclip then
								local results = performCast(initialPos, realDiff, raycastParams, root) or performCast(initialPos, -realDiff, raycastParams, root)--workspace:Raycast(initialPos, realDiff, raycastParams) or workspace:Raycast(initialPos, -realDiff, raycastParams)
								if results then
									table.insert(reason_DEBUG, "Noclip ("..results.Instance:GetFullName()..")")

									-- Move them back to where they came from
									local diff = results.Position - initialPos

									diff = diff - diff.Unit * 0.5 + results.Normal * 2

									realDiff = diff
									flagForUpdate = true
								end
							end

							if flagForUpdate then
								-- Calculate the reset CFrame
								local position = initialPos + realDiff
								local cframe = CFrame.new(position, position+root.CFrame.LookVector)

								-- Reset their location without firing extra events (much smoother)
								workspace:BulkMoveTo({root}, {cframe}, Enum.BulkMoveMode.FireCFrameChanged)
							end
						end

						-- AssemblyLinearVelocity checking
						do
							-- Get their humanoid
							local humanoid = character:FindFirstChildOfClass("Humanoid")

							local flagForHorizontalUpdate, flagForVerticalUpdate = false
							if humanoid then
								local horizontalVelocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
								local verticalSpeed = root.AssemblyLinearVelocity.Y

								-- Get memorized AssemblyLinearVelocity
								local velocityMemory = physicsData.VelocityMemory or Vector3.new()
								-- Get only the horizontal component
								local memHorizontal = velocityMemory * Vector3.new(1, 0, 1)
								-- Get only the vertical component
								local memVertical = velocityMemory.Y

								local previousVerticalSpeed = (physicsData.InitialVelocity and physicsData.InitialVelocity.Y) or 0

								local initialVelocity = horizontalVelocity + Vector3.new(0, verticalSpeed, 0)
								physicsData.Acceleration = initialVelocity - (physicsData.InitialVelocity or Vector3.new())

								-- Make it a pain for exploiters to set WalkSpeed and other things by constantly blasting them with property updates
								-- This makes their speed hacks inconsistent and helps enforce client physics updates by causing big fluctuations in speed
								-- This is not intended to stop any form of exploiting, just make it more annoying and reduce compatability
								humanoid.WalkSpeed += SMALL_DECIMAL
								humanoid.WalkSpeed -= SMALL_DECIMAL
								humanoid.JumpPower += SMALL_DECIMAL
								humanoid.JumpPower -= SMALL_DECIMAL
								humanoid.JumpHeight += SMALL_DECIMAL
								humanoid.JumpHeight -= SMALL_DECIMAL
								humanoid.HipHeight += SMALL_DECIMAL
								humanoid.HipHeight -= SMALL_DECIMAL
								humanoid.MaxSlopeAngle += SMALL_DECIMAL
								humanoid.MaxSlopeAngle -= SMALL_DECIMAL

								local walkSpeed = humanoid.WalkSpeed
								local jumpPower = humanoid.JumpPower

								if Anticheat.ChecksEnabled.VerticalSpeed then
									if verticalSpeed > (math.max(jumpPower, memVertical) + self.Thresholds.VerticalSpeed + self.Thresholds.VerticalSpeedPercent/100 * math.max(jumpPower, memVertical)) then
										if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
											table.insert(reason_DEBUG, "Vert Jump ("..verticalSpeed.." sps)")

											-- Jump vertical speed
											verticalSpeed = math.min(verticalSpeed, (math.max(jumpPower, memVertical) + self.Thresholds.VerticalSpeed + self.Thresholds.VerticalSpeedPercent/100 * math.max(jumpPower, memVertical)))
											flagForVerticalUpdate = true
										else
											-- Non-jump vertical speed
											if humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
												if verticalSpeed > memVertical + self.Thresholds.VerticalSpeedCap then
													table.insert(reason_DEBUG, "Vert Nojump ("..verticalSpeed.." sps)")

													verticalSpeed = math.min(verticalSpeed, memVertical + self.Thresholds.VerticalSpeedCap)
													flagForVerticalUpdate = true
												end
											end

											-- Vertical acceleration
											if physicsData.Acceleration and verticalSpeed > 0 and physicsData.Acceleration.Y > math.max(previousVerticalSpeed, memVertical) + self.Thresholds.Acceleration then
												table.insert(reason_DEBUG, "Vert Accel ("..tostring(physicsData.Acceleration).." sps^2)")

												verticalSpeed = verticalSpeed - physicsData.Acceleration.Y + self.Thresholds.Acceleration
												flagForVerticalUpdate = true
											end
										end
									end
								end

								-- Speed check
								if Anticheat.ChecksEnabled.Speed then
									if horizontalVelocity.Magnitude > (math.max(walkSpeed, memHorizontal.Magnitude) + self.Thresholds.Speed + self.Thresholds.SpeedPercent/100 * math.max(walkSpeed, memHorizontal.Magnitude)) then
										table.insert(reason_DEBUG, "Speed ("..horizontalVelocity.Magnitude.." sps)")

										horizontalVelocity = horizontalVelocity.Unit * (walkSpeed + self.Thresholds.Speed + self.Thresholds.SpeedPercent/100 * math.max(walkSpeed, memHorizontal.Magnitude))
										flagForHorizontalUpdate = true
									end
								end

								if updateJumpSpeed then
									physicsData.JumpSpeed = verticalSpeed
								end

								local flagForUpdate = flagForVerticalUpdate or flagForHorizontalUpdate

								-- Update horizontal velocity
								if flagForHorizontalUpdate then
									initialVelocity = horizontalVelocity
								else
									initialVelocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
								end

								-- Update vertical velocity
								if flagForVerticalUpdate then
									initialVelocity += Vector3.new(0, verticalSpeed, 0)
								else
									initialVelocity += Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
								end

								if physicsData.InitialVelocity then
									physicsData.Acceleration = initialVelocity - physicsData.InitialVelocity
								else
									physicsData.Acceleration = Vector3.new()
								end

								-- This improves physics accuracy due to network delay by assuming the acceleration will remain close to the same
								if flagForUpdate then
									if physicsData.Acceleration then
										-- Assume that the client will continue accelerating at the current rate and project that assumption
										initialVelocity += physicsData.Acceleration
									end
								end

								if flagForUpdate then
									-- Update their velocity
									root.AssemblyLinearVelocity = initialVelocity
								end
							end
						end
					else
						physicsData.VelocityMemory = root.AssemblyLinearVelocity
					end

					physicsData.InitTime = os.clock()
					physicsData.InitialVelocity = root.AssemblyLinearVelocity
					physicsData.InitialCFrame = root.CFrame
				end
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

	if Anticheat.ChecksEnabled.Experimental__LocalCharacter then
		local StarterCharacterScripts = StarterPlayer:WaitForChild("StarterCharacterScripts")

		local LocalCharacterDispatch = script:WaitForChild("LocalCharacterDispatch")
		LocalCharacterDispatch.Parent = StarterCharacterScripts

		local equipEvent = Instance.new("RemoteFunction")
		equipEvent.Name = "Hexolus_ToolEquipEvent"

		function equipEvent:OnServerInvoke(tool, equip)
			if typeof(tool) ~= "Instance" then
				return
			end
			if not tool:IsA("BackpackItem") then
				return
			end

			local character = self.Character
			if not character then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end

			local backpack = self:FindFirstChildOfClass("Backpack")
			if not backpack then
				return
			end

			if equip then
				if tool.Parent == backpack then
					tool.Parent = character
				end
			else
				if tool.Parent == character then
					tool.Parent = backpack
				end
			end
		end

		equipEvent.Parent = ReplicatedStorage
	end

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