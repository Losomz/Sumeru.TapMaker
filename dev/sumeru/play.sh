#!/usr/bin/env bash
# Git Bash 启动入口：转调 play.ps1（避开 Git Bash 传中文文件名给 cmd 的乱码）。
# 用法：bash dev/sumeru/play.sh [宽] [高]
set -u
DIR="$(cd "$(dirname "$0")" && pwd -W)"
ARGS=()
[ -n "${1:-}" ] && ARGS+=(-Width "$1")
[ -n "${2:-}" ] && ARGS+=(-Height "$2")
MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$DIR/play.ps1" "${ARGS[@]}"
