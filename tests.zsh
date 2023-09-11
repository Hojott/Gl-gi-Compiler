#!/bin/zsh
# Test glögicompiler

./make.zsh

echo "-- Test 1 --"
./glögi.zsh -vd dest src.gl
echo ""

