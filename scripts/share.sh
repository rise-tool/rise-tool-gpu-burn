#!/usr/bin/env bash

PROJECT_ROOT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENVVARS_ROOT_PATH="${PROJECT_ROOT_PATH}/envs"
COMPOSE_YAML_PATH="${PROJECT_ROOT_PATH}/compose.yaml"
INSTANCE_NAME="rise-service-gpu-burn"
ENV_FILE_PATH=""
# Do not implicitly read a caller's .env file; builds and cleanup use known defaults.
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
  local label=""
  while (($#)); do
    case "$1" in
      --label)
        [[ -z "$label" ]] || private_throw_error '参数 --label 不能重复！'
        [[ -n "${2:-}" ]] || private_throw_error '参数 --label 不能为空！'
        label="${2,,}"
        [[ "$label" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
          || private_throw_error '实例标签只支持字母、数字、下划线和连字符，且必须以字母或数字开头！'
        shift 2
        ;;
      *) private_throw_error "参数 $1 不支持！" ;;
    esac
  done
  [[ -n "$label" ]] || private_throw_error '请通过 --label 指定实例标签！'
  INSTANCE_NAME="rise-service-gpu-burn-${label}"
  ENV_FILE_PATH="${ENVVARS_ROOT_PATH}/${INSTANCE_NAME}.env"
  [[ -f "$ENV_FILE_PATH" ]] || private_throw_error "文件 $ENV_FILE_PATH 不存在！"
}

public_compose_build() {
  (($# == 0)) || private_throw_error '构建脚本不接受命令参数，请使用环境变量配置构建！'
  private_check_docker
  "${COMPOSE_SHARE[@]}" -p rise-tool-gpu-burn build
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

private_compose_clean_instances() {
  local env_file_path instance_name
  for env_file_path in "$ENVVARS_ROOT_PATH"/rise-service-gpu-burn-*.env; do
    [[ -f "$env_file_path" ]] || continue
    instance_name="$(basename "$env_file_path" .env)"
    "${COMPOSE_SHARE[@]}" -p "$instance_name" --env-file "$env_file_path" down --remove-orphans
  done
}

private_compose_clean_images() {
  local image_list image_name image_info
  image_list="$("${COMPOSE_SHARE[@]}" -p rise-tool-gpu-burn config --images | sort -u)" \
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
  (($# == 0)) || private_throw_error '清理脚本不接受命令参数！'
  private_check_docker
  private_compose_clean_instances
  private_compose_clean_images
}
