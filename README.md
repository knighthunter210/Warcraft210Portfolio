# Warcraft210Portfolio

Hello, This system is a modular quest system that is for a Roblox Gauntlet pvp game with daily, weekly, and lifetime quests.

The system track player's combat system, survival time, kill streak, gold obtained, and kills. The UI updates in real time and have a reward claim feature.

Through Player action such as kills, grab clashes, grabs, survival time, and earned gold contribute ot the quest progress to update the UI.

src/
├─ ServerScriptService/
│  ├─ QuestServer.lua
│  ├─ SurvivalTracker.lua
│  ├─ GauntletServer.lua
│  └─ Data/
│     ├─ QuestDefinitions.lua
│     └─ ProfileManager.lua
├─ StarterGui/
│  ├─ OldQuests/
│  │  └─ QuestController.client.lua
│  └─ NewLeft/
│     └─ Frame/
│        └─ Quests/
│           └─ QuestsToggle.client.lua
└─ ReplicatedStorage/
   └─ Modules/
      └─ PopupAnimator.lua

#Main Scripts
Server
QuestServer.lua

Main quest state manager
Assigns quest sections to players
Updates progress for matching objectives
Validates claims and awards rewards
Pushes quest updates to the UI

QuestDefinitions.lua
Central source of truth for quest configuration
Defines quest IDs, goals, rewards, stat bindings, and reset timing
Separates daily, weekly, and lifetime progression

ProfileManager.lua
Stores persistent player data
Feeds quest progress from gameplay outcomes like kills, money earned, and double kills
Handles reward currency updates

SurvivalTracker.lua
Reports survival-based progress into the quest system

GauntletServer.lua
Reports combat or interaction-based progress such as grab-related objectives

#Client
QuestController.client.lua
Handles quest menu rendering
Updates visible quest cards from server payloads
Sends reward claim requests
Switches between daily, weekly, and lifetime sections

QuestsToggle.client.lua
Opens and closes the quest interface from the main HUD

PopupAnimator.lua
Shared UI animation helper used by the quest menu

