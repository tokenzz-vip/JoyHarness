#!/usr/bin/env bash
set -euo pipefail

image="${1:?DMG path required}"

# A recently created or modified image can still be temporarily locked.
attempt=1
until hdiutil verify "$image" >/dev/null; do
  if (( attempt == 4 )); then
    echo 'Disk image verification failed after 4 attempts.' >&2
    exit 1
  fi
  printf 'Disk image verification failed. Retrying in %s second(s).\n' "$attempt" >&2
  sleep "$attempt"
  attempt=$((attempt + 1))
done
