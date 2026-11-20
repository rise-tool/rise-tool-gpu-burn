# rise-tool-gpu-burn

基于 [gpu-burn](https://github.com/wilicc/gpu-burn) 的 NVIDIA GPU 压力测试工具，使用 Rocky Linux 9 Minimal 和 Docker Compose，构建时通过 Git 下载上游源码。

运行环境：x86_64 Linux、Bash 4+、Docker、Docker Compose v2.24+、兼容的 NVIDIA 驱动和 [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)。

## Configuration

### 1. 主机配置

配置文件位于 `envs/<主机名>.env`。

| 主机名 | GPU 配置 | COMPUTE |
| --- | --- | --- |
| MT-BB-1 | V100 12 GB × 4（以实际设备为准） | 70 |
| MT-BB-2 | V100 16 GB × 4 | 70 |
| MT-MB-1 | RTX 5090 | 120 |
| MT-MB-2 | RTX 3090 Ti | 86 |

默认使用 CUDA 12.8，测试 1 小时、占用 90% 可用显存、开启 Tensor Core、关闭双精度。BB 主机测试全部可见 GPU，MB 主机测试第 0 张 GPU。

### 2. 环境变量

| 变量名称 | 变量含义 |
| --- | --- |
| `CONTAINER_NAME` / `IMAGE_TAG` | 主机专用容器名称 / 镜像标签 |
| `CUDA_VERSION` / `COMPUTE` | CUDA RPM 系列 / GPU 计算能力 |
| `GPU_BURN_DURATION` | 测试时长，单位秒 |
| `GPU_BURN_MEMORY` | 可用显存百分比或固定 MB 数 |
| `GPU_BURN_GPU_INDEX` | GPU 索引，留空测试全部可见 GPU |
| `GPU_BURN_DOUBLES` | 是否开启双精度，true / false |
| `GPU_BURN_TENSOR_CORES` | 是否尝试使用 Tensor Core，true / false |

可通过 `GPU_BURN_REPOSITORY`、`GPU_BURN_REF` 指定上游 Git 仓库和版本，通过 `NVCCFLAGS` 添加编译参数。Shell 中同名环境变量优先于配置文件。

### 3. 命令参数

| 参数名称 | 参数含义 | 是否必须 | 可选值 |
| --- | --- | --- | --- |
| `--hostname` | 选择主机配置，大小写不敏感 | 是 | MT-BB-1、MT-BB-2、MT-MB-1、MT-MB-2 |

## Usage

在对应测试机器的项目根目录执行，以下以 MT-BB-2 为例。需要 Docker 权限时使用 `sudo bash`。

### 1. 构建项目

```bash
bash scripts/build.sh --hostname MT-BB-2
```

### 2. 启动测试

```bash
bash scripts/start.sh --hostname MT-BB-2
docker logs -f rise-service-gpu-burn-mt-bb-2
```

测试结束后自动退出并保留日志。检查所有目标 GPU 的最终 `OK` / `FAULTY` 和错误计数，不能仅靠退出码判断通过。

### 3. 关闭测试

```bash
bash scripts/close.sh --hostname MT-BB-2
```

### 4. 重启测试

```bash
bash scripts/rerun.sh --hostname MT-BB-2
```

### 5. 清理项目

删除所选主机的容器、日志、网络和镜像，需要保留结果时先导出日志。

```bash
bash scripts/clean.sh --hostname MT-BB-2
```

## Development

```bash
# 运行脚本测试，无需 Docker 或 GPU。
bash tests/smoke.sh
```
