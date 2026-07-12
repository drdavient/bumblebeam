workspace {

    model {
        player = person "Player"

        minecraft = softwareSystem "Minecraft" {
            gameClient = container "Game Client" {
                description "The game software running on the player's machine, responsible for rendering, sound, and handling user input."
                tags "Client"
            }

            gameServer = container "Game Server" {
                description "Hosts the game world, runs game logic, and synchronizes state for all connected players."
                tags "Server"

                // --- Components ---
                c0 = component "Player State Manager" {
                    description "Manages player-specific data like health, hunger, inventory, and location."
                    tags "creative" "pvp" "vanilla"
                }
                c1 = component "Locomotion & Physics" {
                    description "Handles all movement, collision, and world physics like gravity."
                    tags "creative" "pvp" "vanilla"
                }
                c2 = component "Creative Inventory Access" {
                    description "Provides access to the full item inventory in creative mode."
                    tags "creative"
                }
                c3 = component "Health & Damage System" {
                    description "Manages health points and processes all incoming damage from various sources."
                    tags "pvp" "vanilla"
                }
                c4 = component "Combat Logic" {
                    description "Determines the outcome of player and mob attacks (e.g., hit detection, critical hits)."
                    tags "pvp" "vanilla"
                }
                c5 = component "Mob AI" {
                    description "Controls the behavior and actions of non-player characters (e.g., creepers, zombies)."
                    tags "vanilla"
                }
                c6 = component "Crafting System" {
                    description "Handles item crafting logic based on recipes."
                    tags "vanilla"
                }
                c7 = component "Redstone System" {
                    description "Processes logic for redstone circuits."
                    tags "vanilla"
                }
                c8 = component "Multiplayer Chat" {
                    description "Manages sending and receiving chat messages between players."
                    tags "creative" "pvp" "vanilla"
                }

                // --- CORRECTED: Internal Relationships are defined inside their parent container ---
                // Now we can just use the component variable names (c1, c0, etc.)
                c1 -> c0 "Updates player location in"
                c2 -> c0 "Modifies player inventory via"
                c4 -> c3 "Deals damage using"
                c5 -> c4 "Initiates attacks using"
                c5 -> c1 "Navigates world using"
                c3 -> c0 "Updates player health in"
                c6 -> c0 "Uses and updates inventory in"
            }
        }

        // Top-level relationships between containers remain here
        player -> gameClient "Uses" "Keyboard, Mouse, Screen"
        gameClient -> gameServer "Sends player actions and receives game state" "Custom TCP Protocol"
    }

    views {
        systemContext minecraft {
            include *
            autolayout lr
        }

        container minecraft {
            include *
            autolayout lr
        }

        component gameServer GameServerComponents "Game Server Components" {
            include *
            // Layout is now driven by relationships, creating a more logical diagram
        }

        filtered GameServerComponents include "creative" "CreativeMode" "Creative Mode Components"
        filtered GameServerComponents include "pvp" "MinimalPvPMode" "Minimal PvP Mode Components"
        filtered GameServerComponents include "vanilla" "FullVanillaMode" "Full Vanilla Mode Components"

        styles {
            element "person" {
                background "#08427B"
                color "#ffffff"
                shape person
            }
            element "softwareSystem" {
                background "#1168BD"
                color "#ffffff"
            }
            element "container" {
                background "#438DD5"
                color "#ffffff"
            }
            element "component" {
                background "#85BBF0"
                color "#000000"
            }
        }
    }
}