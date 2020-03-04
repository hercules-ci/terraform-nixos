#! /usr/bin/env bash
set -euo pipefail

# Args
nix_path=$1
config=$2
config_pwd=$3
shift 3

source "$(dirname "${BASH_SOURCE[0]}")/nix-install.sh"

# Building the command
command=(nix-instantiate --show-trace --expr '
  { system, configuration, ... }:
  let
    os = import <nixpkgs/nixos> { inherit system configuration; };
    inherit (import <nixpkgs/lib>) concatStringsSep;
  in {
    substituters = concatStringsSep " " os.config.nix.binaryCaches;
    trusted-public-keys = concatStringsSep " " os.config.nix.binaryCachePublicKeys;
    drv_path = os.system.drvPath;
    out_path = os.system;
    inherit (builtins) currentSystem;
  }')

if [[ -f "$config" ]]; then
  config=$(readlink -f "$config")
  command+=(--argstr configuration "$config")
else
  command+=(--arg configuration "$config")
fi

# add all extra CLI args as extra build arguments
command+=("$@")

# Setting the NIX_PATH
if [[ -n "$nix_path" && "$nix_path" != "-" ]]; then
  export NIX_PATH=$nix_path
fi

# Changing directory
cd "$(readlink -f "$config_pwd")"

# Instantiate
echo "running (instantiating): ${NIX_PATH:+NIX_PATH=$NIX_PATH} ${command[*]@Q}" -A out_path >&2
"${command[@]}" -A out_path >/dev/null

# Evaluate some more details,
# relying on preceding "Instantiate" command to perform the instantiation,
# because `--eval` is required but doesn't instantiate for some reason.
echo "running (evaluating): ${NIX_PATH:+NIX_PATH=$NIX_PATH} ${command[*]@Q}" --eval --strict --json >&2
"${command[@]}" --eval --strict --json
