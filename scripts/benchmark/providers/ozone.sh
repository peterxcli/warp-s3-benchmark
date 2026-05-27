#!/usr/bin/env bash

provider_label() {
  printf 'Apache Ozone\n'
}

provider_image() {
  local default_ref
  local repository
  local version
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" == "local" ]]; then
    printf '%s\n' "${OZONE_LOCAL_IMAGE:-apache/ozone-runner:20260206-2-jdk21}"
    return
  fi
  default_ref="$(curl -fsSL "https://raw.githubusercontent.com/apache/ozone-docker/refs/heads/latest/docker-compose.yaml" \
    | sed -nE 's/.*\$\{OZONE_IMAGE:-([^}]*)\}:\$\{OZONE_IMAGE_VERSION:-([^}]*)\}\$\{OZONE_IMAGE_FLAVOR:-[^}]*\}.*/\1:\2/p' \
    | head -n 1)"
  repository="${OZONE_IMAGE:-${default_ref%:*}}"
  version="${OZONE_IMAGE_VERSION:-${default_ref#*:}}"
  printf '%s:%s%s\n' "${repository}" "${version}" "${OZONE_IMAGE_FLAVOR:-}"
}

write_ozone_compose_override() {
  local override_file="$1"
  cat > "${override_file}" <<'OVERRIDE'
services:
   datanode:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-3}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
   om:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-3}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
   scm:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-3}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
   s3g:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-3}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
OVERRIDE
}

write_ozone_local_compose() {
  local compose_file="$1"
  cat > "${compose_file}" <<'COMPOSE'
services:
  local:
    image: ${OZONE_LOCAL_IMAGE:-apache/ozone-runner:20260206-2-jdk21}
    user: "0:0"
    volumes:
      - ${OZONE_LOCAL_DIST_DIR:-.}:/opt/hadoop
      - ozone-local-data:/root/.ozone
    environment:
      - AWS_ACCESS_KEY_ID=${OZONE_ACCESS_KEY:-admin}
      - AWS_SECRET_ACCESS_KEY=${OZONE_SECRET_KEY:-admin123}
      - OZONE_LOCAL_DATANODES=${OZONE_LOCAL_DATANODES:-1}
      - OZONE_LOCAL_FORMAT=${OZONE_LOCAL_FORMAT:-always}
      - OZONE_LOCAL_RECON_ENABLED=${OZONE_LOCAL_RECON_ENABLED:-false}
      - OZONE_LOCAL_STARTUP_TIMEOUT=${OZONE_LOCAL_STARTUP_TIMEOUT:-600s}
      - OZONE-SITE.XML_ozone.scm.pipeline.owner.container.count=${OZONE_LOCAL_PIPELINE_OWNER_CONTAINER_COUNT:-1}
      - OZONE-SITE.XML_ozone.scm.container.size=${OZONE_LOCAL_CONTAINER_SIZE:-80MB}
      - OZONE-SITE.XML_ozone.scm.block.size=${OZONE_LOCAL_BLOCK_SIZE:-64MB}
      - OZONE-SITE.XML_ozone.block.deleting.service.interval=${OZONE_LOCAL_BLOCK_DELETING_INTERVAL:-1s}
      - OZONE-SITE.XML_hdds.scm.block.deleting.service.interval=${OZONE_LOCAL_SCM_BLOCK_DELETING_INTERVAL:-1s}
      - OZONE-SITE.XML_ozone.block.deleting.service.workers=${OZONE_LOCAL_BLOCK_DELETING_WORKERS:-20}
      - OZONE-SITE.XML_hdds.scm.block.deletion.per-interval.max=${OZONE_LOCAL_SCM_BLOCK_DELETION_LIMIT:-500000}
      - OZONE-SITE.XML_ozone.chunk.read.netty.ChunkedNioFile=${OZONE_LOCAL_READ_NETTY_CHUNKED_NIO_FILE:-false}
      - OZONE-SITE.XML_ozone.client.verify.checksum=${OZONE_LOCAL_CLIENT_VERIFY_CHECKSUM:-true}
      - OZONE-SITE.XML_ozone.client.stream.readblock.enable=${OZONE_LOCAL_STREAM_READBLOCK_ENABLE:-false}
    ports:
      - "${OZONE_S3G_PORT:-9878}:9878"
    command:
      - ozone
      - local
      - run
      - --s3g-port
      - "9878"
volumes:
  ozone-local-data:
COMPOSE
}

