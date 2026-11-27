@echo off
cd /d "%~dp0..\app"
dart run tool/lan_sync_server.dart --root ..\testdata\public %*
