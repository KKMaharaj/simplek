#!/usr/bin/env bash
# Reads backup file names (one per line, sorted oldest first, as their dates
# sort) and prints those that are not among the newest $1. Used to prune
# the nightly backups; tested in test/backup_scripts_test.dart.
set -euo pipefail
keep=${1:?how many to keep}
mapfile -t names
count=${#names[@]}
for ((i = 0; i < count - keep; i++)); do
  echo "${names[$i]}"
done
