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
      - OZONE-SITE.XML_ozone.scm.pipeline.owner.container.count=${OZONE_LOCAL_PIPELINE_OWNER_CONTAINER_COUNT:-3}
      - OZONE-SITE.XML_ozone.scm.container.size=${OZONE_LOCAL_CONTAINER_SIZE:-1GB}
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
