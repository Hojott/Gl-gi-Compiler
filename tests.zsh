#!/bin/zsh
# Test glögicompiler

./make.zsh

echo "-- Test 1 --"
./glögi.zsh -fd dest src.gl
echo ""

echo "-- Test 2 --"
./glögi.zsh -fvDd dest src.gl

