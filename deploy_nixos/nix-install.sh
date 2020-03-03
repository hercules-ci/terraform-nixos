#! /usr/bin/env false

if ! type "nix-instantiate" > /dev/null; then
  echo 1>&2 "WARNING: nix-instantiate not found."
  echo 1>&2 "NOTE: Fetching static nix."
  tarball_url="https://gist.github.com/roberth/422f3bab3ed8e9c0af5790bda0ce37cd/raw/8601326c6ea35056212a9944fe82cb04dd0fc8ad/nix.tar"

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
