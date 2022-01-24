#!/usr/bin/env bash
set -euo pipefail

echo 'Generating Go'
../../gopikchr-working/bin/lemongo pikchr.y

echo 'Running Go'
go build -gcflags="-e" ./pikchr.go
