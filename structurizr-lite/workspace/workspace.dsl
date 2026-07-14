workspace "Bumblebeam home infrastructure" "Architecture of the Bumblebeam host and its services." {

    !identifiers hierarchical

    model {
        lanClient = person "LAN client" "A household device using Bumblebeam services."

        router = softwareSystem "GL.iNet router" "Provides DHCP, LAN DNS, and the svc.home.arpa service namespace." "External"
        cloudflare = softwareSystem "Cloudflare" "Provides DNS and the public n8n route." "External"
        mediaInternet = softwareSystem "Media services and indexers" "Metadata, indexer, tracker, and download endpoints." "External"

        bumblebeam = softwareSystem "Bumblebeam" "The home-infrastructure host at 192.168.1.15." {
            traefik = container "Traefik" "Reverse proxy for LAN and public HTTP(S) routes." "Traefik"
            portal = container "Service portal" "Static landing page for local services." "Nginx"
            homeAssistant = container "Home Assistant" "Home-automation platform; host-networked." "Home Assistant"
            plex = container "Plex" "Media server; host-networked and backed by Elements media." "Plex"
            n8n = container "n8n" "Workflow automation, available locally and publicly through Cloudflare DNS." "n8n"
            seerr = container "Seerr" "Family media discovery and request interface; authenticates users through Plex." "Seerr"
            zigbee = container "Zigbee2MQTT" "Zigbee bridge and web UI, connected to Mosquitto." "Zigbee2MQTT"
            mosquitto = container "Mosquitto" "Local MQTT broker for Zigbee2MQTT and Home Assistant." "MQTT"

            group "HOME_MEDIA — VPN-only" {
                gluetun = container "Gluetun" "VPN gateway and kill-switch. All HOME_MEDIA outbound traffic and tests traverse this container." "VPN"
                sonarr = container "Sonarr" "TV library automation; shares Gluetun's network namespace." "VPN-only"
                radarr = container "Radarr" "Movie library automation; shares Gluetun's network namespace." "VPN-only"
                prowlarr = container "Prowlarr" "Indexer manager; shares Gluetun's network namespace." "VPN-only"
                deluge = container "Deluge" "Torrent client; shares Gluetun's network namespace." "VPN-only"
                flareSolverr = container "FlareSolverr" "Browser-based challenge helper; shares Gluetun's network namespace." "VPN-only"
            }
        }

        lanClient -> router "Resolves host and service names"
        router -> bumblebeam "Routes *.svc.home.arpa to"
        lanClient -> bumblebeam.traefik "Uses reverse-proxied services" "HTTP"
        lanClient -> bumblebeam.homeAssistant "Uses" "HTTP"
        lanClient -> bumblebeam.plex "Streams from" "HTTP"
        bumblebeam.traefik -> bumblebeam.portal "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.homeAssistant "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.plex "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.n8n "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.seerr "Routes to" "HTTP"
        bumblebeam.traefik -> bumblebeam.gluetun "Routes media UIs to" "HTTP"
        cloudflare -> bumblebeam.traefik "Resolves public n8n route to" "DNS/HTTPS"
        bumblebeam.zigbee -> bumblebeam.mosquitto "Publishes and subscribes" "MQTT"
        bumblebeam.homeAssistant -> bumblebeam.mosquitto "Uses" "MQTT"
        bumblebeam.sonarr -> bumblebeam.gluetun "Shares network namespace with"
        bumblebeam.radarr -> bumblebeam.gluetun "Shares network namespace with"
        bumblebeam.prowlarr -> bumblebeam.gluetun "Shares network namespace with"
        bumblebeam.deluge -> bumblebeam.gluetun "Shares network namespace with"
        bumblebeam.flareSolverr -> bumblebeam.gluetun "Shares network namespace with"
        bumblebeam.radarr -> bumblebeam.prowlarr "Uses indexers from" "HTTP"
        bumblebeam.sonarr -> bumblebeam.prowlarr "Uses indexers from" "HTTP"
        bumblebeam.seerr -> bumblebeam.plex "Reads library and authenticates users through" "HTTP"
        bumblebeam.seerr -> bumblebeam.gluetun "Connects to Sonarr and Radarr through" "HTTP"
        bumblebeam.prowlarr -> bumblebeam.flareSolverr "Uses when required" "HTTP"
        bumblebeam.sonarr -> bumblebeam.deluge "Submits downloads to" "HTTP"
        bumblebeam.radarr -> bumblebeam.deluge "Submits downloads to" "HTTP"
        bumblebeam.gluetun -> mediaInternet "All HOME_MEDIA outbound traffic and tests" "VPN"
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
            relationship "VPN" {
                color #3b7a57
                thickness 4
            }
        }
    }
}