provider_start_compose() {
  local _image="$1"
  local compose_dir="${OUTPUT_ROOT}/ozone-compose"
  local compose_file="${compose_dir}/docker-compose.yaml"
  local override_file="${compose_dir}/docker-compose.override.yaml"
  mkdir -p "${compose_dir}"
  export WARP_HOST="${OZONE_HOST:-127.0.0.1:9878}"
  export WARP_ACCESS_KEY="${OZONE_ACCESS_KEY:-testuser}"
  export WARP_SECRET_KEY="${OZONE_SECRET_KEY:-testuser-secret}"
  curl -fsSL "https://raw.githubusercontent.com/apache/ozone-docker/refs/heads/latest/docker-compose.yaml" \
    -o "${compose_file}" || return 1
  write_ozone_compose_override "${override_file}"
  docker_compose -f "${compose_file}" -f "${override_file}" up -d --scale datanode="${OZONE_DATANODES:-3}" scm om datanode s3g || return 1
  wait_for_tcp "${WARP_HOST}" 300 || return 1
  wait_for_warp_s3 "${WARP_HOST}" "${WARP_ACCESS_KEY}" "${WARP_SECRET_KEY}" "${WARP_BUCKET}" "${OZONE_READY_TIMEOUT:-420}" || return 1
}

provider_start_local() {
  local image="$1"
  local compose_dir="${OUTPUT_ROOT}/ozone-local-compose"
  local compose_file="${compose_dir}/docker-compose.yaml"
  local env_file=""
  mkdir -p "${compose_dir}"
  export OZONE_LOCAL_IMAGE="${image}"
  export WARP_HOST="${OZONE_HOST:-127.0.0.1:${OZONE_S3G_PORT:-9878}}"
  export WARP_ACCESS_KEY="${OZONE_ACCESS_KEY:-admin}"
  export WARP_SECRET_KEY="${OZONE_SECRET_KEY:-admin123}"
  if [[ -n "${OZONE_LOCAL_COMPOSE_FILE:-}" ]]; then
    compose_file="${OZONE_LOCAL_COMPOSE_FILE}"
    env_file="${OZONE_LOCAL_COMPOSE_ENV_FILE:-$(dirname "${compose_file}")/.env}"
  else
    export OZONE_LOCAL_DIST_DIR="${OZONE_LOCAL_DIST_DIR:-${PWD}}"
    write_ozone_local_compose "${compose_file}"
  fi
  if [[ -n "${env_file}" && -f "${env_file}" ]]; then
    docker_compose --env-file "${env_file}" -f "${compose_file}" up -d local || return 1
  else
    docker_compose -f "${compose_file}" up -d local || return 1
  fi
  wait_for_tcp "${WARP_HOST}" "${OZONE_LOCAL_TCP_TIMEOUT:-720}" || return 1
  wait_for_warp_s3 "${WARP_HOST}" "${WARP_ACCESS_KEY}" "${WARP_SECRET_KEY}" "${WARP_BUCKET}" "${OZONE_LOCAL_READY_TIMEOUT:-900}" || return 1
}

provider_start() {
  local image="$1"
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" == "local" ]]; then
    provider_start_local "${image}"
  else
    provider_start_compose "${image}"
  fi
}

provider_stop() {
  local compose_file
  local override_file
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" == "local" ]]; then
    compose_file="${OZONE_LOCAL_COMPOSE_FILE:-${OUTPUT_ROOT}/ozone-local-compose/docker-compose.yaml}"
    if [[ -f "${compose_file}" ]]; then
      if [[ -n "${OZONE_LOCAL_COMPOSE_ENV_FILE:-}" && -f "${OZONE_LOCAL_COMPOSE_ENV_FILE}" ]]; then
        docker_compose --env-file "${OZONE_LOCAL_COMPOSE_ENV_FILE}" -f "${compose_file}" down -v || true
      else
        docker_compose -f "${compose_file}" down -v || true
      fi
    fi
  else
    compose_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.yaml"
    override_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.override.yaml"
    if [[ -f "${compose_file}" ]]; then
      docker_compose -f "${compose_file}" -f "${override_file}" down -v || true
    fi
  fi
}

