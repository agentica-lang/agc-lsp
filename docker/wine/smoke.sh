set -e
agentica specs/smoke.agc input /tmp/in
prepared=$(agentica bin/prepare.agc Z:/repo Z:/agentica/agentica.exe)
program=$(printf '%s' "$prepared" | tr -d '\r')
if [ -z "$program" ]; then
  echo "wine-smoke: prepare.agc printed no program" >&2
  exit 1
fi
agentica run -- "$program" --stdio < /tmp/in > /tmp/out
agentica specs/smoke.agc verify /tmp/out
