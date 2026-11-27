#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."

pass=0
total=0
failed=0
skipped=0
reasons=""

shopt -s nullglob
specs=(tests/*_spec.lua)
if [[ ${#specs[@]} -eq 0 ]]; then
  echo "PASS 0/0 (0 skipped)"
  exit 1
fi

for spec in "${specs[@]}"; do
  echo "==> ${spec}"
  rc=0
  output=$(nvim --headless -l "$spec" 2>&1) || rc=$?
  printf '%s\n' "$output"
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    skipped=$((skipped + 1))
    reasons+="${line}"$'\n'
  done < <(printf '%s\n' "$output" | grep '^SKIP ' || true)
  result=$(printf '%s\n' "$output" | grep '^RESULT ' | tail -n 1 || true)
  if [[ -z "${result}" ]]; then
    failed=1
  else
    p=$(awk '{print $2}' <<<"${result}")
    f=$(awk '{print $3}' <<<"${result}")
    pass=$((pass + p))
    total=$((total + p + f))
    if [[ "${f}" != "0" ]]; then
      failed=1
    fi
  fi
  if [[ "${rc}" -ne 0 ]]; then
    failed=1
  fi
done

if [[ "${skipped}" -gt 0 ]]; then
  printf '%s' "${reasons}"
fi
echo "PASS ${pass}/${total} (${skipped} skipped)"
if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi
exit 0
