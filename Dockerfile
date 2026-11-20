# Use NVIDIA's RHEL 9 RPM repository on Rocky Linux; do not install a host driver.
FROM rockylinux:9-minimal AS cuda-base

ARG CUDA_VERSION=12.8

# Rocky Minimal already supplies curl and coreutils-single; keep those package variants.
RUN test "$(uname -m)" = x86_64 \
    && microdnf install -y ca-certificates bash grep libstdc++ \
    && printf '%s\n' "$CUDA_VERSION" | grep -Eq '^[0-9]+\.[0-9]+$' \
    && curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo \
         -o /etc/yum.repos.d/cuda-rhel9.repo \
    && microdnf clean all

ENV CUDA_HOME=/usr/local/cuda-${CUDA_VERSION}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

FROM cuda-base AS builder

ARG COMPUTE=75
ARG NVCCFLAGS=""
ARG GPU_BURN_REPOSITORY=https://github.com/wilicc/gpu-burn.git
ARG GPU_BURN_REF=0d19c94dcb2e9b6858b7586a4c327674cd67113b

RUN cuda_series="$(printf '%s' "$CUDA_VERSION" | tr . -)" \
    && microdnf install -y gcc-c++ make git-core \
         "cuda-nvcc-${cuda_series}" "cuda-cudart-devel-${cuda_series}" \
         "cuda-driver-devel-${cuda_series}" "libcublas-devel-${cuda_series}" \
    && microdnf clean all

WORKDIR /build
RUN git init . \
    && git remote add origin "$GPU_BURN_REPOSITORY" \
    && git fetch --depth 1 origin "$GPU_BURN_REF" \
    && git checkout --detach FETCH_HEAD \
    && git rev-parse HEAD > /build/UPSTREAM_COMMIT \
    && make CUDAPATH="$CUDA_HOME" COMPUTE="$COMPUTE" NVCCFLAGS="$NVCCFLAGS"

FROM cuda-base AS runtime

RUN cuda_series="$(printf '%s' "$CUDA_VERSION" | tr . -)" \
    && microdnf install -y "cuda-cudart-${cuda_series}" "libcublas-${cuda_series}" \
    && microdnf clean all

LABEL org.opencontainers.image.title="rise-tool-gpu-burn" \
      org.opencontainers.image.description="Multi-GPU CUDA stress test" \
      org.opencontainers.image.source="https://github.com/rise-tool/rise-tool-gpu-burn"

WORKDIR /app
COPY --from=builder /build/gpu_burn /build/compare.fatbin ./
COPY --from=builder /build/LICENSE /build/UPSTREAM_COMMIT /usr/share/licenses/gpu-burn/
COPY --chmod=0755 bin/gpu-burn.sh /usr/local/bin/gpu-burn.sh

ENTRYPOINT ["/usr/local/bin/gpu-burn.sh"]
CMD []
