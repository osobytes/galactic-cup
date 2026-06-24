#!/usr/bin/env bash
# Bootstraps the dev environment with NO sudo. Idempotent — safe to re-run.
# Installs into ~/.local (bin on PATH). Targets: LÖVE 11.5, StyLua, LuaLS, type defs.
set -uo pipefail
cd "$(dirname "$0")/.."

BIN="$HOME/.local/bin"
LIB="$HOME/.local/lib"
mkdir -p "$BIN" "$LIB" types

LOVE_VERSION="11.5"

echo "==> LÖVE $LOVE_VERSION (AppImage)"
if ! command -v love >/dev/null 2>&1; then
    curl -fL --retry 2 -o "$BIN/love" \
        "https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-x86_64.AppImage"
    chmod +x "$BIN/love"
fi
love --version || echo "   ! love installed but failed to run (FUSE? try: love --appimage-extract-and-run)"

echo "==> LÖVE type definitions (LuaCATS)"
if [ ! -d types/love2d ]; then
    git clone --depth 1 -q https://github.com/LuaCATS/love2d types/love2d
    rm -rf types/love2d/.git
fi
echo "   $(find types/love2d -name '*.lua' | wc -l) definition files"

echo "==> StyLua"
if ! command -v stylua >/dev/null 2>&1; then
    curl -fsSL -o /tmp/stylua.zip \
        https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-linux-x86_64.zip
    (cd /tmp && unzip -oq stylua.zip && mv stylua "$BIN/" && chmod +x "$BIN/stylua")
fi
stylua --version

echo "==> lua-language-server"
if ! command -v lua-language-server >/dev/null 2>&1; then
    ver=$(curl -fsSL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest \
        | grep -m1 '"tag_name"' | sed -E 's/.*"([0-9.]+)".*/\1/')
    mkdir -p "$LIB/lua-language-server"
    curl -fsSL -o /tmp/luals.tar.gz \
        "https://github.com/LuaLS/lua-language-server/releases/download/${ver}/lua-language-server-${ver}-linux-x64.tar.gz"
    tar -xzf /tmp/luals.tar.gz -C "$LIB/lua-language-server"
    ln -sf "$LIB/lua-language-server/bin/lua-language-server" "$BIN/lua-language-server"
fi
lua-language-server --version

echo "==> Busted (optional, needs luarocks)"
if command -v busted >/dev/null 2>&1; then
    busted --version
elif command -v luarocks >/dev/null 2>&1; then
    luarocks install --local busted && echo "   installed busted"
else
    echo "   ! luarocks not found — tests skipped until 'sudo apt install luarocks && luarocks install --local busted'"
fi

echo "==> Done. Ensure ~/.local/bin is on PATH."
