#!/usr/bin/env bash
set -euo pipefail

private_throw_error() {
  printf '错误：%s\n' "$1" >&2
  exit 1
}

private_check_positive_integer() {
  # Limit values to the signed 32-bit range consumed by upstream atoi().
  [[ "$2" =~ ^[1-9][0-9]{0,9}$ ]] && ((10#$2 <= 2147483647)) \
    || private_throw_error "$1 必须是 1 到 2147483647 之间的整数！"
}

private_check_boolean() {
  case "$2" in
    true|false) ;;
    *) private_throw_error "$1 仅支持 true 或 false！" ;;
  esac
}

private_start_app() {
  # Explicit arguments use the native gpu-burn CLI, e.g. -l, -h or -m 50% 3600.
  if (($#)); then
    exec ./gpu_burn "$@"
  fi

  local duration="${GPU_BURN_DURATION:-60}"
  local memory="${GPU_BURN_MEMORY:-90%}"
  local gpu_index="${GPU_BURN_GPU_INDEX:-}"
  local doubles="${GPU_BURN_DOUBLES:-false}"
  local tensor_cores="${GPU_BURN_TENSOR_CORES:-false}"
  local -a args=(-m "$memory")

  private_check_positive_integer GPU_BURN_DURATION "$duration"
  if [[ "$memory" == *% ]]; then
    local percentage="${memory%\%}"
    [[ "$percentage" =~ ^[1-9][0-9]?$|^100$ ]] \
      || private_throw_error 'GPU_BURN_MEMORY 百分比必须在 1% 到 100% 之间！'
  else
    private_check_positive_integer GPU_BURN_MEMORY "$memory"
  fi
  if [[ -n "$gpu_index" ]]; then
    [[ "$gpu_index" =~ ^(0|[1-9][0-9]{0,9})$ ]] && ((10#$gpu_index <= 2147483647)) \
      || private_throw_error 'GPU_BURN_GPU_INDEX 必须是 0 到 2147483647 之间的整数！'
    args+=(-i "$gpu_index")
  fi
  private_check_boolean GPU_BURN_DOUBLES "$doubles"
  private_check_boolean GPU_BURN_TENSOR_CORES "$tensor_cores"
  if [[ "$doubles" == true ]]; then
    args+=(-d)
  fi
  if [[ "$tensor_cores" == true ]]; then
    args+=(-tc)
  fi
  exec ./gpu_burn "${args[@]}" "$duration"
}

private_start_app "$@"
