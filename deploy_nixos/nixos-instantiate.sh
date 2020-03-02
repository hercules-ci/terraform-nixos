#! /usr/bin/env bash
set -euo pipefail

# Args
nix_path=$1
config=$2
config_pwd=$3
shift
shift
shift

if ! type "nix-instantiate" > /dev/null; then
  echo 1>&2 "WARNING: nix-instantiate not found."
  echo 1>&2 "NOTE: Fetching static nix."
  tarball_url="https://gist.github.com/roberth/422f3bab3ed8e9c0af5790bda0ce37cd/raw/a94e867018677cc562699acf64b63d7cb1e829cb/nix.tar"

  store="$HOME/.my-store"
  export NIX_CONF_DIR=~/.static-nix/etc/nix
  nix_conf="$NIX_CONF_DIR/nix.conf"
  export NIX_DATA_DIR=~/.static-nix/result/share
  export NIX_LOG_DIR=~/.my-store/log
  export NIX_STATE_DIR=~/.my-store/var
  export PATH="$HOME/.static-nix/result/bin:$PATH"
  mkdir -p ~/.static-nix
  curl -L "$tarball_url" | tar -xC ~/.static-nix
  mkdir -p "$NIX_DATA_DIR" "$store" "$NIX_CONF_DIR" "$NIX_LOG_DIR" "$NIX_STATE_DIR"
  echo "store = $store" >"$nix_conf"
fi

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
