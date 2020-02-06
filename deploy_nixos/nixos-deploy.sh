#!/usr/bin/env bash
# nixos-deploy deploys a nixos-instantiate-generated drvPath to a target host
#
# Usage: nixos-deploy.sh <drvPath> <host> <switch-action> [<build-opts>] ignoreme
set -euo pipefail

### Defaults ###

buildArgs=(
  --option extra-binary-caches https://cache.nixos.org/
)
profile=/nix/var/nix/profiles/system
sshOpts=(
  -o "ControlMaster=auto"
  -o "ControlPersist=60"
  -o "ControlPath=${HOME}/.ssh/deploy_nixos_%C"
  # Avoid issues with IP re-use. This disable TOFU security.
  -o "StrictHostKeyChecking=no"
  -o "UserKnownHostsFile=/dev/null"
  -o "GlobalKnownHostsFile=/dev/null"
  # interactive authentication is not possible
  -o "BatchMode=yes"
  # verbose output for easier debugging
  -v
)

###  Argument parsing ###

drvPath="$1"
targetHost="$2"
sshPrivateKeyFile="$3"
action="$4"
shift
shift
shift
shift
# remove the last argument
set -- "${@:1:$(($# - 1))}"
buildArgs+=("$@")

if [ -n "${sshPrivateKeyFile}" ]; then
    sshOpts+=( -o "IdentityFile=${sshPrivateKeyFile}" )
fi

### Functions ###

log() {
  echo "--- $*" >&2
}

copyToTarget() {
  NIX_SSHOPTS="${sshOpts[*]}" nix-copy-closure --to "$targetHost" "$@"
}

# assumes that passwordless sudo is enabled on the server
targetHostCmd() {
  # shellcheck disable=SC2029
  # ${*@Q} escapes the arguments losslessly into space-separted quoted strings.
  # `ssh` did not properly maintain the array nature of the command line,
  # erroneously splitting arguments with internal spaces, even when using `--`.
  # Tested with OpenSSH_7.9p1.
  ssh "${sshOpts[@]}" "$targetHost" "./maybe-sudo.sh ${*@Q}"
}

### Main ###

# Ensure the local SSH directory exists
# shellcheck disable=SC2174
#                    ^^^^^^ -m only applies to deepest directory
mkdir -m 0700 -p "$HOME"/.ssh

# Build derivation
log "building nix code"
outPath=$(nix-store --realize "$drvPath" "${buildArgs[@]}")

# Upload build results
log "uploading build results"
copyToTarget "$outPath" --gzip --use-substitutes

# Activate
log "activating configuration"
targetHostCmd nix-env --profile "$profile" --set "$outPath"
targetHostCmd "$outPath/bin/switch-to-configuration" "$action"

# Cleanup previous generations
log "collecting old nix derivations"
targetHostCmd "nix-collect-garbage" "-d"
