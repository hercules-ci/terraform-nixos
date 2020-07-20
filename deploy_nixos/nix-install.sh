#! /usr/bin/env false

if ! type "nix-instantiate" > /dev/null; then
  export PATH="$HOME/.static-nix/result/bin:$PATH"
  export NIX_CONF_DIR=~/.static-nix/etc/nix
  export NIX_DATA_DIR=~/.static-nix/result/share
  export NIX_LOG_DIR=~/.my-store/log
  export NIX_STATE_DIR=~/.my-store/var
fi

(
  exec 100>/tmp/nix-install.lock || exit 1
  flock 100 || exit 1

  if ! type "nix-instantiate" > /dev/null; then
    echo 1>&2 "WARNING: nix-instantiate not found."
    echo 1>&2 "NOTE: Fetching static nix."
    tarball_url="https://gist.github.com/roberth/422f3bab3ed8e9c0af5790bda0ce37cd/raw/ce50c6852b4281edefb2254a5de60cf5dca05c40/nix-2.3.7-patched.tar.gz"

    store="$HOME/.my-store"
    nix_conf="$NIX_CONF_DIR/nix.conf"
    mkdir -p ~/.static-nix
    curl -L "$tarball_url" | tar -xzC ~/.static-nix
    mkdir -p "$NIX_DATA_DIR" "$store" "$NIX_CONF_DIR" "$NIX_LOG_DIR" "$NIX_STATE_DIR"
    echo "store = $store" >"$nix_conf"
    # Use the store to initialize it without concurrency
    nix-store -r /nix/store/lrvcml3jjd9vydygrwnv2x603dpfxx3d-hook --add-root ~/bogus --indirect >/dev/null
    rm ~/bogus
  fi
)

echo 1>&2 "Nix version:"
nix-instantiate --version 1>&2
