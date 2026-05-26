#!/bin/bash

if [[ "$1" == "" ]]; then
    echo "Write a domain name after the script path. Example:"
    echo "      ./script.sh example.com"
    exit 0
fi

read -rp "AWS CLI profile (press Enter for none): " _profile
_profile_args=()
[[ -n "$_profile" ]] && _profile_args=(--profile "$_profile")

hostedzoneid=$(aws route53 list-hosted-zones "${_profile_args[@]}" --output json | jq -r ".HostedZones[] | select(.Name == \"$1.\") | .Id" | cut -d'/' -f3)

aws route53 list-resource-record-sets "${_profile_args[@]}" --hosted-zone-id $hostedzoneid | \
    jq -jr '.ResourceRecordSets[] | "\(.Name) \t\(.TTL) \tIN \t\(.Type) \t\(.ResourceRecords[]?.Value)\n"' | \
    sed "s|^$1. |@ |g; s|.$1.||g; s|172800|3600|g" | \
    sed 's|\\052|*|g'
