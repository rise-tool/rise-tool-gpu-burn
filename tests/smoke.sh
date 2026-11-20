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
  *'config --images') printf 'rise-tool-gpu-burn:mt-bb-1-v1.0.0\n' ;;
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
instance_prefix="$compose_prefix<-p><rise-service-gpu-burn-mt-bb-1><--env-file><$PROJECT_ROOT_PATH/envs/MT-BB-1.env>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/build.sh" --hostname MT-BB-1
assert_trace "$instance_prefix<build>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/start.sh" --hostname MT-BB-1
assert_trace "$instance_prefix<up><-d><--no-build>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/close.sh" --hostname MT-BB-1
assert_trace "$instance_prefix<stop>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/rerun.sh" --hostname MT-BB-1
assert_trace "$instance_prefix<stop>"$'\n'"$instance_prefix<up><-d><--no-build>"
: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/start.sh" --hostname MT-BB-2
assert_trace "$compose_prefix<-p><rise-service-gpu-burn-mt-bb-2><--env-file><$PROJECT_ROOT_PATH/envs/MT-BB-2.env><up><-d><--no-build>"

for action in build start close rerun clean; do
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh"
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --hostname
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --hostname ../1
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --hostname '1;echo bad'
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --hostname MT-BB-1 --hostname MT-BB-2
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --hostname missing
  expect_failure bash "$PROJECT_ROOT_PATH/scripts/$action.sh" --unknown 1
done
expect_failure bash "$PROJECT_ROOT_PATH/scripts/start.sh" --label 1

: > "$TEST_TRACE_PATH"
if TEST_DOCKER_EXIT_CODE=17 bash "$PROJECT_ROOT_PATH/scripts/start.sh" --hostname MT-BB-1; then
  fail 'start lost the Docker exit code'
else
  [[ "$?" == 17 ]] || fail 'unexpected Docker exit code'
fi
: > "$TEST_TRACE_PATH"
if TEST_DOCKER_EXIT_CODE=17 bash "$PROJECT_ROOT_PATH/scripts/rerun.sh" --hostname MT-BB-1; then
  fail 'rerun ignored a failed stop'
else
  [[ "$?" == 17 ]] || fail 'unexpected Docker exit code'
fi
assert_trace "$instance_prefix<stop>"
printf 'PASS: instance selection, lifecycle commands and error propagation\n'

: > "$TEST_TRACE_PATH"
bash "$PROJECT_ROOT_PATH/scripts/clean.sh" --hostname MT-BB-1
trace="$(cat "$TEST_TRACE_PATH")"
[[ "$trace" == *"$instance_prefix<down><--remove-orphans>"* ]] || fail 'cleanup missed instance 1'
[[ "$trace" != *'<rise-service-gpu-burn-mt-bb-2>'* ]] || fail 'cleanup touched another host'
[[ "$trace" == *'<config><--images>'* ]] || fail 'cleanup did not resolve project images'
[[ "$trace" == *'<image><ls><--quiet><--filter><reference=rise-tool-gpu-burn:mt-bb-1-v1.0.0>'* ]] || fail 'cleanup image query is not scoped'
[[ "$trace" == *'<image><rm><rise-tool-gpu-burn:mt-bb-1-v1.0.0>' ]] || fail 'cleanup missed the project image'
[[ "$trace" != *'<prune>'* ]] || fail 'cleanup must not prune unrelated Docker resources'
printf 'PASS: cleanup removes only the selected host and its image\n'

for host_name in MT-BB-1 MT-BB-2 MT-MB-1 MT-MB-2; do
  (
    set -a
    source "$PROJECT_ROOT_PATH/envs/$host_name.env"
    set +a
    case "$host_name" in
      MT-BB-1|MT-BB-2) expected_compute=70; expected_args='<-m><90%><-tc><3600>' ;;
      MT-MB-1) expected_compute=120; expected_args='<-m><90%><-i><0><-tc><3600>' ;;
      MT-MB-2) expected_compute=86; expected_args='<-m><90%><-i><0><-tc><3600>' ;;
    esac
    [[ "$COMPUTE" == "$expected_compute" ]] || fail "wrong compute capability for $host_name"
    [[ "$CUDA_VERSION" == 12.8 ]] || fail "wrong CUDA series for $host_name"
    [[ "$IMAGE_TAG" == "${host_name,,}-v1.0.0" ]] || fail "wrong image tag for $host_name"
    [[ "$CONTAINER_NAME" == "rise-service-gpu-burn-${host_name,,}" ]] || fail "wrong container name for $host_name"
    bash "$PROJECT_ROOT_PATH/bin/gpu-burn.sh"
    assert_trace "$expected_args"
  )
  : > "$TEST_TRACE_PATH"
  bash "$PROJECT_ROOT_PATH/scripts/build.sh" --hostname "${host_name,,}"
  assert_trace "$compose_prefix<-p><rise-service-gpu-burn-${host_name,,}><--env-file><$PROJECT_ROOT_PATH/envs/$host_name.env><build>"
done
printf 'PASS: all four hardware profiles and case-insensitive hostname selection\n'
