local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Debris=game:GetService("Debris")
local RunService=game:GetService("RunService")
local Modules=ReplicatedStorage:WaitForChild("Modules")
local Remotes=ReplicatedStorage:WaitForChild("Remotes")
local GrabAnimations=ReplicatedStorage:WaitForChild("GrabAnimations")
local ClashParticle=ReplicatedStorage:WaitForChild("ClashParticle")
local SFXFolder=ReplicatedStorage:WaitForChild("SFX")
local QuestServer = require(game.ServerScriptService.QuestServer)

local Hitbox=require(Modules:WaitForChild("Hitbox"))
local Ragdoll=require(Modules:WaitForChild("Ragdoll"))
local ProfileManager=require(game.ServerScriptService.Data:WaitForChild("ProfileManager"))

local PlaySFX=Remotes:WaitForChild("PlaySFX")
local AuthorizeGrab=Remotes:WaitForChild("AuthorizeGrab")
local AuthorizeThrow=Remotes:WaitForChild("AuthorizeThrow")
local GrabbedPlayer=Remotes:WaitForChild("GrabbedPlayer")
local DropPlayer=Remotes:WaitForChild("DropPlayer")
local CarrierStopCarry=Remotes:FindFirstChild("CarrierStopCarry")
local StopCarryingAnim=Remotes:WaitForChild("StopCarryingAnim")

_G.playersInLobby=_G.playersInLobby or {}
local playersInLobby=_G.playersInLobby
local lobbyPart=workspace:WaitForChild("LobbyPart")

local activeGrabs={}
local GrabState = require(game.ServerScriptService.Modules.GrabState)
local carriedBy = GrabState.carriedBy
local holderTool={}
local autoDropToken={}
local playerCooldowns={}
local killstreakTimers={}
local killstreakCounts={}
local lastGrabAt = {}
local lastGrabTarget = {}
local pendingGrab = {}
local grabbingLock = {}

local grabLock = {}
local lastGrabTime = {}

local CLASH_WINDOW = 0.18

local lastGrabTime = {}
local activeGrabs = activeGrabs or {}
local carriedBy = carriedBy or {}
local holderTool = holderTool or {}
local autoDropToken = autoDropToken or {}

local function getPlayerFromChar(char)
	return Players:GetPlayerFromCharacter(char)
end

local function getCharFromPlayer(player)
	return player and player.Character or nil
end

local function clearKillstreakTimer(p)
	if killstreakTimers[p] then
		task.cancel(killstreakTimers[p])
		killstreakTimers[p]=nil
		killstreakCounts[p]=0
	end
end

local function startKillstreakTimer(p)
	if killstreakTimers[p] then task.cancel(killstreakTimers[p]) end
	killstreakTimers[p]=task.delay(10,function()
		killstreakCounts[p]=nil
		killstreakTimers[p]=nil
	end)
end

local function playKillstreakSound(p)
	killstreakCounts[p]=(killstreakCounts[p] or 0)+1
	local key="Kill"..tostring(math.min(killstreakCounts[p],5))
	PlaySFX:FireClient(p,key)
	startKillstreakTimer(p)
end

lobbyPart.Touched:Connect(function(part)
	local c=part.Parent
	if not c then return end
	local p=Players:GetPlayerFromCharacter(c)
	if p then playersInLobby[p]=true end
end)

lobbyPart.TouchEnded:Connect(function(part)
	local c=part.Parent
	if not c then return end
	local p=Players:GetPlayerFromCharacter(c)
	if not p then return end
	local touching=false
	for _,cp in ipairs(c:GetChildren()) do
		if cp:IsA("BasePart") then
			for _,t in ipairs(cp:GetTouchingParts()) do
				if t==lobbyPart then touching=true break end
			end
			if touching then break end
		end
	end
	if not touching then playersInLobby[p]=nil end
end)

local function setCarryPhysics(char,val)
	for _,part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless=val
			part.CanCollide=not val
		end
	end
end

local function stopCarrierState(holderChar)
	local p=Players:GetPlayerFromCharacter(holderChar)
	if CarrierStopCarry and p then CarrierStopCarry:FireClient(p) end
	local tool=holderTool[holderChar]
	if tool and tool.Parent then
		local hcVal=tool:FindFirstChild("HoldingCharacter")
		if hcVal then hcVal.Value=nil end
		tool:SetAttribute("Holding",false)
	end
	holderTool[holderChar]=nil
