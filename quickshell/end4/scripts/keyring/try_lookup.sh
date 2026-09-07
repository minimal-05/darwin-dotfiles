#!/usr/bin/env bash

data=$(secret-tool lookup 'application' 'illogical-impulse')
if [[ -z "$data" ]]; then
    echo 'not found'
    exit 1
fi
echo "$data"
