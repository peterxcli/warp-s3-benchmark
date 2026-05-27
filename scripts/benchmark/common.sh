#!/usr/bin/env bash

set -euo pipefail

benchmark_log() {
  printf '[benchmark] %s\n' "$*" >&2
}

provider_container_name() {
  local provider="$1"
  printf 'warp-benchmark-%s' "${provider}"
}

docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

resolve_image() {
  local image="$1"
  docker pull "${image}" >/dev/null
  local digest
  digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "${image}" 2>/dev/null || true)"
  if [[ -z "${digest}" || "${digest}" == "<no value>" ]]; then
    digest="${image}"
  fi
  printf '%s\n' "${digest}"
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-180}"
  local started
  started="$(date +%s)"
  while true; do
    if curl -fsS --max-time 3 "${url}" >/dev/null 2>&1; then
      return 0
    fi
    if (( $(date +%s) - started >= timeout_seconds )); then
      benchmark_log "Timed out waiting for ${url}"
      return 1
    fi
    sleep 2
  done
}

wait_for_tcp() {
  local address="$1"
  local timeout_seconds="${2:-180}"
  local host="${address%:*}"
  local port="${address##*:}"
  local started
  started="$(date +%s)"
  while true; do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      return 0
    fi
    if (( $(date +%s) - started >= timeout_seconds )); then
      benchmark_log "Timed out waiting for TCP ${address}"
      return 1
    fi
    sleep 2
  done
}

