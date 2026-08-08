# linux-scripts

A collection of standalone Linux and AWS administration scripts.

---

## Developer tools

### `claude-resume-wrapper.sh` — Claude Code usage-limit retry wrapper

Starts a fresh, explicitly identified Claude Code session by default. If Claude
reports a usage limit and exits, the wrapper retries that exact session rather
than whichever session happens to be newest. Interactive Claude options pass
through on the initial launch, and `--continue` or `--resume` can be used when
you intentionally want an existing session. The wrapper preserves Claude's
interactive terminal UI and stops on unrelated errors. By default it retries
every 15 minutes, up to 24 times. If Claude remains open at its prompt after
showing the limit, exit Claude normally to start the wait-and-retry cycle.

**Dependencies:** Claude Code, Bash, and the standard `script` utility

```bash
chmod +x claude-resume-wrapper.sh
sudo install -m 0755 claude-resume-wrapper.sh /usr/local/bin/claude-smart

# Start a fresh session.
claude-smart

# Start fresh with normal Claude options.
claude-smart --name billing-fix --model opus
claude-smart --worktree billing-fix --model sonnet

# Deliberately continue or resume an existing session.
claude-smart --continue
claude-smart --resume SESSION_ID

# Optional: retry every 30 minutes with no retry limit.
CLAUDE_SMART_RETRY_SECONDS=1800 CLAUDE_SMART_MAX_RETRIES=0 claude-smart
```

Non-interactive (`--print`), background, cloud, remote-control, non-persistent,
and forked sessions are rejected because their lifecycle conflicts with this
interactive auto-resume wrapper.

---

## Scripts

### AWS

#### `route53-export.sh` — Route 53 DNS export (recommended)

Exports all DNS records from an AWS Route 53 hosted zone. Supports multiple output formats and accepts an AWS CLI profile, making it suitable for multi-account environments. This is the preferred script for Route 53 exports.

**Dependencies:** `aws` CLI, `jq`

**Formats:** `bind` (default), `csv`, `json`, `powerdns`, `yaml`

By default the output is saved to a file named after the domain (e.g. `example.com.zone`, `example.com.csv`). Use `--no-save` to print to stdout instead.

```bash
# Export as BIND zone file (default), saving to example.com.zone
./route53-export.sh --profile myprofile --domain example.com

# Export as CSV, printing to stdout
./route53-export.sh --profile myprofile --domain example.com --format csv --no-save

# Export using a known zone ID
./route53-export.sh --profile myprofile --id Z1234567890ABC --format json

# Save to a specific file
./route53-export.sh --profile myprofile --domain example.com --output /tmp/example.zone
```

---

#### `route53-export-bind.sh` — Route 53 export, BIND/tab-separated (legacy)

An earlier, simpler version of the Route 53 exporter. Outputs records in a raw tab-separated format using `jq`. The AWS profile is hardcoded to `ndc`; use `route53-export.sh` instead if you need a different profile or a specific output format.

**Dependencies:** `aws` CLI, `jq`

```bash
./route53-export-bind.sh --domain example.com
./route53-export-bind.sh --id Z1234567890ABC
```

---

#### `route53-export-2.sh` — Route 53 export, positional argument (legacy)

An even earlier version. Takes the domain name as a positional argument and hardcodes `--profile ndc`. Output is tab-separated and includes some sed-based post-processing (strips the apex label, normalises TTLs, unescapes `\052` → `*`). Prefer `route53-export.sh` for new use.

**Dependencies:** `aws` CLI, `jq`

```bash
./route53-export-2.sh example.com
```

---

#### `s3_delete_all_buckets.sh` — Delete all S3 buckets under a profile

Lists every bucket in an account and deletes them, including all object versions and delete markers (required for versioning-enabled buckets). Deletes objects in batches of up to 1000 and retries automatically on API throttling.

**Warning:** This is destructive and irreversible. Edit the `PROFILE` variable at the top of the script before running.

**Dependencies:** `aws` CLI, `jq`

```bash
# Edit PROFILE="your-profile" in the script first, then:
./s3_delete_all_buckets.sh
```

---

### Linux maintenance

#### `check-reboot-reqd.sh`

Checks whether a Linux system needs to be rebooted by detecting two conditions:

1. Libraries that have been deleted on disk but are still mapped into running processes (indicates a package upgrade that requires a restart).
2. A mismatch between the running kernel (`uname -r`) and the kernel that would boot next (`/boot/vmlinuz`).

Exit code `0` means a reboot is required; `1` means none is needed (unusual convention — designed for use in monitoring scripts).

```bash
./check-reboot-reqd.sh
echo $?   # 0 = reboot required, 1 = no reboot needed
```

---

#### `clean-centos-disk-space.sh`

Frees disk space on CentOS systems by removing:

- Log files over 50 MB or older than 30 days (truncated, not deleted)
- yum caches and temporary files
- WP-CLI, Composer, npm, and node-gyp caches
- mock build caches
- User home directory caches
- Core dump files
- cPanel `error_log` files

Can be run directly from GitHub via curl:

```bash
curl -Ls https://raw.githubusercontent.com/jgiambona/linux-scripts/master/clean-centos-disk-space.sh | sudo bash
```

---

#### `clean-fedora-old-kernels.sh`

Removes all but the latest installed kernel on Fedora using `dnf`. Safe to run after a kernel upgrade to reclaim `/boot` space.

**Dependencies:** `dnf`

```bash
sudo ./clean-fedora-old-kernels.sh
```

---

### MySQL Workbench

#### `wb_admin_export.py` — Patched MySQL Workbench export module

A modified version of MySQL Workbench's internal `wb_admin_export.py` module that restores compatibility with older MySQL server versions. This is not a standalone script — it is a drop-in replacement for the file installed by MySQL Workbench.

To apply, replace the file at:

```
/usr/lib64/mysql-workbench/modules/wb_admin_export.py
```
