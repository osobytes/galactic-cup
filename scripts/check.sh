#!/usr/bin/env bash
# Project quality gate: format-check, type-check, tests, fun tripwire.
# Each step is skipped (with a warning) if its tool isn't installed, so the
# script is usable during bootstrap and strict once everything is present.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

echo "==> StyLua (format check)"
if command -v stylua >/dev/null 2>&1; then
    stylua --check . || fail=1
else
    echo "   ! stylua not installed — skipping"
fi

echo "==> lua-language-server (type check)"
if command -v lua-language-server >/dev/null 2>&1; then
    lua-language-server --check . --checklevel=Warning || fail=1
else
    echo "   ! lua-language-server not installed — skipping"
fi

echo "==> Tests (love . --test)"
if command -v love >/dev/null 2>&1; then
    love . --test || fail=1
else
    echo "   ! love not installed — skipping"
fi

echo "==> Fun tripwire (love . --tripwire)"
if command -v love >/dev/null 2>&1; then
    love . --tripwire || fail=1
else
    echo "   ! love not installed — skipping"
fi

if [ "$fail" -ne 0 ]; then
    echo "CHECK FAILED"
    exit 1
fi
echo "CHECK OK"
