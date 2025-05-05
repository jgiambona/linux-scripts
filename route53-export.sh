#!/bin/bash
#
# route53-export.sh
#
# Author: Jason Giambona (@jgiambona)
#
# Description:
#   Export AWS Route 53 DNS records from a hosted zone in various formats.
#   Supports raw JSON export, BIND zone files, CSV for auditing, YAML for Terraform,
#   and PowerDNS zone format.
#
# Usage:
#   ./route53-export.sh [--profile PROFILE] (--id ZONE_ID | --domain DOMAIN_NAME)
#                       [--format FORMAT] [--output FILE] [--no-save]
#
# Supported Formats:
#   --format bind       BIND zone file (default)
#   --format csv        CSV with name, type, ttl, value
#   --format json       Raw AWS Route 53 JSON
#   --format powerdns   PowerDNS-style zone records
#   --format yaml       YAML array (Terraform-compatible)
#
# Output:
#   By default, saves to a file like domain.tld.zone or domain.tld.csv
#   Use --no-save to print to stdout instead
#
# Dependencies:
#   - AWS CLI
#   - jq
#
# License:
#   MIT (or your preferred open license)
#
# Version: 1.0

set -euo pipefail

usage() {
  echo >&2 "
Usage:
  $(basename "$0") [--profile PROFILE] (--domain DOMAIN_NAME | --id ZONE_ID)
                   [--format FORMAT] [--output FILE] [--no-save]

Options:
  --profile PROFILE     (Optional) AWS CLI profile to use
  --domain DOMAIN_NAME  (Optional) DNS name to find hosted zone ID
  --id ZONE_ID          (Optional) Hosted zone ID if known
  --format FORMAT       Output format: bind, csv, json, yaml, powerdns (default: bind)
  --output FILE         Filename to save (auto-chosen if omitted)
  --no-save             Print to stdout instead of saving to file
"
  exit 1
}

profile=""
zone_id=""
zone_name=""
format="bind"
output_file=""
no_save=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) shift; profile="$1" ;;
    --id) shift; zone_id="$1" ;;
    --domain) shift; zone_name="$1" ;;
    --format) shift; format="$1" ;;
    --output) shift; output_file="$1" ;;
    --no-save) no_save=true ;;
    *) usage ;;
  esac
  shift
done

[[ -n "$zone_id" || -n "$zone_name" ]] || usage

aws_args=()
[[ -n "$profile" ]] && aws_args+=(--profile "$profile")

if [[ -z "$zone_id" ]]; then
  zone_id=$(aws "${aws_args[@]}" route53 list-hosted-zones --output json |
    jq -r ".HostedZones[] | select(.Name == \"${zone_name}.\") | .Id" |
    head -n1 | cut -d/ -f3)
  if [[ -z "$zone_id" ]]; then
    echo "❌ Error: No hosted zone found for domain '$zone_name'" >&2
    exit 2
  fi
  echo "+ Found zone ID: $zone_id" >&2
fi

records=$(aws "${aws_args[@]}" route53 list-resource-record-sets --hosted-zone-id "$zone_id" --output json)
[[ $(echo "$records" | jq '.ResourceRecordSets | length') -eq 0 ]] && {
  echo "❌ Error: No records found in zone '$zone_id'" >&2
  exit 3
}

base_name="${zone_name:-$zone_id}"

if [[ -z "$output_file" && $no_save == false ]]; then
  case "$format" in
    bind) output_file="${base_name}.zone" ;;
    json) output_file="${base_name}.json" ;;
    csv) output_file="${base_name}.csv" ;;
    powerdns) output_file="${base_name}.pdns" ;;
    yaml) output_file="${base_name}.yaml" ;;
    *) echo "❌ Unknown format: $format" >&2; usage ;;
  esac
fi

generate_output() {
  case "$format" in
    bind)
      origin=$(echo "$records" | jq -r '.ResourceRecordSets[0].Name')
      [[ "$origin" != *"." ]] && origin="${origin}."
      {
        echo "\$ORIGIN $origin"
        echo "\$TTL 300"
        echo "$records" | jq -r '
          .ResourceRecordSets[] |
          . as $r |
          ($r.Name | rtrimstr(".")) as $name |
          ($r.Type) as $type |
          ($r.TTL // 300) as $ttl |
          if $type == "A" or $type == "AAAA" or $type == "CNAME" then
            [$r.ResourceRecords[].Value] | map("\($name).	\($ttl)	IN	\($type)	\(. | rtrimstr("."))") | .[]
          elif $type == "TXT" then
            [$r.ResourceRecords[].Value] | map("\($name).\t\($ttl)\tIN\tTXT\t\"\(.)\"") | .[]
          elif $type == "MX" then
            [$r.ResourceRecords[].Value] | map("\($name).	\($ttl)	IN	MX	10 \(. | rtrimstr("."))") | .[]
          elif $type == "NS" then
            [$r.ResourceRecords[].Value] | map("\($name).	\($ttl)	IN	NS	\(. | rtrimstr("."))") | .[]
          elif $type == "SRV" then
            [$r.ResourceRecords[].Value] | map("\($name).	\($ttl)	IN	SRV	0 0 0 \(. | rtrimstr("."))") | .[]
          elif $type == "SOA" then
            "\($name).	\($ttl)	IN	SOA	\($r.ResourceRecords[0].Value)"
          else
            "# Unsupported type \($type) for \($name)"
          end
        '
      }
      ;;

    json)
      echo "$records"
      ;;

    csv)
      echo "Name,Type,TTL,Value"
      echo "$records" | jq -r '
        .ResourceRecordSets[] |
        ($.Name | rtrimstr(".")) as $name |
        (.Type) as $type |
        (.TTL // 300) as $ttl |
        .ResourceRecords[]?.Value as $val |
        "\($name),\($type),\($ttl),\($val)"
      '
      ;;

    powerdns)
      echo "$records" | jq -r '
        .ResourceRecordSets[] |
        ($.Name | rtrimstr(".")) as $name |
        (.Type) as $type |
        (.TTL // 300) as $ttl |
        .ResourceRecords[]?.Value as $val |
        "\($name)	IN	\($ttl)	\($type)	\($val)"
      '
      ;;

    yaml)
      echo "$records" | jq '
        .ResourceRecordSets |
        map({
          name: .Name,
          type: .Type,
          ttl: .TTL,
          records: [.ResourceRecords[].Value]
        })
      '
      ;;

    *)
      echo "❌ Unsupported format: $format" >&2
      usage
      ;;
  esac
}

if [[ "$no_save" == true ]]; then
  generate_output
else
  generate_output > "$output_file"
  echo "✅ Exported to: $output_file"
fi
