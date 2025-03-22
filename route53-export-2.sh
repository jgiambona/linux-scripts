#!/bin/bash

if [[ "$1" == "" ]]; then
    echo "Write a domain name after the script path. Example:"
    echo "      ./script.sh example.com"
    exit 0
fi

hostedzoneid=$(aws route53 list-hosted-zones --profile ndc --output json | jq -r ".HostedZones[] | select(.Name == \"$1.\") | .Id" | cut -d'/' -f3)

aws route53 list-resource-record-sets --profile ndc --hosted-zone-id $hostedzoneid | \
    jq -jr '.ResourceRecordSets[] | "\(.Name) \t\(.TTL) \tIN \t\(.Type) \t\(.ResourceRecords[]?.Value)\n"' | \
    sed "s|^$1. |@ |g; s|.$1.||g; s|172800|3600|g" | \
    sed 's|\\052|*|g'
