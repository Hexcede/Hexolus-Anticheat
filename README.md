# FAQ / READ FIRST
NOTE: Hexolus is NOT the name of the anticheat, and the Discord server is NOT specific to the anticheat. Hexolus is the name of the game that the anticheat was originally created for. Some of the features from Hexolus are partially open sourced, and, the anticheat is one of them.

Q: How do I download the anticheat?
A: You can download the anticheat in the Releases tab above, it will be an rbxm file and you can just drop it in

Q: Where do I put the anticheat?
A: The easiest place to put the anticheat is in `ServerScriptService` 

Q: Why aren't you updating/why haven't you added X yet?
A: Currently I am rewriting the anticheat from the ground up under the name `Polygon`. Polygon will completely replace this anticheat and become its own separate thing.

Q: Why isn't X getting detected? / "The anticheat isn't working"
A: A lot of people are understandably a little confused when, for example, setting WalkSpeed doesn't actually get detected by the anticheat. This is because the anticheat adapts to the server, its a lot like FilteringEnabled, but for physics.

# How does it work?
Most of how the anticheat works is pretty simple actually!
The anticheat basically just creates a net to block players from moving too far or going to fast. It will predict where it thinks they should be. If they aren't close to where they should be it'll put them back to a place where they are.

The anticheat just uses physics to predict the player's movements, and, adjusts for lag by skipping a bit of time in the physics so their client will receive it. You won't even notice you got lagged back usually.

# Anticheat
This is the Anticheat for Hexolus.

The anticheat is designed to stop most common movement exploits from the server alone with no help from the client at all.
This means that the only potential way for an exploiter to get around the anticheat is to either abuse flaws in your code, or use something that isn't covered by the anticheat.
Of course, there may be loopholes in how the anticheat works, but, for the most part, especially with movement exploits, there should be no way for an exploiter to circumvent what behaviour exists.

It's designed with a methodology focusing solely on prevention of exploits vs disincentive or punishment for using them.
This is good for your games because it means potential false positives or glitches with your game which trigger checks won't effect your players negatively.

I would recommend not punishing players with this anticheat unless you are an expert and know what you are doing with your checks.
There are a lot of quirks with Roblox's engine which could trigger false positives when you wouldn't expect it.

It consistently prevents noclipping, speed exploits, teleportation, and more with little to no detrement to the player's experience.
The settings have already been tuned to fairly optimal values, so, you shouldn't need to do anything when implementing this into your game.

# List of checks
* Teleportation - Changing your position, or otherwise moving faster than humanly possible in a single instant
* Speed - Zoom
* Noclip - Going ghost
* VerticalSpeed - Zooming up or down (Speed and vertical speed are both done as separate checks)
* MultiTool - Equipping multiple tools at once
* InvalidDrop - Dropping tools that don't have CanBeDropped
* ToolDeletion - Stop the client from deleting tools (Incompatible with any usage of tool.Parent = nil)
* FEGodMode - God mod by deleting their Humanoid on the server and creating a fake one on the client

# Planned checks
* ServerOwnedLimbs - Make sure limbs are server owned when detached from the player
* HumanoidStateValidation - Validate humanoid states and make sure things such as Swimming, Climbing, etc happen when they make sense to

# Unstable Checks
* Flight - This is currently extremely unreliable and prone to issues, do not use it in production

# Implementing it into your game
Implementing this into your game is pretty simple, but some components in your game might not behave as you expect them to. You should do thorough testing, especially if your game uses any sort of custom physics stuff involving the player.

To use the anticheat, just insert it into your game in ServerScriptService and it will run on its own.
Optionally, you can delete the runner script and require it manually like so:
```lua
local Anticheat = require(script:WaitForChild("Anticheat"))()
```

Generally, it won't be necessary to access any of the Anticheat's methods, and I currently recommend that if you want to make behaviour changes that you do so directly, and marking where you've made changes so you can more easily apply them. In the future, this will be addressed by making the whole anticheat much more modular.

# Caveats
Unfortunately, the anticheat has some limitations around how physics may work on a player that may or may not be detremental to your game.
Here is a list of currently unsupported or potentially unreliable behaviours:
1. Boosting/flinging without setting .Velocity or .AssemblyLinearVelocity on the server
2. Vehicle seats. Vehicle seat compatibility is still being tested, the intended behavior is that checks become disabled when the player sits in a seat.
3. BodyMovers. BodyMovers are completely incompatible with the anticheat. Some very limited BodyMover support, such as BodyVelocity and BodyForce will come in the future.
4. `Tool.Parent = nil` or `Tool.Parent = workspace` with `CanBeDropped` off. If your game sets the parent of a tool to nil while its equipped by the player, the anticheat will stop it by default. If you need this behaviour for temporary use, parent the tool to the player's backpack first, then parent to nil.
5. Climbing is currently not handled at all by the anticheat, but, should be mostly compatible. With the fly check off climbing will behave mostly as expected other than some undesirable false positives which might make it a bit annoying to use ladders. In the future, the anticheat will properly take into account climbing and will support movement checks.
