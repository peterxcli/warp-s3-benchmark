import subprocess
import textwrap
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
    assert "${OZONE_DATANODES:-3}" in script
    assert 'up -d --scale datanode="${OZONE_DATANODES:-3}" scm om datanode s3g' in script
    compose_override = script.split("cat > \"${override_file}\" <<'OVERRIDE'", 1)[1].split("OVERRIDE", 1)[0]
    assert "OZONE-SITE.XML_ozone.scm.container.size" not in compose_override
    assert "OZONE-SITE.XML_ozone.scm.block.size" not in compose_override
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
    assert "OZONE-SITE.XML_ozone.scm.pipeline.owner.container.count=${OZONE_LOCAL_PIPELINE_OWNER_CONTAINER_COUNT:-1}" in script
    assert "OZONE-SITE.XML_ozone.scm.container.size=${OZONE_LOCAL_CONTAINER_SIZE:-80MB}" in script
    assert "OZONE-SITE.XML_ozone.scm.block.size=${OZONE_LOCAL_BLOCK_SIZE:-64MB}" in script
    assert "OZONE-SITE.XML_ozone.block.deleting.service.interval=${OZONE_LOCAL_BLOCK_DELETING_INTERVAL:-1s}" in script
    assert "OZONE-SITE.XML_hdds.scm.block.deleting.service.interval=${OZONE_LOCAL_SCM_BLOCK_DELETING_INTERVAL:-1s}" in script
    assert "ozone-local-data:/root/.ozone" in script
    assert "ozone\n      - local\n      - run" in script
    assert "OZONE_LOCAL_DATANODES:-1" in script
    assert "OZONE_LOCAL_STARTUP_TIMEOUT:-600s" in script
    assert "OZONE_LOCAL_CONTAINER_SIZE:-80MB" in script
    assert "OZONE_LOCAL_TCP_TIMEOUT:-720" in script
    assert "OZONE_LOCAL_READY_TIMEOUT:-900" in script


def test_ozone_local_jvm_pid_prefers_ozone_process_over_jcmd(tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    jcmd = fake_bin / "jcmd"
    jcmd.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            if [[ "$1" == "-l" ]]; then
              cat <<'OUT'
            41 jdk.jcmd/sun.tools.jcmd.JCmd -l
            1234 org.apache.hadoop.ozone.MiniOzoneCluster
            5678 com.example.OtherJvm
            OUT
            fi
            """
        ),
        encoding="utf-8",
    )
    jcmd.chmod(0o755)

    result = subprocess.run(
        [
            "bash",
            "-lc",
            f'PATH="{fake_bin}:$PATH"; source scripts/benchmark/providers/ozone.sh; ozone_local_jvm_pid',
        ],
        check=False,
        text=True,
        capture_output=True,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "1234"


def test_ozone_local_jvm_pid_falls_back_to_first_non_jcmd_process(tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    jcmd = fake_bin / "jcmd"
    jcmd.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            if [[ "$1" == "-l" ]]; then
              cat <<'OUT'
            41 jdk.jcmd/sun.tools.jcmd.JCmd -l
            2222 org.eclipse.jetty.start.Main
            OUT
            fi
            """
        ),
        encoding="utf-8",
    )
    jcmd.chmod(0o755)

    result = subprocess.run(
        [
            "bash",
            "-lc",
            f'PATH="{fake_bin}:$PATH"; source scripts/benchmark/providers/ozone.sh; ozone_local_jvm_pid',
        ],
        check=False,
        text=True,
        capture_output=True,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "2222"


def test_ozone_jvm_pids_lists_all_non_jcmd_processes(tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    jcmd = fake_bin / "jcmd"
    jcmd.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            if [[ "$1" == "-l" ]]; then
              cat <<'OUT'
            41 jdk.jcmd/sun.tools.jcmd.JCmd -l
            1234 org.apache.hadoop.ozone.MiniOzoneCluster
            5678 org.apache.hadoop.ozone.om.OzoneManager
            9012 org.apache.hadoop.hdds.scm.server.StorageContainerManager
            OUT
            fi
            """
        ),
        encoding="utf-8",
    )
    jcmd.chmod(0o755)

    result = subprocess.run(
        [
            "bash",
            "-lc",
            f'PATH="{fake_bin}:$PATH"; source scripts/benchmark/providers/ozone.sh; ozone_jvm_pids',
        ],
        check=False,
        text=True,
        capture_output=True,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["1234", "5678", "9012"]


def test_ozone_profile_diagnostics_collects_per_profile_jfr_views() -> None:
    script = provider_script("ozone")

    assert "provider_profile_diagnostics_start()" in script
    assert "provider_profile_diagnostics_collect()" in script
    assert "for pid in \\$(ozone_jvm_pids); do" in script
    assert "JFR.start name=${recording_name}" in script
    assert "jfr view --width 160 hot-methods" in script
    assert "jfr view --width 160 allocation-by-site" in script
    assert "jfr-recordings.tgz" in script


def test_profile_diagnostics_wrap_each_warp_profile() -> None:
    runner = Path("scripts/run-benchmark-provider.sh").read_text(encoding="utf-8")
    common = Path("scripts/benchmark/common.sh").read_text(encoding="utf-8")

    assert 'generic_profile_diagnostics_start "${profile_id}"' in runner
    assert 'provider_profile_diagnostics_start "${profile_id}"' in runner
    assert 'run_benchmark_profile_command "${profile_id}"' in runner
    assert 'provider_profile_diagnostics_collect "${profile_id}"' in runner
    assert 'generic_profile_diagnostics_collect "${profile_id}"' in runner
    assert "run_benchmark_profile_command()" in common
    assert "/usr/bin/time -v -o" in common
    assert "warp-time.txt" in common


def test_workflow_exposes_targeted_ozone_jfr_profile_suite() -> None:
    workflow = Path(".github/workflows/benchmark-nightly.yml").read_text(encoding="utf-8")

    assert "- ozone-jfr" in workflow


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
