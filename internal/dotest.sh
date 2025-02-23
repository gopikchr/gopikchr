#!/usr/bin/env bash
set -euo pipefail

echo 'Generating Go'
../../golemon/bin/golemon pikchr.y
go fmt ./pikchr.go

echo 'Building Go'
go build -gcflags="-e" ./pikchr.go
