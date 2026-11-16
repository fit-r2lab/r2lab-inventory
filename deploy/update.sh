#!/bin/bash
#
# Apply the current checkout to this box: compute the config files from the
# sources in this repo, install them under /etc, and restart the services
# that depend on them.
#
# Called by r2lab-embedded/services/run-updates.sh after it has moved this
# repo to the latest origin commit; can also be run by hand to force a redeploy.
# The git update itself is NOT done here, since resetting a repo under a
# running script is unsafe.
#
# This runs both on faraday (prod) and on the preplab gateway (prep), and
# which one we are on is figured out from the services that are enabled, like
# the other update.sh scripts do, and not from the hostname: prod runs both
# monitorphones and monitorpdus, the preplab runs none of them. Anything else
# is a mistake and nothing is touched. For manual use, --prod or --prep
# bypasses the detection.
#
# Brute force on purpose: all files are recomputed and reinstalled every time,
# and all the units that are enabled are restarted, even if nothing changed.
# The relaystemperatures timer is not restarted: its service is spawned anew
# at each cycle, and so picks up the new inventory by itself.
# NetworkManager comes first, restarting it also cleans up the leases file;
# otherwise a new node may need to wait for some time before it gets served
# its address and could get stuff like 192.168.3.251 instead
#

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."

export PATH="/root/.local/bin:$PATH"

UNITS="NetworkManager monitornodes monitorphones monitorpdus relaysapi"

enabled() {
    systemctl is-enabled --quiet "$1"
}

detect_platform() {
    if enabled monitorphones && enabled monitorpdus; then
        echo prod
    elif ! enabled monitorphones && ! enabled monitorpdus; then
        echo prep
    else
        echo "update.sh: monitorphones and monitorpdus should be both enabled (prod) or both not (prep)" >&2
        return 1
    fi
}

case "${1:-}" in
    --prod) platform=prod ;;
    --prep) platform=prep ;;
    "")     platform=$(detect_platform) ;;
    *)      echo "usage: $0 [--prod|--prep]" >&2; exit 1 ;;
esac
echo "update.sh: installing the inventory for $platform"

uv sync --frozen
uv run inventory install "--$platform"

to_restart=""
skipped=""
for unit in $UNITS; do
    if enabled "$unit"; then
        to_restart="$to_restart $unit"
    else
        skipped="$skipped $unit"
    fi
done

[ -n "$skipped" ] && echo "update.sh: skipping (not installed or not enabled):$skipped"

# one at a time, in order, so that NetworkManager is done first
for unit in $to_restart; do
    systemctl restart "$unit"
done
