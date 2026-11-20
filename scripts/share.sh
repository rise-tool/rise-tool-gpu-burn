#!/usr/bin/env bash

PROJECT_ROOT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENVVARS_ROOT_PATH="${PROJECT_ROOT_PATH}/envs"
COMPOSE_YAML_PATH="${PROJECT_ROOT_PATH}/compose.yaml"
INSTANCE_NAME="rise-service-gpu-burn"
ENV_FILE_PATH=""
# Do not implicitly read a caller's .env file.
COMPOSE_SHARE=(docker compose --project-directory "$PROJECT_ROOT_PATH" -f "$COMPOSE_YAML_PATH" --env-file /dev/null)

private_throw_error() {
  printf '错误：%s\n' "$1" >&2
  exit 1
}

private_check_docker() {
  command -v docker >/dev/null 2>&1 || private_throw_error '请先安装 Docker 和 Docker Compose v2！'
  docker compose version >/dev/null 2>&1 || private_throw_error 'Docker Compose v2 不可用！'
}

private_parse_command_args() {
  local host_name=""
  while (($#)); do
    case "$1" in
      --hostname)
        [[ -z "$host_name" ]] || private_throw_error '参数 --hostname 不能重复！'
        [[ -n "${2:-}" ]] || private_throw_error '参数 --hostname 不能为空！'
        host_name="${2^^}"
        [[ ${#host_name} -le 63 && "$host_name" =~ ^[A-Z0-9]([A-Z0-9-]*[A-Z0-9])?$ ]] \
          || private_throw_error '主机名最多 63 个字符，仅支持字母、数字和连字符，首尾须为字母或数字！'
        shift 2
        ;;
      *) private_throw_error "参数 $1 不支持！" ;;
    esac
  done
  [[ -n "$host_name" ]] || private_throw_error '请通过 --hostname 指定主机名！'
  INSTANCE_NAME="rise-service-gpu-burn-${host_name,,}"
  ENV_FILE_PATH="${ENVVARS_ROOT_PATH}/${host_name}.env"
  [[ -f "$ENV_FILE_PATH" ]] || private_throw_error "文件 $ENV_FILE_PATH 不存在！"
}

public_compose_build() {
  private_parse_command_args "$@"
  private_check_docker
  "${COMPOSE_SHARE[@]}" -p "$INSTANCE_NAME" --env-file "$ENV_FILE_PATH" build
}

private_compose_start() {
  "${COMPOSE_SHARE[@]}" -p "$INSTANCE_NAME" --env-file "$ENV_FILE_PATH" up -d --no-build
}

private_compose_close() {
  "${COMPOSE_SHARE[@]}" -p "$INSTANCE_NAME" --env-file "$ENV_FILE_PATH" stop
}

public_compose_start() {
  private_parse_command_args "$@"
  private_check_docker
  private_compose_start
}

public_compose_close() {
  private_parse_command_args "$@"
  private_check_docker
  private_compose_close
}

public_compose_rerun() {
  private_parse_command_args "$@"
  private_check_docker
  private_compose_close
  private_compose_start
}

private_compose_clean_images() {
  local image_list image_name image_info
  image_list="$("${COMPOSE_SHARE[@]}" -p "$INSTANCE_NAME" --env-file "$ENV_FILE_PATH" config --images | sort -u)" \
    || private_throw_error '获取 Docker 镜像列表失败！'
  while IFS= read -r image_name; do
    [[ -n "$image_name" ]] || continue
    image_info="$(docker image ls --quiet --filter "reference=$image_name")" \
      || private_throw_error "查询 Docker 镜像 $image_name 失败！"
    [[ -n "$image_info" ]] || continue
    docker image rm "$image_name"
  done <<< "$image_list"
}

public_compose_clean() {
  private_parse_command_args "$@"
  private_check_docker
  "${COMPOSE_SHARE[@]}" -p "$INSTANCE_NAME" --env-file "$ENV_FILE_PATH" down --remove-orphans
  private_compose_clean_images
}
