#!/bin/bash

# Script to build and update the kdb+ plugin in a Grafana container
# Requires yarn/go/docker; installs frontend deps if missing (runs yarn install when needed).
# In docker-compose set GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=aquaqanalytics-kdbbackend-datasource to allow this unsigned plugin.

set -e  # Exit on error

if [ -z "$1" ]; then
	echo "Usage: $(basename "$0") <grafana-container-name>"
	echo "Also ensure GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=aquaqanalytics-kdbbackend-datasource is set in docker-compose."
	exit 1
fi

GRAFANA_CONTAINER="$1"

if [ ! -x "node_modules/.bin/grafana-toolkit" ]; then
	echo "Installing frontend dependencies (yarn install)..."
	yarn install --frozen-lockfile || yarn install
fi

echo "Building frontend..."
export NODE_OPTIONS=--openssl-legacy-provider
yarn build

echo "Detecting Grafana container platform..."
PLATFORM=$(docker inspect --format '{{.Os}}/{{.Architecture}}' "${GRAFANA_CONTAINER}" 2>/dev/null || true)
if [ -z "$PLATFORM" ]; then
	echo "Could not read platform from docker inspect; trying uname inside container..."
	UNAME_M=$(docker exec "${GRAFANA_CONTAINER}" uname -m 2>/dev/null || true)
	case "$UNAME_M" in
		x86_64) GOARCH=amd64 ;;
		aarch64|arm64) GOARCH=arm64 ;;
		armv7l|armv7) GOARCH=arm ;;
		s390x) GOARCH=s390x ;;
		ppc64le) GOARCH=ppc64le ;;
		riscv64) GOARCH=riscv64 ;;
		*) GOARCH="$UNAME_M" ;;
	esac
	GOOS=linux
else
	GOOS=$(echo "$PLATFORM" | cut -d'/' -f1)
	GOARCH=$(echo "$PLATFORM" | cut -d'/' -f2)
fi

EXT=""
if [ "$GOOS" = "windows" ]; then
	EXT=".exe"
fi

mkdir -p dist

# Remove old backend binaries to avoid confusion
echo "Cleaning old backend binaries from dist/..."
rm -f dist/gpx_kdbbackend-datasource_* 2>/dev/null || true

OUT="dist/gpx_kdbbackend-datasource_${GOOS}_${GOARCH}${EXT}"
echo "Building backend for ${GOOS}/${GOARCH} -> ${OUT}"
GOOS=$GOOS GOARCH=$GOARCH go build -o "$OUT" ./pkg

echo "Copying plugin to Grafana container..."
docker cp dist/. "${GRAFANA_CONTAINER}:/var/lib/grafana/plugins/aquaqanalytics-kdbbackend-datasource/"

echo "Restarting Grafana container..."
docker restart "${GRAFANA_CONTAINER}"

echo "Plugin updated successfully!"
echo "Waiting for Grafana to start..."
sleep 5

echo "Checking plugin status..."
docker logs "${GRAFANA_CONTAINER}" 2>&1 | grep -i "Plugin registered.*aquaq" || echo "Plugin registration not found in recent logs"

if ! docker inspect "${GRAFANA_CONTAINER}" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q "GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=aquaqanalytics-kdbbackend-datasource"; then
	echo "Issue: GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=aquaqanalytics-kdbbackend-datasource is not set on the Grafana container; add it in docker-compose and restart Grafana."
fi

echo "Done!"