provider_logs() {
  local compose_file
  local override_file
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" == "local" ]]; then
    compose_file="${OZONE_LOCAL_COMPOSE_FILE:-${OUTPUT_ROOT}/ozone-local-compose/docker-compose.yaml}"
    if [[ -f "${compose_file}" ]]; then
      if [[ -n "${OZONE_LOCAL_COMPOSE_ENV_FILE:-}" && -f "${OZONE_LOCAL_COMPOSE_ENV_FILE}" ]]; then
        docker_compose --env-file "${OZONE_LOCAL_COMPOSE_ENV_FILE}" -f "${compose_file}" logs
      else
        docker_compose -f "${compose_file}" logs
      fi
    fi
  else
    compose_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.yaml"
    override_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.override.yaml"
    if [[ -f "${compose_file}" ]]; then
      docker_compose -f "${compose_file}" -f "${override_file}" logs
    fi
  fi
}

ozone_local_container_id() {
  local compose_file
  compose_file="${OZONE_LOCAL_COMPOSE_FILE:-${OUTPUT_ROOT}/ozone-local-compose/docker-compose.yaml}"
  if [[ ! -f "${compose_file}" ]]; then
    return 1
  fi
  if [[ -n "${OZONE_LOCAL_COMPOSE_ENV_FILE:-}" && -f "${OZONE_LOCAL_COMPOSE_ENV_FILE}" ]]; then
    docker_compose --env-file "${OZONE_LOCAL_COMPOSE_ENV_FILE}" -f "${compose_file}" ps -q local
  else
    docker_compose -f "${compose_file}" ps -q local
  fi
}

ozone_local_jvm_pid() {
  jcmd -l 2>/dev/null | awk '
    /jdk[.]jcmd|sun[.]tools[.]jcmd[.]JCmd|[[:space:]]JCmd([[:space:]]|$)/ {
      next
    }
    first == "" {
      first = $1
    }
    tolower($0) ~ /(org[.]apache[.]hadoop[.](ozone|hdds)|ozone|hdds)/ && preferred == "" {
      preferred = $1
    }
    END {
      if (preferred != "") {
        print preferred
      } else if (first != "") {
        print first
      }
    }
  '
}

ozone_local_jcmd_preamble() {
  declare -f ozone_local_jvm_pid
  cat <<'SCRIPT'
printf '%s\n' 'jcmd -l:'
jcmd -l 2>&1 || true
pid="$(ozone_local_jvm_pid)"
test -n "${pid}" || pid=1
printf 'Selected JVM PID: %s\n' "${pid}"
SCRIPT
}

ozone_jvm_pids() {
  jcmd -l 2>/dev/null | awk '
    /jdk[.]jcmd|sun[.]tools[.]jcmd[.]JCmd|[[:space:]]JCmd([[:space:]]|$)/ {
      next
    }
    NF > 0 {
      print $1
    }
  '
}

ozone_jvm_pids_preamble() {
  declare -f ozone_jvm_pids
  cat <<'SCRIPT'
printf '%s\n' 'jcmd -l:'
jcmd -l 2>&1 || true
SCRIPT
}

provider_diagnostic_container_ids() {
  local compose_file
  local override_file
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" == "local" ]]; then
    ozone_local_container_id
  else
    compose_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.yaml"
    override_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.override.yaml"
    if [[ -f "${compose_file}" ]]; then
      docker_compose -f "${compose_file}" -f "${override_file}" ps -q
    fi
  fi
}

provider_profile_diagnostics_start() {
  benchmark_diagnostics_enabled || return 0

  local profile_id="$1"
  local safe_profile
  local recording_name
  local diagnostics_dir
  local container
  local safe_container
  local jcmd_preamble
  local -a containers
  safe_profile="$(benchmark_diagnostic_safe_token "${profile_id}")"
  recording_name="warp_${safe_profile}"
  recording_name="${recording_name//-/_}"
  recording_name="${recording_name//./_}"
  diagnostics_dir="${OUTPUT_ROOT}/diagnostics/profiles/${safe_profile}/ozone-jfr"
  mkdir -p "${diagnostics_dir}"
  mapfile -t containers < <(provider_diagnostic_container_ids | sed '/^$/d')
  jcmd_preamble="$(ozone_jvm_pids_preamble)"

  for container in "${containers[@]}"; do
    safe_container="$(benchmark_diagnostic_safe_name "${container}")"
    mkdir -p "${diagnostics_dir}/${safe_container}"
    docker exec "${container}" sh -lc "${jcmd_preamble}
for pid in \$(ozone_jvm_pids); do
  printf '\n=== JFR start pid %s ===\n' \"\${pid}\"
  jcmd \"\${pid}\" JFR.start name=${recording_name} settings=profile filename=/tmp/${recording_name}-\${pid}.jfr dumponexit=true
done" > "${diagnostics_dir}/${safe_container}/jfr-start.txt" 2>&1 || true
  done
}

