@echo off
chcp 65001 >nul
title Volta Node 版本选择
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0volta-node-menu.ps1" %*
if errorlevel 1 pause
