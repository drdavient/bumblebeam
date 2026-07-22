workspace "Bumblebeam home infrastructure" "Architecture of the Bumblebeam host and its services." {

    !identifiers hierarchical

    model {
        lanClient = person "LAN client" "A household device using Bumblebeam services."

        router = softwareSystem "GL.iNet router" "Provides DHCP, LAN DNS, and the svc.home.arpa service namespace." "External"
        cloudflare = softwareSystem "Cloudflare" "Provides DNS and the public n8n route." "External"
        mediaInternet = softwareSystem "Media services and indexers" "Metadata, indexer, tracker, and download endpoints." "External"
        tailnet = softwareSystem "Tailscale tailnet" "WireGuard mesh: remote LAN access via subnet routing, split DNS, and on-demand exit node (ADR 0009)." "External"

        bumblebeam = softwareSystem "Bumblebeam" "The home-infrastructure host at 192.168.1.15." {
            !docs docs
            !decisions ../../docs/adr

            traefik = container "Traefik" "Reverse proxy for LAN and public HTTP(S) routes." "Traefik" {
                dockerProvider = component "Docker provider" "Discovers routes from container labels via the Docker socket." "Traefik provider"
                fileProvider = component "File provider" "Static route table for host-networked services (dynamic.yml)." "Traefik provider"
                webEntrypoint = component "Web entrypoint" "Port 80/443 listener; all LAN and tailnet HTTP enters here." "Traefik entrypoint"
                basicAuth = component "BasicAuth middleware" "Credential gate for routes without native auth (structurizr usersfile)." "Traefik middleware"
                acme = component "ACME resolver" "Let's Encrypt certificates for the public n8n route." "Traefik resolver"
            }
            portal = container "Service portal" "Static landing page for local services." "Nginx"
            homeAssistant = container "Home Assistant" "Home-automation platform; host-networked." "Home Assistant" {
                automations = component "Automation engine" "Event-driven rules (Pomodoro cube focus routine, ADR 0008)." "HA core"
                mqttIntegration = component "MQTT integration" "Subscribes to Zigbee2MQTT topics via Mosquitto." "HA integration"
                castIntegration = component "Cast integration" "Chromecast connectivity (currently retrying, see task register)." "HA integration"
                bluetooth = component "Bluetooth scanner" "hci0 scanner; lacks NET_ADMIN/NET_RAW (known issue)." "HA integration"
            }
            plex = container "Plex" "Media server; host-networked and backed by Elements media." "Plex" {
                pms = component "Media server" "Streams to LAN and authorised remote clients." "Plex Media Server"
                scanner = component "Library scanner" "Indexes the Elements media library." "Plex"
                transcoder = component "Transcoder" "On-the-fly format conversion for constrained clients." "Plex"
            }
            audiobookshelf = container "Audiobookshelf" "Audiobook and podcast library server; reads the Elements library and is reverse-proxied by Traefik." "Node.js" {
                absServer = component "Web/API server" "Library UI, playback API, and per-user progress." "Node.js"
                absScanner = component "Library scanner" "Watches and indexes /mnt/Elements/media/audiobooks." "Node.js"
            }
            n8n = container "n8n" "Workflow automation, available locally and publicly through Cloudflare DNS." "n8n" {
                editor = component "Editor UI" "Workflow authoring interface." "n8n"
                webhooks = component "Webhook listener" "Public HTTPS triggers via the Cloudflare route." "n8n"
                engine = component "Workflow engine" "Executes scheduled and triggered workflows." "n8n"
            }
            seerr = container "Seerr" "Family media discovery and request interface; authenticates users through Plex." "Seerr" {
                plexAuth = component "Plex sign-in" "Authenticates household users against Plex accounts." "Seerr"
                requests = component "Request engine" "Permission-limited request queue for family members." "Seerr"
                arrConnectors = component "Sonarr/Radarr connectors" "Forwards approved requests into the media pipeline." "Seerr"
            }
            zigbee = container "Zigbee2MQTT" "Zigbee bridge and web UI, connected to Mosquitto." "Zigbee2MQTT" {
                coordinator = component "Coordinator driver" "SONOFF ZBDongle-E serial interface (EmberZNet)." "Serial"
                mqttBridge = component "MQTT publisher" "Publishes device state and receives commands." "MQTT client"
                z2mFrontend = component "Frontend" "Device pairing and network management UI." "Web UI"
            }
            mosquitto = container "Mosquitto" "Local MQTT broker for Zigbee2MQTT and Home Assistant." "MQTT"
            structurizrServer = container "Structurizr Server" "Multi-workspace C4 publisher, open core built from source (ADR 0014); behind Traefik basicAuth." "Java" {
                workspacesApi = component "Workspace pages" "Dashboard, diagram viewer/editor, inspections." "Spring MVC"
                fileStorage = component "File storage" "Workspace JSON, properties, and thumbnails in the data directory." "Filesystem"
                publishPipeline = component "publish.sh pipeline" "Renders versioned DSL to workspace JSON (no push API in open core)." "Bash + structurizr export"
            }
            video = container "Video browser" "Read-only HTTP view of the Elements video library (Range/seek)." "Nginx"
            openspeedtest = container "OpenSpeedTest" "LAN speed test; direct :3000 and Traefik paths isolate proxy overhead from link problems." "Nginx"
            appShelf = container "App shelf" "Fire-tablet sideloading catalog and upload manager (ADR 0011)." "Nginx + Filebrowser"
            cloudflareDdns = container "Cloudflare DDNS" "Keeps the public n8n DNS record pointed at the home IP." "Container"

            group "HOME_MEDIA — VPN-only" {
                gluetun = container "Gluetun" "VPN gateway and kill-switch. All HOME_MEDIA outbound traffic and tests traverse this container." "VPN" {
                    vpnClient = component "VPN client" "OpenVPN tunnel to the provider (Belgium endpoint)." "OpenVPN"
                    killSwitch = component "Firewall kill-switch" "Blocks all egress outside the tunnel." "iptables"
                    controlServer = component "Control server" "Health and port-forward status API." "HTTP"
                }
                sonarr = container "Sonarr" "TV library automation; shares Gluetun's network namespace." "VPN-only" {
                    indexerClient = component "Indexer client" "Searches via Prowlarr Torznab feeds." "Torznab"
                    downloadClient = component "Download client" "Submits and monitors Deluge torrents." "Deluge RPC"
                    importer = component "Library importer" "Renames and moves completed downloads into the TV library." "Filesystem"
                }
                radarr = container "Radarr" "Movie library automation; shares Gluetun's network namespace." "VPN-only" {
                    indexerClient = component "Indexer client" "Searches via Prowlarr Torznab feeds." "Torznab"
                    downloadClient = component "Download client" "Submits and monitors Deluge torrents." "Deluge RPC"
                    importer = component "Library importer" "Renames and moves completed downloads into the movie library." "Filesystem"
                }
                prowlarr = container "Prowlarr" "Indexer manager; shares Gluetun's network namespace." "VPN-only" {
                    indexers = component "Indexer definitions" "Configured tracker/indexer endpoints." "Torznab/Newznab"
                    appSync = component "App sync" "Pushes indexer configuration to Sonarr and Radarr." "HTTP"
                    challengeProxy = component "Challenge proxy" "Routes protected indexers through FlareSolverr." "HTTP"
                }
                shelfarr = container "Shelfarr" "Audiobook and ebook request manager; shares Gluetun's network namespace." "VPN-only" {
                    requestManager = component "Request manager" "Audiobook/ebook request queue." "Web UI"
                    searcher = component "Indexer search" "Searches via Prowlarr." "Torznab"
                    absImporter = component "Audiobookshelf importer" "Imports completed downloads and triggers library scans." "HTTP"
                }
                deluge = container "Deluge" "Torrent client; shares Gluetun's network namespace." "VPN-only" {
                    daemon = component "Core daemon" "Torrent engine; all peer traffic via the VPN namespace." "libtorrent"
                    webUi = component "Web UI" "Management interface exposed through Traefik." "Web UI"
                }
                flareSolverr = container "FlareSolverr" "Browser-based challenge helper; shares Gluetun's network namespace." "VPN-only"
            }
        }

        lanClient -> router "Resolves host and service names" "DNS"
        router -> bumblebeam "Routes *.svc.home.arpa to" "DNS/HTTP"
        lanClient -> bumblebeam.traefik "Uses reverse-proxied services" "HTTP"
        lanClient -> bumblebeam.homeAssistant "Uses" "HTTP"
        lanClient -> bumblebeam.plex "Streams from" "HTTP"
        lanClient -> tailnet "Reaches the LAN remotely through" "WireGuard"
        tailnet -> bumblebeam "Subnet-routes 192.168.1.0/24 via" "WireGuard"
        bumblebeam.traefik -> bumblebeam.portal "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.homeAssistant "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.plex "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.audiobookshelf "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.n8n "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.seerr "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.structurizrServer "Routes (behind BasicAuth) to" "HTTP"
        bumblebeam.traefik -> bumblebeam.video "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.openspeedtest "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.appShelf "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.gluetun "Routes media UIs to" "HTTP"
        cloudflare -> bumblebeam.traefik "Resolves public n8n route to" "DNS/HTTPS"
        bumblebeam.cloudflareDdns -> cloudflare "Updates the public DNS record via" "HTTPS API"
        bumblebeam.zigbee -> bumblebeam.mosquitto "Publishes and subscribes" "MQTT"
        bumblebeam.homeAssistant -> bumblebeam.mosquitto "Uses" "MQTT"
        bumblebeam.sonarr -> bumblebeam.gluetun "Shares network namespace with" "Docker netns"
        bumblebeam.radarr -> bumblebeam.gluetun "Shares network namespace with" "Docker netns"
        bumblebeam.prowlarr -> bumblebeam.gluetun "Shares network namespace with" "Docker netns"
        bumblebeam.shelfarr -> bumblebeam.gluetun "Shares network namespace with" "Docker netns"
        bumblebeam.deluge -> bumblebeam.gluetun "Shares network namespace with" "Docker netns"
        bumblebeam.flareSolverr -> bumblebeam.gluetun "Shares network namespace with" "Docker netns"
        bumblebeam.radarr -> bumblebeam.prowlarr "Uses indexers from" "HTTP"
        bumblebeam.sonarr -> bumblebeam.prowlarr "Uses indexers from" "HTTP"
        bumblebeam.seerr -> bumblebeam.plex "Reads library and authenticates users through" "HTTP"
        bumblebeam.seerr -> bumblebeam.gluetun "Connects to Sonarr and Radarr through" "HTTP"
        bumblebeam.prowlarr -> bumblebeam.flareSolverr "Uses when required" "HTTP"
        bumblebeam.sonarr -> bumblebeam.deluge "Submits downloads to" "HTTP"
        bumblebeam.radarr -> bumblebeam.deluge "Submits downloads to" "HTTP"
        bumblebeam.shelfarr -> bumblebeam.prowlarr "Searches indexers through" "HTTP"
        bumblebeam.shelfarr -> bumblebeam.deluge "Submits downloads to" "HTTP"
        bumblebeam.shelfarr -> bumblebeam.audiobookshelf "Triggers library scans on" "HTTP"
        bumblebeam.gluetun -> mediaInternet "All HOME_MEDIA outbound traffic and tests" "VPN"

        # Component-level wiring (internal structure + cross-container edges)
        bumblebeam.traefik.dockerProvider -> bumblebeam.traefik.webEntrypoint "Registers label-derived routes on" "In-process"
        bumblebeam.traefik.fileProvider -> bumblebeam.traefik.webEntrypoint "Registers host-service routes on" "In-process"
        bumblebeam.traefik.webEntrypoint -> bumblebeam.traefik.basicAuth "Applies to protected routes" "In-process"
        bumblebeam.traefik.basicAuth -> bumblebeam.structurizrServer.workspacesApi "Forwards authenticated requests to" "HTTP"
        bumblebeam.traefik.acme -> cloudflare "Answers DNS-01 challenges via" "HTTPS API"
        bumblebeam.homeAssistant.mqttIntegration -> bumblebeam.mosquitto "Subscribes to device topics on" "MQTT"
        bumblebeam.homeAssistant.automations -> bumblebeam.homeAssistant.mqttIntegration "Reacts to cube orientation events from" "In-process"
        bumblebeam.zigbee.coordinator -> bumblebeam.zigbee.mqttBridge "Feeds device events to" "In-process"
        bumblebeam.zigbee.mqttBridge -> bumblebeam.mosquitto "Publishes to" "MQTT"
        bumblebeam.plex.scanner -> bumblebeam.plex.pms "Maintains the library index for" "In-process"
        bumblebeam.plex.pms -> bumblebeam.plex.transcoder "Delegates incompatible streams to" "In-process"
        bumblebeam.audiobookshelf.absScanner -> bumblebeam.audiobookshelf.absServer "Maintains the library for" "In-process"
        bumblebeam.n8n.editor -> bumblebeam.n8n.engine "Deploys workflows to" "In-process"
        bumblebeam.n8n.webhooks -> bumblebeam.n8n.engine "Triggers" "In-process"
        bumblebeam.seerr.plexAuth -> bumblebeam.plex.pms "Verifies accounts against" "HTTP"
        bumblebeam.seerr.requests -> bumblebeam.seerr.arrConnectors "Hands approved requests to" "In-process"
        bumblebeam.seerr.arrConnectors -> bumblebeam.sonarr.indexerClient "Creates series requests in" "HTTP"
        bumblebeam.seerr.arrConnectors -> bumblebeam.radarr.indexerClient "Creates movie requests in" "HTTP"
        bumblebeam.sonarr.indexerClient -> bumblebeam.prowlarr.indexers "Searches" "Torznab"
        bumblebeam.radarr.indexerClient -> bumblebeam.prowlarr.indexers "Searches" "Torznab"
        bumblebeam.sonarr.downloadClient -> bumblebeam.deluge.daemon "Submits and monitors torrents on" "Deluge RPC"
        bumblebeam.radarr.downloadClient -> bumblebeam.deluge.daemon "Submits and monitors torrents on" "Deluge RPC"
        bumblebeam.sonarr.importer -> bumblebeam.plex.scanner "Feeds new episodes to" "Filesystem"
        bumblebeam.radarr.importer -> bumblebeam.plex.scanner "Feeds new movies to" "Filesystem"
        bumblebeam.prowlarr.appSync -> bumblebeam.sonarr.indexerClient "Pushes indexer config to" "HTTP"
        bumblebeam.prowlarr.appSync -> bumblebeam.radarr.indexerClient "Pushes indexer config to" "HTTP"
        bumblebeam.prowlarr.challengeProxy -> bumblebeam.flareSolverr "Solves challenges via" "HTTP"
        bumblebeam.shelfarr.searcher -> bumblebeam.prowlarr.indexers "Searches" "Torznab"
        bumblebeam.shelfarr.requestManager -> bumblebeam.deluge.daemon "Submits downloads to" "Deluge RPC"
        bumblebeam.shelfarr.absImporter -> bumblebeam.audiobookshelf.absScanner "Triggers scans on" "HTTP"
        bumblebeam.gluetun.vpnClient -> mediaInternet "Tunnels all namespace egress to" "OpenVPN"
        bumblebeam.gluetun.killSwitch -> bumblebeam.gluetun.vpnClient "Restricts egress to" "iptables"
        bumblebeam.gluetun.controlServer -> bumblebeam.gluetun.vpnClient "Reports tunnel health of" "In-process"
        bumblebeam.homeAssistant.castIntegration -> lanClient "Casts to household displays of" "Cast protocol"
        bumblebeam.homeAssistant.bluetooth -> lanClient "Scans for BLE devices of (currently failing: missing NET_ADMIN/NET_RAW)" "Bluetooth"
        lanClient -> bumblebeam.zigbee.z2mFrontend "Manages Zigbee devices via" "HTTP"
        bumblebeam.traefik.webEntrypoint -> bumblebeam.deluge.webUi "Routes deluge UI to (via the Gluetun namespace)" "HTTP"
        bumblebeam.deluge.webUi -> bumblebeam.deluge.daemon "Controls" "In-process"
        bumblebeam.structurizrServer.workspacesApi -> bumblebeam.structurizrServer.fileStorage "Reads and writes workspaces in" "Filesystem"
        bumblebeam.structurizrServer.publishPipeline -> bumblebeam.structurizrServer.fileStorage "Places rendered workspace JSON in" "Filesystem"
    }

    views {
        systemContext bumblebeam "SystemContext" {
            include *
            autolayout lr
        }

        container bumblebeam "Containers" {
            include *
            autolayout lr
        }

        component bumblebeam.traefik "TraefikComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.gluetun "GluetunComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.homeAssistant "HomeAssistantComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.plex "PlexComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.audiobookshelf "AudiobookshelfComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.n8n "N8nComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.seerr "SeerrComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.zigbee "ZigbeeComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.sonarr "SonarrComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.radarr "RadarrComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.prowlarr "ProwlarrComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.shelfarr "ShelfarrComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.deluge "DelugeComponents" {
            include *
            autolayout lr
        }
        component bumblebeam.structurizrServer "StructurizrServerComponents" {
            include *
            autolayout lr
        }

        styles {
            element "Person" {
                shape person
                background #08427b
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Traefik" {
                background #24a1c1
                color #ffffff
            }
            element "VPN" {
                background #3b7a57
                color #ffffff
            }
            element "VPN-only" {
                background #5b8c5a
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
            relationship "VPN" {
                color #3b7a57
                thickness 4
            }
        }
    }

    configuration {
        scope softwaresystem
    }
}
