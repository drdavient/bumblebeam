#!/usr/bin/env bash
set -euo pipefail

ensure_network() {
  local name=$1
  local bridge=$2
  local subnet=$3
  local gateway=$4

  if docker network inspect "$name" >/dev/null 2>&1; then
    local actual
    actual=$(docker network inspect "$name" --format '{{(index .IPAM.Config 0).Subnet}} {{(index .IPAM.Config 0).Gateway}} {{index .Options "com.docker.network.bridge.name"}}')
    local expected="$subnet $gateway $bridge"
    if [[ "$actual" != "$expected" ]]; then
      printf 'Network %s exists with unexpected identity: %s (expected %s)\n' \
        "$name" "$actual" "$expected" >&2
      exit 2
    fi
    printf 'Network %s already matches the pinned identity\n' "$name"
    return
  fi

  docker network create \
    --driver bridge \
    --opt "com.docker.network.bridge.name=$bridge" \
    --subnet "$subnet" \
    --gateway "$gateway" \
    "$name" >/dev/null
  printf 'Created network %s (%s, %s)\n' "$name" "$bridge" "$subnet"
}

ensure_network gluetun-net br-gluetun 172.18.0.0/16 172.18.0.1
ensure_network traefik-net br-traefik 172.26.0.0/16 172.26.0.1
