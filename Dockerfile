# CUDA development tools stay in the builder; the final image only needs runtime libraries.
ARG CUDA_VERSION=12.8.1
ARG IMAGE_DISTRO=ubuntu22.04

FROM nvidia/cuda:${CUDA_VERSION}-devel-${IMAGE_DISTRO} AS builder

ARG COMPUTE=75
ARG NVCCFLAGS=""

RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY vendor/gpu-burn/Makefile vendor/gpu-burn/compare.cu vendor/gpu-burn/gpu_burn-drv.cpp ./
RUN make COMPUTE="${COMPUTE}" NVCCFLAGS="${NVCCFLAGS}"

FROM nvidia/cuda:${CUDA_VERSION}-runtime-${IMAGE_DISTRO}

LABEL org.opencontainers.image.title="rise-tool-gpu-burn" \
      org.opencontainers.image.description="Multi-GPU CUDA stress test" \
      org.opencontainers.image.source="https://github.com/rise-tool/rise-tool-gpu-burn"

WORKDIR /app
COPY --from=builder /build/gpu_burn /build/compare.fatbin ./
COPY vendor/gpu-burn/LICENSE vendor/gpu-burn/UPSTREAM.md /usr/share/licenses/gpu-burn/
COPY --chmod=0755 bin/gpu-burn.sh /usr/local/bin/gpu-burn.sh

ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENTRYPOINT ["/usr/local/bin/gpu-burn.sh"]
CMD []
