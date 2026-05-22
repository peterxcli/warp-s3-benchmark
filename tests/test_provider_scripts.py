from pathlib import Path


PROVIDER_DIR = Path("scripts/benchmark/providers")


def provider_script(name: str) -> str:
    return (PROVIDER_DIR / f"{name}.sh").read_text(encoding="utf-8")


def test_ozone_provider_overrides_ci_disk_and_replication_limits() -> None:
    script = provider_script("ozone")

    assert "write_ozone_compose_override" in script
    assert "OZONE-SITE.XML_hdds.datanode.volume.min.free.space" in script
    assert "OZONE-SITE.XML_ozone.scm.datanode.ratis.volume.free-space.min" in script
    assert "OZONE-SITE.XML_hdds.scm.wait.time.after.safemode.exit" in script
    assert "OZONE-SITE.XML_ozone.server.default.replication" in script
    assert "OZONE-SITE.XML_ozone.scm.container.size: \"1GB\"" in script
    assert "${OZONE_DATANODES:-1}" in script


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
