#!/usr/bin/env bash

provider_label() {
  printf 'Apache Ozone\n'
}

provider_image() {
  local default_ref
  local repository
  local version
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
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-1}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
         OZONE-SITE.XML_ozone.scm.container.size: "1GB"
   om:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-1}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
         OZONE-SITE.XML_ozone.scm.container.size: "1GB"
   scm:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-1}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
         OZONE-SITE.XML_ozone.scm.container.size: "1GB"
   s3g:
      environment:
         OZONE-SITE.XML_hdds.datanode.volume.min.free.space: "1MB"
         OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min: "1MB"
         OZONE-SITE.XML_hdds.scm.safemode.min.datanode: "${OZONE_DATANODES:-1}"
         OZONE-SITE.XML_hdds.scm.safemode.pipeline.creation: "false"
         OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit: "0s"
         OZONE-SITE.XML_ozone.server.default.replication: "1"
         OZONE-SITE.XML_ozone.server.default.replication.type: "RATIS"
         OZONE-SITE.XML_ozone.scm.container.size: "1GB"
OVERRIDE
}

provider_start() {
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
  docker_compose -f "${compose_file}" -f "${override_file}" up -d --scale datanode="${OZONE_DATANODES:-1}" || return 1
  wait_for_tcp "${WARP_HOST}" 300 || return 1
  wait_for_warp_s3 "${WARP_HOST}" "${WARP_ACCESS_KEY}" "${WARP_SECRET_KEY}" "${WARP_BUCKET}" "${OZONE_READY_TIMEOUT:-420}" || return 1
}

provider_stop() {
  local compose_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.yaml"
  local override_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.override.yaml"
  if [[ -f "${compose_file}" ]]; then
    docker_compose -f "${compose_file}" -f "${override_file}" down -v || true
  fi
}

provider_logs() {
  local compose_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.yaml"
  local override_file="${OUTPUT_ROOT}/ozone-compose/docker-compose.override.yaml"
  if [[ -f "${compose_file}" ]]; then
    docker_compose -f "${compose_file}" -f "${override_file}" logs
  fi
}
