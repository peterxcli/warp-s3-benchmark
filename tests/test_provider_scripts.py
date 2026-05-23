from pathlib import Path


PROVIDER_DIR = Path("scripts/benchmark/providers")


def provider_script(name: str) -> str:
    return (PROVIDER_DIR / f"{name}.sh").read_text(encoding="utf-8")


def test_ozone_provider_uses_default_container_and_block_sizes() -> None:
    script = provider_script("ozone")

    assert "write_ozone_compose_override" in script
    assert "OZONE-SITE.XML_hdds.datanode.volume.min.free.space" in script
    assert "OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min" in script
    assert "OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit" in script
    assert "OZONE-SITE.XML_ozone.server.default.replication" in script
    assert "OZONE-SITE.XML_ozone.scm.block.size" not in script
    assert "${OZONE_DATANODES:-3}" in script
    assert 'up -d --scale datanode="${OZONE_DATANODES:-3}" scm om datanode s3g' in script
    compose_override = script.split("cat > \"${override_file}\" <<'OVERRIDE'", 1)[1].split("OVERRIDE", 1)[0]
    assert "OZONE-SITE.XML_ozone.scm.container.size" not in compose_override
    assert "recon" not in script.split('up -d --scale datanode="${OZONE_DATANODES:-3}"', 1)[1].split("|| return 1", 1)[0]
    assert "httpfs" not in script.split('up -d --scale datanode="${OZONE_DATANODES:-3}"', 1)[1].split("|| return 1", 1)[0]


def test_ozone_provider_can_use_experimental_local_mode() -> None:
    script = provider_script("ozone")

    assert 'OZONE_DEPLOYMENT_MODE:-compose}" == "local"' in script
    assert "write_ozone_local_compose" in script
    assert "apache/ozone-runner:20260206-2-jdk21" in script
    assert "${OZONE_LOCAL_DIST_DIR:-.}:/opt/hadoop" in script
    assert "OZONE_LOCAL_COMPOSE_FILE" in script
    assert "OZONE_LOCAL_COMPOSE_ENV_FILE" in script
    assert "OZONE-SITE.XML_ozone.scm.pipeline.owner.container.count=${OZONE_LOCAL_PIPELINE_OWNER_CONTAINER_COUNT:-3}" in script
    assert "ozone-local-data:/root/.ozone" in script
    assert "ozone\n      - local\n      - run" in script
    assert "OZONE_LOCAL_DATANODES:-1" in script
    assert "OZONE_LOCAL_STARTUP_TIMEOUT:-600s" in script
    assert "OZONE_LOCAL_TCP_TIMEOUT:-720" in script
    assert "OZONE_LOCAL_READY_TIMEOUT:-900" in script


def test_ceph_provider_publishes_rgw_port_without_host_network() -> None:
    script = provider_script("ceph")

    assert "network_mode: host" not in script
    assert '"${CEPH_PORT:-8080}:8080"' in script
    assert "CEPH_DEMO_UID: warp-benchmark" in script
    assert "CEPH_DEMO_ACCESS_KEY: ${WARP_ACCESS_KEY}" in script
    assert "Ceph container exited before RGW user" in script


def test_readiness_probe_runs_without_gnu_timeout() -> None:
    script = Path("scripts/benchmark/common.sh").read_text(encoding="utf-8")

    assert "probe_command=(" in script
    assert "if (( ${#timeout_prefix[@]} > 0 )); then" in script


def test_warmup_runs_against_discarded_bucket() -> None:
    script = Path("scripts/benchmark/common.sh").read_text(encoding="utf-8")

    assert "run_warp_warmup()" in script
    assert 'warmup_bucket="${WARP_WARMUP_BUCKET:-${bucket}-warmup}"' in script
    assert 'warmup_log="${output_root}/warmup.log"' in script
    assert '--bucket="${warmup_bucket}"' in script
