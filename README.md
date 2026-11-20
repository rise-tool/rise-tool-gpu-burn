# rise-tool-gpu-burn

基于 [gpu-burn](https://github.com/wilicc/gpu-burn) 的 NVIDIA GPU 压力测试工具，按照
[rise-tool-template-docker](https://github.com/rise-tool/rise-tool-template-docker)
的目录结构和脚本约定，使用 Docker Compose 构建镜像、按标签管理多个测试实例。

## 运行要求

- x86_64 Linux、Bash 4+、Docker Engine 和 Docker Compose v2.24+（支持 GPU device reservations）。
- NVIDIA GPU、与所选 CUDA 版本兼容的主机驱动，以及已配置 Docker runtime 的
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)。
- 主机无需安装 CUDA Toolkit，编译工具和 CUDA 库由容器镜像提供。

基础镜像使用 `rockylinux:9-minimal`，通过 NVIDIA 官方 RHEL 9 RPM 仓库安装 CUDA 12.8，
默认计算能力为 7.5。请根据显卡和驱动选择
`CUDA_VERSION` 与 `COMPUTE`；较老显卡可能需要较早的 CUDA 版本。
开始前可使用 `nvidia-smi` 检查驱动，并验证容器能够访问 GPU：

```bash
docker run --rm --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  rockylinux:9-minimal nvidia-smi
```

压力测试会持续占用 GPU 算力和显存。运行前确认散热、电源与当前 GPU 工作负载，
避免同时在同一张 GPU 上启动多个测试实例。

## Configuration

### 1. 构建环境变量

通过环境变量传给 `scripts/build.sh`，多个实例共用同一镜像。

| 变量名称 | 含义 | 默认值 |
| --- | --- | --- |
| `CUDA_VERSION` | CUDA RPM 系列，格式为主版本.次版本，需在 NVIDIA RHEL 9 x86_64 仓库中存在 | `12.8` |
| `COMPUTE` | CUDA 计算能力，例如 `75`、`86`、`89`、`90` | `75` |
| `NVCCFLAGS` | 附加 nvcc 编译参数 | 空 |
| `GPU_BURN_REPOSITORY` | 构建时拉取的 Git 仓库，可设为兼容的镜像仓库地址 | `https://github.com/wilicc/gpu-burn.git` |
| `GPU_BURN_REF` | Git 提交、标签或分支；建议固定完整提交 SHA | `0d19c94dcb2e9b6858b7586a4c327674cd67113b` |

`CUDA_VERSION` 使用 RPM 系列编号，例如 `12.8`，不再接受原 CUDA 镜像的 `12.8.1`
格式。构建会安装该系列当前可用的 RPM 包，并非锁定补丁版本；`IMAGE_DISTRO` 已移除。

`COMPUTE` 可以显式设为空，再使用 `NVCCFLAGS` 的 `-gencode` 参数构建多个架构；
请确保所选 CUDA 版本支持目标架构。例如：

```bash
COMPUTE= NVCCFLAGS='-gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_90,code=sm_90' \
  bash scripts/build.sh
```

### 2. 实例环境变量

每个实例对应 `envs/rise-service-gpu-burn-<label>.env`，提供了 `1` 和 `2` 两个示例。

| 变量名称 | 含义 | 默认值 / 可选值 |
| --- | --- | --- |
| `CONTAINER_NAME` | 唯一容器名称 | 直接运行 Compose 时为 `rise-service-gpu-burn-default`，实例文件中须设置唯一名称 |
| `GPU_BURN_DURATION` | 测试时长，单位秒 | `60`，正整数 |
| `GPU_BURN_MEMORY` | 使用可用显存的百分比，或固定显存 MB 数 | `90%`；支持 `1%`～`100%` 或正整数，例如 `4096` |
| `GPU_BURN_GPU_INDEX` | 容器内 CUDA GPU 索引，对应上游 `-i` 参数 | 空表示测试所有可见 GPU；示例 1 为 `0`，示例 2 为 `1` |
| `GPU_BURN_DOUBLES` | 启用双精度，对应 `-d` | `false` / `true` |
| `GPU_BURN_TENSOR_CORES` | 尝试使用 Tensor Core，对应 `-tc` | `false` / `true` |

`GPU_BURN_DURATION`、固定显存 MB 数和 GPU 索引最大支持 `2147483647`；数字不接受前导零。
实例 2 需要主机至少有两张可用 GPU。单卡主机可只运行实例 1。
默认 Compose 向容器开放所有 GPU，再由 `GPU_BURN_GPU_INDEX` 选择实际测试的显卡；
它不是设备隔离设置。需要限定容器能访问的 GPU 时，可在 Compose override 中用
`device_ids` 替换 `count: all`（两者不能同时指定），再根据 `-l` 输出配置容器内索引。

### 3. 命令参数

| 参数名称 | 含义 | 适用脚本 |
| --- | --- | --- |
| `--label` | 必填实例标签，自动转为小写；支持字母、数字、下划线、连字符，首字符为字母或数字 | `start.sh`、`close.sh`、`rerun.sh` |

## Usage

以下命令在项目根目录执行；脚本也支持从其他工作目录通过绝对路径调用。
如果当前用户没有 Docker 权限，在命令前加 `sudo`；构建时需要保留环境变量，可使用 `sudo -E`。

### 1. 构建项目

```bash
bash scripts/build.sh

# 按显卡和驱动调整 CUDA 版本、计算能力。
CUDA_VERSION=12.8 COMPUTE=86 bash scripts/build.sh

# 从指定 Git 提交构建；也可指定上游标签或分支。
GPU_BURN_REF=0d19c94dcb2e9b6858b7586a4c327674cd67113b bash scripts/build.sh
```

镜像名称为 `rise-tool-gpu-burn:v1.0.0`。编译和运行阶段均基于 `rockylinux:9-minimal`。
构建阶段使用 Git 浅拉取指定版本，安装 CUDA 编译器、开发库及 C++ 工具链；
运行阶段仅安装 CUDA Runtime、cuBLAS 等运行依赖，并复制 `gpu_burn`、`compare.fatbin`、
启动脚本、上游许可证及实际构建提交记录，不包含 Git 和编译工具链。
容器内不安装 NVIDIA 驱动，驱动及 `nvidia-smi` 由主机的 NVIDIA Container Toolkit 注入。

如果使用分支或可移动标签，Docker 的构建缓存不会自动感知远端更新；更新时请运行
`docker compose build --no-cache`，或将 `GPU_BURN_REF` 改为新的完整提交 SHA 后重新构建。

### 2. 启动测试

```bash
# 编辑 envs/rise-service-gpu-burn-1.env 后启动。
bash scripts/start.sh --label 1

# 查看进度、错误计数与最终结果。
docker logs -f rise-service-gpu-burn-1

# 查看容器状态及进程退出码。
docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' rise-service-gpu-burn-1
```

测试在后台运行，到达设定时长后退出，不会自动重启。测试结束后容器及日志保留，
便于检查结果。启动成功仅表示容器已创建；请检查日志中目标 GPU 的最终 `OK` / `FAULTY`
与错误信息。上游即使报告 `FAULTY` 也可能返回 `0`，不能仅靠进程退出码判断测试通过。

双卡主机可独立运行实例 2：

```bash
bash scripts/start.sh --label 2
docker logs -f rise-service-gpu-burn-2
```

新增实例时复制配置文件，并设置唯一容器名称和正确的 GPU 索引：

```bash
cp envs/rise-service-gpu-burn-1.env envs/rise-service-gpu-burn-lab.env
# 编辑新文件，将 CONTAINER_NAME 改为 rise-service-gpu-burn-lab。
bash scripts/start.sh --label lab
```

Shell 中同名环境变量优先于实例文件；排查配置时可查看实际 Compose 配置：

```bash
docker compose --env-file envs/rise-service-gpu-burn-1.env config
```

### 3. 关闭、重启与清理

```bash
bash scripts/close.sh --label 1
bash scripts/rerun.sh --label 1

# 关闭并删除 envs 中所有本项目实例的容器、网络，然后删除项目镜像。
bash scripts/clean.sh
```

`close.sh` 保留容器与日志；`rerun.sh` 会重新开始测试。`clean.sh` 删除容器时也会删除其日志，
需要保留结果时先用 `docker logs <容器名> > result.log 2>&1` 导出。
请保留实例 `.env` 文件，直到该实例清理完成；清理脚本通过这些文件确定实例列表。

### 4. 使用上游原生命令

显式传入参数会覆盖所有 `GPU_BURN_*` 配置，直接交给 `gpu_burn`。
`-h` 查看帮助，`-l` 列出 GPU；二进制依赖主机 CUDA 驱动库，两者均需 GPU runtime。

```bash
docker run --rm --gpus all rise-tool-gpu-burn:v1.0.0 -h
docker run --rm --gpus all rise-tool-gpu-burn:v1.0.0 -l
docker run --rm --gpus all rise-tool-gpu-burn:v1.0.0 -m 50% -tc 3600

# 通过 Compose 临时运行；会按所选实例名创建临时容器。
docker compose -p rise-service-gpu-burn-1 \
  --env-file envs/rise-service-gpu-burn-1.env \
  run --rm rise-tool-gpu-burn -l
```

不传参数时使用环境变量，默认测试 60 秒、使用 90% 可用显存。
直接运行 `docker run --gpus all` 且不设置 GPU 索引时，会测试全部可见 GPU。

## Development

- `bin/gpu-burn.sh`：实例环境变量校验、参数转换和进程启动。
- `scripts/`：沿用模板的 `build/start/close/rerun/clean/share` 脚本结构。
- `envs/`：按标签管理实例配置；新增的本地 `.env` 文件默认被 Git 忽略。
- `Dockerfile`：Rocky Linux / CUDA 多阶段构建，以及上游 Git 源码拉取。
- `tests/smoke.sh`：无需 Docker/GPU 的脚本集成测试，使用替身验证命令与参数。

```bash
bash tests/smoke.sh
```

项目不再保存上游源码副本。构建时从 `GPU_BURN_REPOSITORY` 拉取 `GPU_BURN_REF`，
默认固定上游提交 `0d19c94dcb2e9b6858b7586a4c327674cd67113b`。
构建网络需要能访问 Git 仓库、Rocky Linux 软件源和 NVIDIA CUDA RPM 仓库。
上游 BSD-2-Clause 许可证与实际提交 SHA 保存在镜像的 `/usr/share/licenses/gpu-burn/`：

```bash
docker run --rm --entrypoint cat rise-tool-gpu-burn:v1.0.0 \
  /usr/share/licenses/gpu-burn/UPSTREAM_COMMIT
```

更新时修改 `GPU_BURN_REF` 后重新构建，并在 NVIDIA GPU 主机上验证设备枚举、短时测试、
停止及最终结果。CUDA 系列改变时，也需确认主机驱动版本和目标显卡兼容。