provider_profile_diagnostics_collect() {
  benchmark_diagnostics_enabled || return 0

  local profile_id="$1"
  local safe_profile
  local recording_name
  local diagnostics_dir
  local container
  local safe_container
  local jcmd_preamble
  local -a containers
  safe_profile="$(benchmark_diagnostic_safe_token "${profile_id}")"
  recording_name="warp_${safe_profile}"
  recording_name="${recording_name//-/_}"
  recording_name="${recording_name//./_}"
  diagnostics_dir="${OUTPUT_ROOT}/diagnostics/profiles/${safe_profile}/ozone-jfr"
  mkdir -p "${diagnostics_dir}"
  mapfile -t containers < <(provider_diagnostic_container_ids | sed '/^$/d')
  jcmd_preamble="$(ozone_jvm_pids_preamble)"

  for container in "${containers[@]}"; do
    safe_container="$(benchmark_diagnostic_safe_name "${container}")"
    mkdir -p "${diagnostics_dir}/${safe_container}"
    docker exec "${container}" sh -lc "${jcmd_preamble}
for pid in \$(ozone_jvm_pids); do
  recording=/tmp/${recording_name}-\${pid}.jfr
  printf '\n=== Thread.print pid %s ===\n' \"\${pid}\"
  jcmd \"\${pid}\" Thread.print
  printf '\n=== GC.heap_info pid %s ===\n' \"\${pid}\"
  jcmd \"\${pid}\" GC.heap_info
  printf '\n=== JFR.check pid %s ===\n' \"\${pid}\"
  jcmd \"\${pid}\" JFR.check
  printf '\n=== JFR.stop pid %s ===\n' \"\${pid}\"
  jcmd \"\${pid}\" JFR.stop name=${recording_name} filename=\"\${recording}\"
  if test -s \"\${recording}\"; then
    printf '\n=== JFR summary pid %s ===\n' \"\${pid}\"
    jfr summary \"\${recording}\" || true
    printf '\n=== JFR hot-methods pid %s ===\n' \"\${pid}\"
    jfr view --width 160 hot-methods \"\${recording}\" || true
    printf '\n=== JFR allocation-by-site pid %s ===\n' \"\${pid}\"
    jfr view --width 160 allocation-by-site \"\${recording}\" || true
    printf '\n=== JFR container-cpu-usage pid %s ===\n' \"\${pid}\"
    jfr view --width 160 container-cpu-usage \"\${recording}\" || true
  fi
done
printf '\n=== JFR files ===\n'
ls -lh /tmp/${recording_name}-*.jfr 2>/dev/null || true
cd /tmp && tar -czf /tmp/${recording_name}-jfr.tgz ${recording_name}-*.jfr 2>/dev/null || true" \
      > "${diagnostics_dir}/${safe_container}/jfr-end.txt" 2>&1 || true
    docker cp "${container}:/tmp/${recording_name}-jfr.tgz" \
      "${diagnostics_dir}/${safe_container}/jfr-recordings.tgz" >/dev/null 2>&1 || true
  done
}

