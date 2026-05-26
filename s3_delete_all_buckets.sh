#!/bin/bash

read -rp "AWS CLI profile (press Enter for none): " PROFILE
PROFILE_ARGS=()
[[ -n "$PROFILE" ]] && PROFILE_ARGS=(--profile "$PROFILE")

BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text "${PROFILE_ARGS[@]}")

# Colors for output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Helper function to run AWS CLI with retry on throttling
run_aws() {
  local max_retries=5
  local wait_time=60
  local attempt=1
  local cmd=("$@")
  while (( attempt <= max_retries )); do
    err=$("${cmd[@]}" 2>&1 1>/dev/null)
    status=$?
    if [[ $status -eq 0 ]]; then
      return 0
    fi
    if echo "$err" | grep -qiE "throttling|rate exceeded|slow down"; then
      echo -e "${YELLOW}⚠️ Throttling detected, backing off attempt $attempt for $wait_time seconds...${RESET}"
      sleep "$wait_time"
      ((attempt++))
    else
      echo -e "${RED}❌ AWS CLI error:${RESET}"
      echo "$err"
      exit 1
    fi
  done
  echo -e "${RED}❌ Maximum retries exceeded due to throttling.${RESET}"
  exit 1
}

# Delete objects in batches of up to 1000
delete_objects_batch() {
  local bucket=$1
  local objects_json=$2
  local count=$(echo "$objects_json" | jq '.Objects | length')
  if (( count > 0 )); then
    run_aws aws s3api delete-objects --bucket "$bucket" --delete "$objects_json" "${PROFILE_ARGS[@]}"
    echo "$count"
  else
    echo 0
  fi
}

# Process all object versions and delete markers for a bucket page by page
process_bucket() {
  local bucket=$1
  echo "Processing bucket: $bucket"

  local key_marker=""
  local version_id_marker=""
  local deleted_total=0

  while :; do
    # Get one page of versions and markers
    if [[ -z "$key_marker" ]]; then
      resp=$(aws s3api list-object-versions --bucket "$bucket" "${PROFILE_ARGS[@]}" --output json)
    else
      resp=$(aws s3api list-object-versions --bucket "$bucket" "${PROFILE_ARGS[@]}" --output json --key-marker "$key_marker" --version-id-marker "$version_id_marker")
    fi

    # Extract versions and delete markers into delete request JSON formats
    versions_json=$(echo "$resp" | jq '{Objects: [.Versions[]? | {Key: .Key, VersionId: .VersionId}]}')
    markers_json=$(echo "$resp" | jq '{Objects: [.DeleteMarkers[]? | {Key: .Key, VersionId: .VersionId}]}')

    # Delete versions batch
    deleted_versions=$(delete_objects_batch "$bucket" "$versions_json")
    # Delete delete markers batch
    deleted_markers=$(delete_objects_batch "$bucket" "$markers_json")
    deleted_batch=$((deleted_versions + deleted_markers))
    deleted_total=$((deleted_total + deleted_batch))

    echo "Deleted $deleted_batch objects in this batch, total deleted: $deleted_total"

    # Pagination tokens for next iteration
    key_marker=$(echo "$resp" | jq -r '.NextKeyMarker // empty')
    version_id_marker=$(echo "$resp" | jq -r '.NextVersionIdMarker // empty')

    # Break if no more pages
    if [[ -z "$key_marker" ]]; then
      break
    fi
  done

  # After all objects deleted, delete the bucket
  echo "Deleting bucket: $bucket"
  run_aws aws s3 rb s3://"$bucket" --force "${PROFILE_ARGS[@]}"
  echo -e "${GREEN}Bucket $bucket deleted.${RESET}"
}

# Main script execution
for bucket in $BUCKETS; do
  process_bucket "$bucket"
done

echo -e "${GREEN}All specified buckets processed.${RESET}"