end

local function releaseCarry(victimChar)
	if not victimChar then return end
	local vPlr = Players:GetPlayerFromCharacter(victimChar)
	if not vPlr then return end
	local hPlr = carriedBy[vPlr]
	if hPlr then activeGrabs[hPlr] = nil end
	carriedBy[vPlr] = nil
	autoDropToken[vPlr] = nil

	local holderChar = hPlr and hPlr.Character or nil
	local root = victimChar:FindFirstChild("HumanoidRootPart")
	if root then
		local hc = root:FindFirstChild("HoldConstraint")
		if hc then hc:Destroy() end
	end

	if holderChar then
		local tool = holderTool[holderChar]
		if tool then
			tool:SetAttribute("Holding", false)
			local hcVal = tool:FindFirstChild("HoldingCharacter")
			if hcVal then hcVal.Value = nil end
		end
		holderTool[holderChar] = nil

		if StopCarryingAnim then
			StopCarryingAnim:FireClient(hPlr)
		end
	end

	for _, part in ipairs(victimChar:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = false
			part.CanCollide = true
		end
	end

	local vHum = victimChar:FindFirstChildOfClass("Humanoid")
	if vHum then vHum.PlatformStand = false end

	DropPlayer:FireClient(vPlr, false)

	activeGrabs[vPlr] = nil
	carriedBy[vPlr] = nil
	holderTool[vPlr] = nil
	playerCooldowns[vPlr] = nil
	grabLock[vPlr] = nil
	lastGrabTime[vPlr] = nil
end

local function startAutoDrop(holderChar, victimChar, seconds)
	if not holderChar or not victimChar then return end
	local vPlr = Players:GetPlayerFromCharacter(victimChar)
	local hPlr = Players:GetPlayerFromCharacter(holderChar)
	if not vPlr or not hPlr then return end
	local token = {}
	autoDropToken[vPlr] = token
	task.delay(seconds, function()
		if autoDropToken[vPlr] == token and carriedBy[vPlr] == hPlr then
			releaseCarry(victimChar)
		end
	end)
end

local function playGrabMissAnim(p)
	local char=p.Character
	if not char then return end
	local hum=char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local equippedFolder = p:FindFirstChild("Equipped")
	local animSetName = equippedFolder and equippedFolder:FindFirstChild("EquippedGrabAnimation") and equippedFolder.EquippedGrabAnimation.Value or "Default"

	local animFolder = GrabAnimations:FindFirstChild(animSetName) or GrabAnimations.Default
	if not animFolder then return end
	local anim=animFolder:FindFirstChild("Grab")
	if not anim then return end
	local animator=hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local track=animator:LoadAnimation(anim)
	track.Priority=Enum.AnimationPriority.Action
	track:Play()
	Debris:AddItem(track,2)
end

local function spawnClashParticle(p)
	if not p or not p.Character then return end
	local root=p.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local particle=ClashParticle:Clone()
	particle.CFrame=root.CFrame
	particle.Parent=workspace
	task.delay(1.2, function()
		local NewParticle = ReplicatedStorage.LightningGrab:Clone()
		NewParticle.Parent = root
		Debris:AddItem(NewParticle, 1.2)
	end)
	task.delay(1.8,function() if particle then particle:Destroy() end end)
end

local function handleGrabClash(p1, p2)
	activeGrabs[p1] = nil
	activeGrabs[p2] = nil
	carriedBy[p1] = nil
	carriedBy[p2] = nil
	lastGrabTime[p1] = os.clock()
	lastGrabTime[p2] = os.clock()
	PlaySFX:FireClient(p1, "GrabClash")
	PlaySFX:FireClient(p2, "GrabClash")
	DropPlayer:FireClient(p1, false)
	DropPlayer:FireClient(p2, false)
	print("spawning clash particle")
	spawnClashParticle(p1)
	spawnClashParticle(p2)
	if StopCarryingAnim then
		StopCarryingAnim:FireClient(p1)
		StopCarryingAnim:FireClient(p2)
	end
	p1.Character.PrimaryPart.Anchored = true
	p2.Character.PrimaryPart.Anchored = true
	task.delay(1, function()
		p1.Character.PrimaryPart.Anchored = false
		p2.Character.PrimaryPart.Anchored = false
	end)

	Remotes.GrabClashAnimation:FireClient(p1)
	Remotes.GrabClashAnimation:FireClient(p2)

	ProfileManager:AddGrabClashes(p1, 1)
	ProfileManager:AddGrabClashes(p2, 1)
	local QuestServer = require(game.ServerScriptService.QuestServer)
	QuestServer.IncrementQuest(p1, "GrabClashes", 1)
	QuestServer.IncrementQuest(p2, "GrabClashes", 1)

	task.wait(1.5)

	local char1 = p1.Character
	local char2 = p2.Character
	local root1 = char1 and char1:FindFirstChild("HumanoidRootPart")
	local root2 = char2 and char2:FindFirstChild("HumanoidRootPart")

	if root1 and root2 then
		local direction = (root1.Position - root2.Position).Unit
		local knockbackStrength = 25

		local att1 = root1:FindFirstChild("RootAttachment")
		if att1 then
			local lv1 = Instance.new("LinearVelocity")
			lv1.VectorVelocity = direction * knockbackStrength
			lv1.Attachment0 = att1
			lv1.MaxForce = math.huge
			lv1.Parent = root1
			Debris:AddItem(lv1, 0.2)
		end

		local att2 = root2:FindFirstChild("RootAttachment")
		if att2 then
			local lv2 = Instance.new("LinearVelocity")
			lv2.VectorVelocity = -direction * knockbackStrength
			lv2.Attachment0 = att2
			lv2.MaxForce = math.huge
			lv2.Parent = root2
			Debris:AddItem(lv2, 0.2)
		end
	end

	local hc = p1.Character.PrimaryPart:FindFirstChild("HoldConstraint")
	if hc then hc:Destroy() end
	local hc1 = p2.Character.PrimaryPart:FindFirstChild("HoldConstraint")
	if hc1 then hc1:Destroy() end
	for _, Part in pairs(p1.Character:GetDescendants()) do
		if Part.Name == "HoldConstraint" then Part:Destroy() end
	end
	for _, Part in pairs(p2.Character:GetDescendants()) do
		if Part.Name == "HoldConstraint" then Part:Destroy() end
	end
	task.wait(0.5)
	for _, Part in pairs(p1.Character:GetDescendants()) do
		if Part.Name == "HoldConstraint" then Part:Destroy() end
	end
	for _, Part in pairs(p2.Character:GetDescendants()) do
		if Part.Name == "HoldConstraint" then Part:Destroy() end
	end
	task.wait(1)
	for _, Part in pairs(p1.Character:GetDescendants()) do
		if Part.Name == "HoldConstraint" then Part:Destroy() end
	end
	for _, Part in pairs(p2.Character:GetDescendants()) do
		if Part.Name == "HoldConstraint" then Part:Destroy() end
	end
	playerCooldowns[p1] = nil
	playerCooldowns[p2] = nil

	local function resetGrabState(p)
		playerCooldowns[p] = nil
		grabLock[p] = nil
		pendingGrab[p] = nil
		grabbingLock[p] = nil
		lastGrabTime[p] = nil
		lastGrabAt[p] = nil
		lastGrabTarget[p] = nil
		killstreakCounts[p] = 0

		local char = p.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
					if string.find(track.Name, "Grab") or string.find(track.Name, "Carry") then
						track:Stop()
					end
				end
				hum.PlatformStand = false
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local hc = root:FindFirstChild("HoldConstraint")
				if hc then hc:Destroy() end
			end
			setCarryPhysics(char, false)
			for _, tool in ipairs(char:GetChildren()) do
				if tool:IsA("Tool") then
					tool:SetAttribute("Holding", false)
					local hcVal = tool:FindFirstChild("HoldingCharacter")
					if hcVal then hcVal.Value = nil end
				end
			end
		end

		local bp = p:FindFirstChildOfClass("Backpack")
		if bp then
			for _, tool in ipairs(bp:GetChildren()) do
				if tool:IsA("Tool") then
					tool:SetAttribute("Holding", false)
					local hcVal = tool:FindFirstChild("HoldingCharacter")
					if hcVal then hcVal.Value = nil end
				end
			end
		end

		activeGrabs[p] = nil
		carriedBy[p] = nil
		holderTool[p] = nil
		playerCooldowns[p] = nil
		grabLock[p] = nil
		lastGrabTime[p] = nil
	end

	resetGrabState(p1)
	resetGrabState(p2)
end

task.delay(15, function()
	local player1 = Players:FindFirstChild("Player1")
	local player2 = Players:FindFirstChild("Player2")

	if player1 and player2 and player1.Character and player2.Character then
		print("Simulating grab clash between", player1.Name, "and", player2.Name)
		lastGrabTime[player1] = os.clock()
		lastGrabTime[player2] = os.clock()
		handleGrabClash(player1, player2)
	else
		warn("Could not find both players for grab clash test")
	end
end)


local function GrabPlayer(holderChar, victimChar, tool)
	local holder = Players:GetPlayerFromCharacter(holderChar)
	local victim = Players:GetPlayerFromCharacter(victimChar)
	if not holder or not victim then return end
	local grabclash = false
	if activeGrabs[victim] == holder then
		grabclash = true
		handleGrabClash(holder, victim)
		return
	end
	if activeGrabs[holder] then
		local prevVictim = activeGrabs[holder]
		local prevChar = prevVictim and prevVictim.Character
		if prevChar then releaseCarry(prevChar) end
	end
	if carriedBy[victim] then
		local oldHolder = carriedBy[victim]
		local oldChar = oldHolder and oldHolder.Character
		if oldChar then releaseCarry(victimChar) end
	end
	activeGrabs[holder] = victim
	carriedBy[victim] = holder
	holderTool[holderChar] = tool
	for _,part in ipairs(victimChar:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = true
			part.CanCollide = false
		end
	end
	local vHum = victimChar:FindFirstChildOfClass("Humanoid")
	if vHum then vHum.PlatformStand = true end
	local aRoot = holderChar:FindFirstChild("HumanoidRootPart")
	local vRoot = victimChar:FindFirstChild("HumanoidRootPart")
	if aRoot and vRoot and not grabclash then
		local weld = Instance.new("Weld")
		weld.Name = "HoldConstraint"
		weld.Part0 = aRoot
		weld.Part1 = vRoot
		weld.C0 = CFrame.new(0,0,-2) * CFrame.Angles(0, math.rad(180), 0)
		weld.Parent = vRoot
	end
	if vHum then vHum.Died:Once(function() releaseCarry(victimChar) end) end
	local hHum = holderChar:FindFirstChildOfClass("Humanoid")
	if hHum then hHum.Died:Once(function() releaseCarry(victimChar) end) end

	local equippedFolder = holder:FindFirstChild("Equipped")
	local animSetName = equippedFolder and equippedFolder:FindFirstChild("EquippedGrabAnimation") and equippedFolder.EquippedGrabAnimation.Value or "Default"

	local animFolder = GrabAnimations:FindFirstChild(animSetName) or GrabAnimations.Default
	local anim = animFolder:FindFirstChild("Carried")

	if anim then
		GrabbedPlayer:FireClient(victim, anim)
	end

	PlaySFX:FireClient(holder, "GrabHit")
	startAutoDrop(holderChar, victimChar, 7)
	local QuestServer = require(game.ServerScriptService.QuestServer)
	QuestServer.IncrementQuest(holder, "Grabs", 1)
end


local function ThrowPlayer(attacker, victimChar, str, dir)
	if not attacker or not victimChar then return end
	local vHum = victimChar:FindFirstChildOfClass("Humanoid")
	local vRoot = victimChar:FindFirstChild("HumanoidRootPart")
	if vHum then
		local tag = victimChar:FindFirstChild("LastThrownBy") or Instance.new("ObjectValue")
		tag.Name = "LastThrownBy"
		tag.Value = attacker
		tag.Parent = victimChar
		game:GetService("Debris"):AddItem(tag, 10)
	end
	releaseCarry(victimChar)
	if vRoot then
		local att = vRoot:FindFirstChild("RootAttachment")
		if att then
			local lv = Instance.new("LinearVelocity")
			lv.VectorVelocity = dir * str
			lv.Attachment0 = att
			lv.MaxForce = math.huge
			lv.Parent = vRoot
			game.Debris:AddItem(lv, 0.3)
		end
	end
	if vHum then
		vHum:SetAttribute("Ragdoll", true)
		task.delay(2.5, function()
			if vHum and vHum.Parent and vRoot then
				vHum:SetAttribute("Ragdoll", false)
				vRoot.AssemblyLinearVelocity = Vector3.zero
				vHum.PlatformStand = false
			end
		end)
	end
	if attacker then PlaySFX:FireClient(attacker, "Throw") end
	local vp = Players:GetPlayerFromCharacter(victimChar)
	if vp then DropPlayer:FireClient(vp, true) end
	task.spawn(function()
		if not vHum then return end
		vHum.Died:Wait()
		-- KillCredited still prevents double-crediting ProfileManager/quests for the same death
		-- but killstreak always increments regardless
		playKillstreakSound(attacker)
		if victimChar:FindFirstChild("KillCredited") then return end
		local credit = Instance.new("BoolValue")
		credit.Name = "KillCredited"
		credit.Parent = victimChar
		game:GetService("Debris"):AddItem(credit, 3)
		local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
		if victimPlayer then
			local pr = ProfileManager:GetProfile(victimPlayer)
			if pr then ProfileManager:SetKillStreak(victimPlayer, 0) end
			ProfileManager:AddKills(attacker, 1, victimPlayer.Name)
		else
			ProfileManager:AddKills(attacker, 1, "Unknown")
		end
	end)
end


AuthorizeGrab.OnServerInvoke = function(p, hc, Tool, ov)
	if p:GetAttribute("InRealityShift") then PlaySFX:FireClient(p,"GrabMiss") return false end
	if playerCooldowns[p] then PlaySFX:FireClient(p,"GrabMiss") return false end
	local c = p.Character
	if not c or not hc then PlaySFX:FireClient(p,"GrabMiss") return false end
	local g = c:FindFirstChild(Tool.Name)
	if not g then PlaySFX:FireClient(p,"GrabMiss") return false end
	local h = c:FindFirstChildOfClass("Humanoid")
	local hHum = hc:FindFirstChildOfClass("Humanoid")
	if g:GetAttribute("Holding")==true or not h or h.Health<=0 or not hHum or hHum.Health<=0 then
		g:SetAttribute("Holding",false) PlaySFX:FireClient(p,"GrabMiss") return false
	end
	if hHum:GetAttribute("Ragdoll")==true then g:SetAttribute("Holding",false) PlaySFX:FireClient(p,"GrabMiss") return false end

	local holder = p
	local victim = Players:GetPlayerFromCharacter(hc)
	if not victim then PlaySFX:FireClient(p,"GrabMiss") return false end

	if GrabState.protectedPlayers and GrabState.protectedPlayers[victim] then
		PlaySFX:FireClient(p, "GrabMiss")
		playGrabMissAnim(p)
		return false
	end

	local now = os.clock()
	local hRecent = lastGrabTime[holder] and (now - lastGrabTime[holder]) < CLASH_WINDOW
	local vRecent = lastGrabTime[victim] and (now - lastGrabTime[victim]) < CLASH_WINDOW
	if hRecent or vRecent then
		handleGrabClash(holder, victim)
		return false
	end

	local hitSize = g:GetAttribute("HitboxSize")
	local sHit = Hitbox:CastHitbox(c, hitSize * 1.5, ov)
	if not table.find(sHit, hc) then
		g:SetAttribute("Holding", false)
		PlaySFX:FireClient(p, "GrabMiss")
		return false
	end

	lastGrabTime[holder] = now
	lastGrabTime[victim] = now

	local hcVal = g:FindFirstChild("HoldingCharacter") or Instance.new("ObjectValue")
	hcVal.Name = "HoldingCharacter"
	hcVal.Parent = g
	hcVal.Value = hc
	g:SetAttribute("Holding", true)

	task.spawn(function()
		GrabPlayer(c, hc, g)
	end)
	return true
end

AuthorizeThrow.OnServerInvoke = function(p, hc, Tool, dir)
	local c = p.Character
	if not c or not hc then return false end
	local g = c:FindFirstChild(Tool.Name)
	if not g or g:GetAttribute("Holding") == false then return false end

	local hcVal = g:FindFirstChild("HoldingCharacter")
	if not hcVal or hcVal.Value ~= hc then return false end

	local str = g:GetAttribute("ThrowStrength") or 120
	task.spawn(function()
		ThrowPlayer(p, hc, str, dir.Unit)
		local victim = Players:GetPlayerFromCharacter(hc)
		if victim then
			grabLock[victim] = nil
			lastGrabTime[victim] = nil
		end
		grabLock[p] = nil
		lastGrabTime[p] = nil
	end)

	hcVal.Value = nil
	g:SetAttribute("Holding", false)
	return true
end


local function resetGrabState(p)
	playerCooldowns[p] = nil
	grabLock[p] = nil
	pendingGrab[p] = nil
	grabbingLock[p] = nil
	lastGrabTime[p] = nil
	lastGrabAt[p] = nil
	lastGrabTarget[p] = nil
	killstreakCounts[p] = 0

	local char = p.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
				if string.find(track.Name, "Grab") or string.find(track.Name, "Carry") then
					track:Stop()
				end
			end
			hum.PlatformStand = false
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local hc = root:FindFirstChild("HoldConstraint")
			if hc then hc:Destroy() end
		end
		setCarryPhysics(char, false)
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				tool:SetAttribute("Holding", false)
				local hcVal = tool:FindFirstChild("HoldingCharacter")
				if hcVal then hcVal.Value = nil end
			end
		end
	end

	local bp = p:FindFirstChildOfClass("Backpack")
	if bp then
		for _, tool in ipairs(bp:GetChildren()) do
			if tool:IsA("Tool") then
				tool:SetAttribute("Holding", false)
				local hcVal = tool:FindFirstChild("HoldingCharacter")
				if hcVal then hcVal.Value = nil end
			end
		end
	end

	activeGrabs[p] = nil
	carriedBy[p] = nil
	holderTool[p] = nil
	playerCooldowns[p] = nil
	grabLock[p] = nil
	lastGrabTime[p] = nil
end

Players.PlayerAdded:Connect(function(p)
	killstreakCounts[p] = 0

	p.CharacterAdded:Connect(function(c)
		resetGrabState(p)

		-- Glitched Attack / External Ability Support
		p:GetAttributeChangedSignal("ExternalGrabRequest"):Connect(function()
			local victimName = p:GetAttribute("ExternalGrabRequest")
			if victimName and victimName ~= "" then
				local victimPlr = Players:FindFirstChild(victimName)
				local victimChar = victimPlr and victimPlr.Character
				if victimChar and p.Character then
					local tool = p.Character:FindFirstChildWhichIsA("Tool")
					if tool then
						GrabPlayer(p.Character, victimChar, tool)
					end
				end
				p:SetAttribute("ExternalGrabRequest", "")
			end
		end)

		task.delay(1, function()
			for holder, victim in pairs(activeGrabs) do
				if holder == c or victim == c then
					activeGrabs[holder] = nil
					carriedBy[victim] = nil
				end
			end
		end)

		for _, tool in ipairs(p.Backpack:GetChildren()) do
			if tool:IsA("Tool") then
				tool:SetAttribute("Holding", false)
			end
		end

		local h = c:WaitForChild("Humanoid")
		h.Died:Connect(function()
			local pr = ProfileManager:GetProfile(p)
			if pr and pr.Data and pr.Data.KillStreak and pr.Data.KillStreak >= 8 then
				ProfileManager:SetKillStreak(p, 0)
			end
			clearKillstreakTimer(p)
			resetGrabState(p)
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	for vPlr, hPlr in pairs(carriedBy) do
		if hPlr == p then
			local vChar = vPlr.Character
			if vChar then releaseCarry(vChar) end
			carriedBy[vPlr] = nil
			activeGrabs[p] = nil
		end
	end
	local char = p.Character
	if char then releaseCarry(char) end
	clearKillstreakTimer(p)
	killstreakCounts[p] = nil
	playersInLobby[p] = nil
end)

RunService.Heartbeat:Connect(function()
	for vPlr, hPlr in pairs(carriedBy) do
		local vChar = vPlr and vPlr.Character or nil
		local hChar = hPlr and hPlr.Character or nil
		if not vChar or not hChar then
			if vChar then releaseCarry(vChar) end
			carriedBy[vPlr] = nil
			if hPlr then activeGrabs[hPlr] = nil end
		else
			local root = vChar:FindFirstChild("HumanoidRootPart")
			if not root or not root:FindFirstChild("HoldConstraint") then
				releaseCarry(vChar)
				carriedBy[vPlr] = nil
				activeGrabs[hPlr] = nil
			end
		end
	end
end)