wait_for_warp_s3() {
  local address="$1"
  local access_key="$2"
  local secret_key="$3"
  local bucket="$4"
  local timeout_seconds="${5:-300}"
  local started
  local probe_dir
  local probe_log
  local benchdata
  local exit_code
  local command_timeout
  local -a timeout_prefix
  local -a probe_command
  if [[ ! -x "${WARP_BINARY}" ]]; then
    benchmark_log "Warp binary is not executable: ${WARP_BINARY}"
    return 1
  fi
  started="$(date +%s)"
  command_timeout="${WARP_S3_PROBE_COMMAND_TIMEOUT:-30s}"
  timeout_prefix=()
  if command -v timeout >/dev/null 2>&1; then
    timeout_prefix=(timeout "${command_timeout}")
  fi
  probe_dir="${RUNNER_TEMP:-/tmp}/warp-s3-readiness"
  mkdir -p "${probe_dir}"
  probe_log="${probe_dir}/${bucket}.log"
  benchdata="${probe_dir}/${bucket}.csv.zst"
  while true; do
    rm -f "${probe_log}" "${benchdata}"
    probe_command=(
      "${WARP_BINARY}" put
      --host="${address}"
      --access-key="${access_key}"
      --secret-key="${secret_key}"
      --bucket="${bucket}"
      --duration=1s
      --concurrent=1
      --obj.size=1KiB
      --benchdata="${benchdata}"
      --autoterm
    )
    set +e
    if (( ${#timeout_prefix[@]} > 0 )); then
      "${timeout_prefix[@]}" "${probe_command[@]}" >"${probe_log}" 2>&1
    else
      "${probe_command[@]}" >"${probe_log}" 2>&1
    fi
    exit_code="$?"
    set -e
    if [[ "${exit_code}" -eq 0 ]]; then
      rm -f "${probe_log}" "${benchdata}"
      return 0
    fi
    if (( $(date +%s) - started >= timeout_seconds )); then
      benchmark_log "Timed out waiting for S3 readiness at ${address}"
      if [[ -s "${probe_log}" ]]; then
        tail -n 20 "${probe_log}" >&2 || true
      fi
      return 1
    fi
    sleep 5
  done
}

run_warp_warmup() {
  local address="$1"
  local access_key="$2"
  local secret_key="$3"
  local bucket="$4"
  local output_root="$5"
  local enabled
  local warmup_bucket
  local duration
  local concurrent
  local object_size
  local warmup_dir
  local warmup_log
  local benchdata
  local exit_code
  local -a warmup_command
  enabled="${WARP_WARMUP:-true}"
  if [[ "${enabled}" != "true" ]]; then
    benchmark_log "Skipping Warp warmup because WARP_WARMUP=${enabled}"
    return 0
  fi
  if [[ ! -x "${WARP_BINARY}" ]]; then
    benchmark_log "Warp binary is not executable: ${WARP_BINARY}"
    return 1
  fi
  warmup_bucket="${WARP_WARMUP_BUCKET:-${bucket}-warmup}"
  duration="${WARP_WARMUP_DURATION:-10s}"
  concurrent="${WARP_WARMUP_CONCURRENCY:-4}"
  object_size="${WARP_WARMUP_OBJECT_SIZE:-128KiB}"
  warmup_dir="${RUNNER_TEMP:-/tmp}/warp-s3-warmup"
  warmup_log="${output_root}/warmup.log"
  benchdata="${warmup_dir}/${warmup_bucket}.csv.zst"
  mkdir -p "${warmup_dir}" "${output_root}"
  rm -f "${benchdata}" "${warmup_log}"
  warmup_command=(
    "${WARP_BINARY}" put
    --host="${address}"
    --access-key="${access_key}"
    --secret-key="${secret_key}"
    --bucket="${warmup_bucket}"
    --duration="${duration}"
    --concurrent="${concurrent}"
    --obj.size="${object_size}"
    --benchdata="${benchdata}"
    --autoterm
  )
  benchmark_log "Running Warp warmup for ${warmup_bucket} (${duration}, c${concurrent}, ${object_size})"
  {
    printf 'Command:'
    printf ' %q' "${warmup_command[@]}"
    printf '\n\n'
  } >"${warmup_log}"
  set +e
  "${warmup_command[@]}" >>"${warmup_log}" 2>&1
  exit_code="$?"
  set -e
  rm -f "${benchdata}" || true
  if [[ "${exit_code}" -ne 0 ]]; then
    benchmark_log "Warp warmup failed for ${warmup_bucket}"
    tail -n 20 "${warmup_log}" >&2 || true
    return "${exit_code}"
  fi
  return 0
}

wait_for_container_log() {
  local container="$1"
  local pattern="$2"
  local timeout_seconds="${3:-180}"
  local started
  started="$(date +%s)"
  while true; do
    if docker logs "${container}" 2>&1 | grep -qE "${pattern}"; then
      return 0
    fi
    if (( $(date +%s) - started >= timeout_seconds )); then
      benchmark_log "Timed out waiting for ${container} log pattern ${pattern}"
      return 1
    fi
    sleep 2
  done
}

remove_container() {
  local container="$1"
  docker rm -f "${container}" >/dev/null 2>&1 || true
}

benchmark_diagnostics_enabled() {
  case "${BENCHMARK_DIAGNOSTICS:-false}" in
    true|TRUE|1|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

benchmark_diagnostic_container_ids() {
  if declare -F provider_diagnostic_container_ids >/dev/null; then
    provider_diagnostic_container_ids
    return
  fi
  docker ps -aq --filter "name=^/$(provider_container_name "${PROVIDER}")$"
}

benchmark_diagnostic_safe_name() {
  local container="$1"
  local name
  name="$(docker inspect --format '{{.Name}}' "${container}" 2>/dev/null | sed 's#^/##' || true)"
  if [[ -z "${name}" ]]; then
    name="${container}"
  fi
  printf '%s' "${name}" | tr -c 'A-Za-z0-9_.-' '_'
}

benchmark_diagnostic_safe_token() {
  local value="$1"
  printf '%s' "${value}" | tr -c 'A-Za-z0-9_.-' '_'
}

benchmark_diagnostic_snapshot() {
  local phase="$1"
  local diagnostics_dir="${OUTPUT_ROOT}/diagnostics/generic"
  local container
  local safe_name
  local -a containers
  mkdir -p "${diagnostics_dir}"
  mapfile -t containers < <(benchmark_diagnostic_container_ids | sed '/^$/d')
  if (( ${#containers[@]} == 0 )); then
    benchmark_log "Diagnostics ${phase}: no containers found for ${PROVIDER}"
    printf 'No containers found for provider %s\n' "${PROVIDER}" > "${diagnostics_dir}/${phase}-containers.txt"
    return 0
  fi

  docker ps --no-trunc --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
    > "${diagnostics_dir}/${phase}-docker-ps.txt" 2>&1 || true
  printf '%s\n' "${containers[@]}" > "${diagnostics_dir}/${phase}-container-ids.txt"
  for container in "${containers[@]}"; do
    safe_name="$(benchmark_diagnostic_safe_name "${container}")"
    docker inspect "${container}" > "${diagnostics_dir}/${phase}-${safe_name}-inspect.json" 2>&1 || true
    docker stats --no-stream "${container}" > "${diagnostics_dir}/${phase}-${safe_name}-stats.txt" 2>&1 || true
    docker top "${container}" -eo pid,ppid,nlwp,pcpu,pmem,comm,args \
      > "${diagnostics_dir}/${phase}-${safe_name}-top.txt" 2>&1 \
      || docker top "${container}" > "${diagnostics_dir}/${phase}-${safe_name}-top.txt" 2>&1 \
      || true
    docker exec "${container}" sh -lc 'cat /sys/fs/cgroup/cpu.stat 2>/dev/null || true; printf "\n--- io.stat ---\n"; cat /sys/fs/cgroup/io.stat 2>/dev/null || true; printf "\n--- memory.current ---\n"; cat /sys/fs/cgroup/memory.current 2>/dev/null || true; printf "\n--- pids.current ---\n"; cat /sys/fs/cgroup/pids.current 2>/dev/null || true; printf "\n--- pids.max ---\n"; cat /sys/fs/cgroup/pids.max 2>/dev/null || true' \
      > "${diagnostics_dir}/${phase}-${safe_name}-cgroup.txt" 2>&1 || true
  done
}

generic_provider_diagnostics_start() {
  benchmark_diagnostics_enabled || return 0
  local diagnostics_dir="${OUTPUT_ROOT}/diagnostics/generic"
  local interval="${BENCHMARK_DIAGNOSTICS_INTERVAL:-5}"
  mkdir -p "${diagnostics_dir}"
  benchmark_log "Starting generic diagnostics for ${PROVIDER}"
  benchmark_diagnostic_snapshot start
  (
    while true; do
      date -u '+%Y-%m-%dT%H:%M:%SZ'
      mapfile -t containers < <(benchmark_diagnostic_container_ids | sed '/^$/d')
      if (( ${#containers[@]} == 0 )); then
        printf 'No containers found for provider %s\n' "${PROVIDER}"
      else
        docker stats --no-stream "${containers[@]}" || true
      fi
      sleep "${interval}"
    done
  ) > "${diagnostics_dir}/docker-stats-samples.txt" 2>&1 &
  printf '%s\n' "$!" > "${diagnostics_dir}/docker-stats-sampler.pid"
}

generic_profile_diagnostics_start() {
  benchmark_diagnostics_enabled || return 0
  local profile_id="$1"
  local safe_profile
  safe_profile="$(benchmark_diagnostic_safe_token "${profile_id}")"
  benchmark_log "Starting profile diagnostics for ${PROVIDER} ${profile_id}"
  benchmark_diagnostic_snapshot "profile-${safe_profile}-start"
}

generic_profile_diagnostics_collect() {
  benchmark_diagnostics_enabled || return 0
  local profile_id="$1"
  local safe_profile
  safe_profile="$(benchmark_diagnostic_safe_token "${profile_id}")"
  benchmark_log "Collecting profile diagnostics for ${PROVIDER} ${profile_id}"
  benchmark_diagnostic_snapshot "profile-${safe_profile}-end"
}

generic_provider_diagnostics_collect() {
  benchmark_diagnostics_enabled || return 0
  local diagnostics_dir="${OUTPUT_ROOT}/diagnostics/generic"
  local sampler_pid
  mkdir -p "${diagnostics_dir}"
  if [[ -f "${diagnostics_dir}/docker-stats-sampler.pid" ]]; then
    sampler_pid="$(cat "${diagnostics_dir}/docker-stats-sampler.pid")"
    kill "${sampler_pid}" >/dev/null 2>&1 || true
  fi
  benchmark_log "Collecting generic diagnostics for ${PROVIDER}"
  benchmark_diagnostic_snapshot end
}

run_benchmark_profile_command() {
  local profile_id="$1"
  local command_line="$2"
  local output_file="$3"
  local diagnostics_dir
  local safe_profile

  if benchmark_diagnostics_enabled; then
    safe_profile="$(benchmark_diagnostic_safe_token "${profile_id}")"
    diagnostics_dir="${OUTPUT_ROOT}/diagnostics/profiles/${safe_profile}"
    mkdir -p "${diagnostics_dir}"
    printf '%s\n' "${command_line}" > "${diagnostics_dir}/warp-command.txt"
    if [[ -x /usr/bin/time ]] && /usr/bin/time -v true >/dev/null 2>&1; then
      /usr/bin/time -v -o "${diagnostics_dir}/warp-time.txt" \
        bash -lc "${command_line}" > "${output_file}" 2>&1
      return "$?"
    fi
  fi

  bash -lc "${command_line}" > "${output_file}" 2>&1
}

write_runner_json() {
  python3 - <<'PY'
import json
import os
import platform
import shutil

runner = {
    "os": platform.platform(),
    "machine": platform.machine(),
    "python": platform.python_version(),
    "cpu_count": os.cpu_count() or 0,
}
disk = shutil.disk_usage(os.getcwd())
runner["disk_total_bytes"] = disk.total
runner["disk_free_bytes"] = disk.free
print(json.dumps(runner, sort_keys=True))
PY
}
