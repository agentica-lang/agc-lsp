set -e
agentica specs/smoke.agc input /tmp/in
program=$(agentica --allow-run bin/prepare.agc Z:/repo Z:/agentica/agentica.exe | tr -d '\r')
agentica run --allow-run -- "$program" --stdio < /tmp/in > /tmp/out
agentica specs/smoke.agc verify /tmp/out