provider_diagnostics_start() {
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" != "local" ]]; then
    return 0
  fi
  if [[ "${OZONE_DIAGNOSTICS_ENABLED:-${BENCHMARK_DIAGNOSTICS:-false}}" != "true" ]]; then
    return 0
  fi

  local diagnostics_dir
  local container_id
  local jcmd_preamble
  diagnostics_dir="${OUTPUT_ROOT}/diagnostics"
  mkdir -p "${diagnostics_dir}"
  container_id="$(ozone_local_container_id 2>/dev/null || true)"
  if [[ -z "${container_id}" ]]; then
    benchmark_log "Ozone diagnostics skipped: local container not found"
    return 0
  fi

  benchmark_log "Starting Ozone local diagnostics for ${container_id}"
  docker inspect "${container_id}" > "${diagnostics_dir}/container-inspect-start.json" 2>&1 || true
  docker stats --no-stream "${container_id}" > "${diagnostics_dir}/docker-stats-start.txt" 2>&1 || true
  docker exec "${container_id}" sh -lc 'cat /sys/fs/cgroup/cpu.stat; printf "\n--- io.stat ---\n"; cat /sys/fs/cgroup/io.stat 2>/dev/null || true; printf "\n--- memory.current ---\n"; cat /sys/fs/cgroup/memory.current 2>/dev/null || true' > "${diagnostics_dir}/cgroup-start.txt" 2>&1 || true
  jcmd_preamble="$(ozone_local_jcmd_preamble)"
  docker exec "${container_id}" sh -lc "${jcmd_preamble}
jcmd \"\${pid}\" VM.version
jcmd \"\${pid}\" VM.flags
jcmd \"\${pid}\" GC.heap_info
jcmd \"\${pid}\" Thread.print" > "${diagnostics_dir}/jcmd-start.txt" 2>&1 || true
  docker exec "${container_id}" sh -lc "${jcmd_preamble}
jcmd \"\${pid}\" JFR.start name=warp_diag settings=profile filename=/tmp/ozone-warp-diagnostic.jfr dumponexit=true" > "${diagnostics_dir}/jfr-start.txt" 2>&1 || true

  (
    while true; do
      date -u '+%Y-%m-%dT%H:%M:%SZ'
      docker stats --no-stream "${container_id}" || true
      sleep "${OZONE_DIAGNOSTICS_STATS_INTERVAL:-5}"
    done
  ) > "${diagnostics_dir}/docker-stats-samples.txt" 2>&1 &
  printf '%s\n' "$!" > "${diagnostics_dir}/docker-stats-sampler.pid"
}

provider_diagnostics_collect() {
  if [[ "${OZONE_DEPLOYMENT_MODE:-compose}" != "local" ]]; then
    return 0
  fi
  if [[ "${OZONE_DIAGNOSTICS_ENABLED:-${BENCHMARK_DIAGNOSTICS:-false}}" != "true" ]]; then
    return 0
  fi

  local diagnostics_dir
  local container_id
  local jcmd_preamble
  local sampler_pid
  diagnostics_dir="${OUTPUT_ROOT}/diagnostics"
  mkdir -p "${diagnostics_dir}"
  if [[ -f "${diagnostics_dir}/docker-stats-sampler.pid" ]]; then
    sampler_pid="$(cat "${diagnostics_dir}/docker-stats-sampler.pid")"
    kill "${sampler_pid}" >/dev/null 2>&1 || true
  fi

  container_id="$(ozone_local_container_id 2>/dev/null || true)"
  if [[ -z "${container_id}" ]]; then
    benchmark_log "Ozone diagnostics collect skipped: local container not found"
    return 0
  fi

  benchmark_log "Collecting Ozone local diagnostics for ${container_id}"
  docker inspect "${container_id}" > "${diagnostics_dir}/container-inspect-end.json" 2>&1 || true
  docker stats --no-stream "${container_id}" > "${diagnostics_dir}/docker-stats-end.txt" 2>&1 || true
  docker exec "${container_id}" sh -lc 'cat /sys/fs/cgroup/cpu.stat; printf "\n--- io.stat ---\n"; cat /sys/fs/cgroup/io.stat 2>/dev/null || true; printf "\n--- memory.current ---\n"; cat /sys/fs/cgroup/memory.current 2>/dev/null || true' > "${diagnostics_dir}/cgroup-end.txt" 2>&1 || true
  jcmd_preamble="$(ozone_local_jcmd_preamble)"
  docker exec "${container_id}" sh -lc "${jcmd_preamble}
jcmd \"\${pid}\" Thread.print
jcmd \"\${pid}\" GC.heap_info
jcmd \"\${pid}\" JFR.check
jcmd \"\${pid}\" JFR.stop name=warp_diag filename=/tmp/ozone-warp-diagnostic.jfr" > "${diagnostics_dir}/jcmd-end.txt" 2>&1 || true
  docker exec "${container_id}" sh -lc 'test -s /tmp/ozone-warp-diagnostic.jfr && jfr summary /tmp/ozone-warp-diagnostic.jfr' > "${diagnostics_dir}/jfr-summary.txt" 2>&1 || true
  docker cp "${container_id}:/tmp/ozone-warp-diagnostic.jfr" "${diagnostics_dir}/ozone-warp-diagnostic.jfr" >/dev/null 2>&1 || true
}
