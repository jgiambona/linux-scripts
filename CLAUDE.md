# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of standalone Linux and AWS administration scripts. There is no build system, test suite, or package manager — each script is independently executable and self-contained.

## Dependencies

- AWS scripts require: `aws` CLI and `jq`
- Linux maintenance scripts require: `yum`/`dnf` (distro-specific)
- `wb_admin_export.py` is a patched MySQL Workbench internal module, not a standalone script

## Script inventory

| Script | Purpose | Distro/Context |
|---|---|---|
| `check-reboot-reqd.sh` | Detects if a reboot is needed (deleted libs still loaded, kernel mismatch). Exit 0 = reboot required, 1 = no reboot needed. | Any Linux |
| `clean-centos-disk-space.sh` | Clears yum caches, logs, WP-CLI/Composer/npm caches, core dumps, cPanel logs | CentOS |
| `clean-fedora-old-kernels.sh` | Removes old kernels via `dnf repoquery --installonly` | Fedora |
| `route53-export.sh` | **Canonical Route 53 export script.** Exports DNS records in BIND, CSV, JSON, PowerDNS, or YAML format. Supports `--profile`, `--domain`/`--id`, `--format`, `--output`, `--no-save`. | AWS |
| `route53-export-2.sh` | Older, simpler Route 53 export — hardcodes `--profile ndc`, positional domain arg, BIND-like tab-separated output | AWS (legacy) |
| `route53-export-bind.sh` | Another older Route 53 export — hardcodes `--profile ndc`, supports `--id`/`--domain`, raw jq output | AWS (legacy) |
| `s3_delete_all_buckets.sh` | Deletes all S3 buckets under a profile, including versioned objects and delete markers. Retries on throttling. | AWS |
| `wb_admin_export.py` | Patched MySQL Workbench export module for older MySQL compatibility. Drop-in replacement for `/usr/lib64/mysql-workbench/modules/wb_admin_export.py`. | MySQL Workbench |

## Hardcoded values to be aware of

- `s3_delete_all_buckets.sh`: `PROFILE="jazzypay"` — change this before running against a different account.
- `route53-export-2.sh` and `route53-export-bind.sh`: hardcode `--profile ndc` — use `route53-export.sh` with `--profile` instead for flexible usage.

## Running scripts

Scripts are run directly. Make executable first if needed:

```bash
chmod +x script.sh
./script.sh [args]
```

For Route 53 export (preferred script):

```bash
./route53-export.sh --profile myprofile --domain example.com --format bind
./route53-export.sh --profile myprofile --id Z1234567890 --format csv --no-save
```
