#!/usr/bin/env bash
# Exercise the actual entrypoint and lifecycle scripts without Docker or a GPU.
set -euo pipefail

PROJECT_ROOT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT_PATH="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT_PATH"' EXIT
mkdir -p "$TEST_ROOT_PATH/bin" "$TEST_ROOT_PATH/app"
export TEST_TRACE_PATH="$TEST_ROOT_PATH/trace"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_trace() {
  local expected="$1" actual
  actual="$(cat "$TEST_TRACE_PATH")"
  [[ "$actual" == "$expected" ]] || fail "expected [$expected], got [$actual]"
}

expect_failure() {
  : > "$TEST_TRACE_PATH"
  if "$@" > "$TEST_ROOT_PATH/output" 2>&1; then
    fail "command should have failed: $*"
  fi
  [[ ! -s "$TEST_TRACE_PATH" ]] || fail 'invalid input executed an external command'
  [[ -s "$TEST_ROOT_PATH/output" ]] || fail 'missing error message'
}

cat > "$TEST_ROOT_PATH/app/gpu_burn" <<'STUB'
#!/usr/bin/env bash
printf '<%s>' "$@" > "$TEST_TRACE_PATH"
exit "${TEST_GPU_EXIT_CODE:-0}"
STUB
cat > "$TEST_ROOT_PATH/bin/docker" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == 'compose version' ]]; then
  exit 0
fi
printf '<%s>' "$@" >> "$TEST_TRACE_PATH"
printf '\n' >> "$TEST_TRACE_PATH"
case "$*" in
  *'config --images') printf 'rise-tool-gpu-burn:v1.0.0\n' ;;
  'image ls '*) printf 'fake-image-id\n' ;;
esac
exit "${TEST_DOCKER_EXIT_CODE:-0}"
STUB
chmod +x "$TEST_ROOT_PATH/app/gpu_burn" "$TEST_ROOT_PATH/bin/docker"
export PATH="$TEST_ROOT_PATH/bin:$PATH"
unset GPU_BURN_DURATION GPU_BURN_MEMORY GPU_BURN_GPU_INDEX GPU_BURN_DOUBLES GPU_BURN_TENSOR_CORES

cd "$TEST_ROOT_PATH/app"
bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
assert_trace '<-m><90%><60>'
GPU_BURN_DURATION=3600 GPU_BURN_MEMORY=4096 GPU_BURN_GPU_INDEX=1 \
  GPU_BURN_DOUBLES=true GPU_BURN_TENSOR_CORES=true bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
assert_trace '<-m><4096><-i><1><-d><-tc><3600>'
GPU_BURN_MEMORY=100% GPU_BURN_GPU_INDEX=0 bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
assert_trace '<-m><100%><-i><0><60>'
GPU_BURN_DURATION=invalid bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh" -l
assert_trace '<-l>'
bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh" -m 50% -tc 30
assert_trace '<-m><50%><-tc><30>'
if TEST_GPU_EXIT_CODE=23 bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh" -h; then
  fail 'entrypoint lost the upstream exit code'
else
  [[ "$?" == 23 ]] || fail 'unexpected upstream exit code'
fi

for value in 0 -1 1.5 01 abc 2147483648 999999999999999999999; do
  expect_failure env GPU_BURN_DURATION="$value" bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
done
for value in 0% 101% -1% 01% 50.5% 0 -3 abc '50% -d'; do
  expect_failure env GPU_BURN_MEMORY="$value" bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
done
for value in -1 abc 01 2147483648; do
  expect_failure env GPU_BURN_GPU_INDEX="$value" bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
done
for name in GPU_BURN_DOUBLES GPU_BURN_TENSOR_CORES; do
  expect_failure env "$name=yes" bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
done
printf 'PASS: entrypoint defaults, flags, validation and exit code\n'

# Run from outside the repository to verify that all paths resolve from the scripts.
compose_prefix="<compose><--project-directory><$PROJECT_ROOT_PATH><-f><$PROJECT_ROOT_PATH/compose.yaml><--env-file></dev/null>"
instance_prefix="$compose_prefix<-p><rise-service-gpu-burn-1><--env-file><$PROJECT_ROOT_PATH/envs/rise-service-gpu-burn-1.env>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/build.sh"
assert_trace "$compose_prefix<-p><rise-tool-gpu-burn><build>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/start.sh" --label 1
assert_trace "$instance_prefix<up><-d><--no-build>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/close.sh" --label 1
assert_trace "$instance_prefix<stop>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/rerun.sh" --label 1
assert_trace "$instance_prefix<stop>"$'\n'"$instance_prefix<up><-d><--no-build>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/start.sh" --label 2
assert_trace "$compose_prefix<-p><rise-service-gpu-burn-2><--env-file><$PROJECT_ROOT_PATH/envs/rise-service-gpu-burn-2.env><up><-d><--no-build>"

for action in start close rerun; do
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh"
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --label
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --label ../1
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --label '1;echo bad'
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --label 1 --label 2
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --label missing
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --unknown 1
done
expect_failure bash "$PROJECT_ROOT_PATH/scripts/build.sh" --label 1
expect_failure bash "$PROJECT_ROOT_PATH/scripts/clean.sh" --label 1

: > "$TEST_TRACE_PATH"
if TEST_DOCKER_EXIT_CODE=17 bash "$PROJECT_ROOT_PATH/scripts/start.sh" --label 1; then
  fail 'start lost the Docker exit code'
else
  [[ "$?" == 17 ]] || fail 'unexpected Docker exit code'
fi
: > "$TEST_TRACE_PATH"
if TEST_DOCKER_EXIT_CODE=17 bash "$PROJECT_ROOT_PATH/scripts/rerun.sh" --label 1; then
  fail 'rerun ignored a failed stop'
else
  [[ "$?" == 17 ]] || fail 'unexpected Docker exit code'
fi
assert_trace "$instance_prefix<stop>"
printf 'PASS: instance selection, lifecycle commands and error propagation\n'

: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/clean.sh"
trace="$(cat "$TEST_TRACE_PATH")"
[[ "$trace" == *"$instance_prefix<down><--remove-orphans>"* ]] || fail 'cleanup missed instance 1'
[[ "$trace" == *'<rise-service-gpu-burn-2>'*'<down><--remove-orphans>'* ]] || fail 'cleanup missed instance 2'
[[ "$trace" == *'<config><--images>'* ]] || fail 'cleanup did not resolve project images'
[[ "$trace" == *'<image><ls><--quiet><--filter><reference=rise-tool-gpu-burn:v1.0.0>'* ]] || fail 'cleanup image query is not scoped'
[[ "$trace" == *'<image><rm><rise-tool-gpu-burn:v1.0.0>' ]] || fail 'cleanup missed the project image'
[[ "$trace" != *'<prune>'* ]] || fail 'cleanup must not prune unrelated Docker resources'
printf 'PASS: cleanup removes only configured instances and the project image\n'
