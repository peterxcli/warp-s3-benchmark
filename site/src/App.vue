<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";

import { createDuckDbParquetQueryClient } from "./lib/duckdbParquetQueryClient";
import { fetchBenchmarkIndex, fetchBenchmarkRun, resolveBenchmarkDataPath } from "./lib/parquetReport";
import {
  formatDate,
  formatOps,
  formatThroughput,
  profileLabel,
  providerColor,
  providerResultMeta,
  providerResultStatusLabel,
  providerResultsForProfile,
  profilesForWorkload,
  timeseriesForProfile,
  workloadsFromResults,
} from "./lib/report";
import type {
  BenchmarkIndex,
  BenchmarkMetricKey,
  BenchmarkProfile,
  BenchmarkResult,
  BenchmarkRun,
  BenchmarkRunSummary,
  BenchmarkTimeseriesPoint,
} from "./lib/types";
import type { ParquetCacheMode } from "./lib/duckdbParquetQueryClient";

const loading = ref(true);
const errorMessage = ref("");
const index = ref<BenchmarkIndex | null>(null);
const latestRun = ref<BenchmarkRun | null>(null);
const selectedWorkload = ref("");
const selectedProfileId = ref("");
const metric = ref<BenchmarkMetricKey>("throughput_mib_per_sec");

function normalizedDataBaseUrl(value: string): string {
  const text = value.trim() || "./data/";
  return text.endsWith("/") ? text : `${text}/`;
}

function normalizedCacheMode(value: string): ParquetCacheMode {
  return value === "auto" || value === "on_disk" || value === "in_mem" ? value : "direct";
}

const searchParams = new URLSearchParams(window.location.search);
const dataBaseUrl = normalizedDataBaseUrl(
  searchParams.get("dataBaseUrl") || import.meta.env.VITE_REPORT_DATA_BASE_URL || "./data/",
);
const cacheMode = normalizedCacheMode(
  searchParams.get("cacheFs") || searchParams.get("duckdbCache") || import.meta.env.VITE_DUCKDB_CACHE_MODE || "direct",
);
const parquetClient = createDuckDbParquetQueryClient({ cacheMode });

const latestSummary = computed<BenchmarkRunSummary | null>(() => index.value?.runs[0] || null);
const archiveRuns = computed<BenchmarkRunSummary[]>(() => index.value?.runs.slice(1) || []);
const workloads = computed<string[]>(() => workloadsFromResults(latestRun.value?.results || []));
const workloadProfiles = computed<BenchmarkProfile[]>(() =>
  latestRun.value ? profilesForWorkload(latestRun.value.profiles, selectedWorkload.value) : [],
);
const selectedProfile = computed<BenchmarkProfile | null>(
  () => workloadProfiles.value.find((profile) => profile.profile_id === selectedProfileId.value) || workloadProfiles.value[0] || null,
);
const providerRows = computed<BenchmarkResult[]>(() =>
  selectedProfile.value
    ? providerResultsForProfile(latestRun.value?.results || [], selectedProfile.value.profile_id, metric.value)
    : [],
);
const chartProviders = computed<string[]>(() =>
  latestRun.value?.providers.map((provider) => provider.provider) || [],
);
const workloadChartRows = computed(() => {
  if (!latestRun.value) return [];
  return workloadProfiles.value.map((profile) => {
    const results = chartProviders.value.map((provider) => {
      const result = latestRun.value?.results.find(
        (entry) => entry.profile_id === profile.profile_id && entry.provider === provider,
      );
      const value = result?.status === "completed" ? Number(result[metric.value] || 0) : 0;
      return { provider, result, value };
    });
    return { profile, results };
  });
});
const workloadChartMax = computed(() =>
  Math.max(...workloadChartRows.value.flatMap((row) => row.results.map((result) => result.value)), 0),
);
const workloadChartWidth = computed(() => Math.max(900, workloadChartRows.value.length * 92));
const workloadChartHeight = 360;
const workloadChartPlotTop = 24;
const workloadChartPlotBottom = 82;
const workloadChartPlotHeight = workloadChartHeight - workloadChartPlotTop - workloadChartPlotBottom;
const selectedArtifacts = computed(() =>
  selectedProfile.value
    ? (latestRun.value?.artifacts || []).filter((artifact) => artifact.profile_id === selectedProfile.value?.profile_id)
    : [],
);
const selectedCommands = computed(() =>
  selectedProfile.value
    ? (latestRun.value?.commands || []).filter((command) => command.profile_id === selectedProfile.value?.profile_id)
    : [],
);
const runnerFields = computed(() => Object.entries(latestRun.value?.runner || {}).slice(0, 8));
const warpCommit = computed(() => String(latestRun.value?.warp?.commit || latestSummary.value?.warp_commit || ""));

watch(workloads, (next) => {
  if (!selectedWorkload.value || !next.includes(selectedWorkload.value)) {
    selectedWorkload.value = next[0] || "";
  }
});

watch(workloadProfiles, (next) => {
  if (!selectedProfileId.value || !next.some((profile) => profile.profile_id === selectedProfileId.value)) {
    selectedProfileId.value = next[0]?.profile_id || "";
  }
});

function metricValue(result: BenchmarkResult): number | null | undefined {
  return result[metric.value];
}

function formatMetric(result: BenchmarkResult): string {
  if (metric.value === "throughput_mib_per_sec") return formatThroughput(result.throughput_mib_per_sec);
  if (metric.value === "ops_per_sec") return formatOps(result.ops_per_sec);
  return formatOps(result.objects_per_sec);
}

function formatMetricNumber(value: number): string {
  if (metric.value === "throughput_mib_per_sec") return formatThroughput(value);
  return formatOps(value);
}

function resultBarWidth(result: BenchmarkResult): string {
  const max = Math.max(...providerRows.value.map((row) => Number(metricValue(row) || 0)), 0);
  const value = Number(metricValue(result) || 0);
  if (!max || !value) return "0%";
  return `${Math.max(4, Math.round((value / max) * 100))}%`;
}

function chartBarHeight(value: number): number {
  if (!workloadChartMax.value || !value) return 0;
  return Math.max(2, (value / workloadChartMax.value) * workloadChartPlotHeight);
}

function chartBarY(value: number): number {
  return workloadChartPlotTop + workloadChartPlotHeight - chartBarHeight(value);
}

function chartBarX(groupIndex: number, providerIndex: number): number {
  const groupWidth = workloadChartWidth.value / Math.max(workloadChartRows.value.length, 1);
  const innerWidth = Math.min(68, groupWidth - 18);
  const barWidth = chartBarWidth();
  return groupIndex * groupWidth + (groupWidth - innerWidth) / 2 + providerIndex * barWidth;
}

function chartBarWidth(): number {
  const providerCount = Math.max(chartProviders.value.length, 1);
  const groupWidth = workloadChartWidth.value / Math.max(workloadChartRows.value.length, 1);
  const innerWidth = Math.min(68, groupWidth - 18);
  return innerWidth / providerCount;
}

function chartProfileX(index: number): number {
  const groupWidth = workloadChartWidth.value / Math.max(workloadChartRows.value.length, 1);
  return index * groupWidth + groupWidth / 2;
}

function providerLabel(provider: string): string {
  return latestRun.value?.providers.find((entry) => entry.provider === provider)?.label || provider;
}

function providerTimeseries(provider: string): BenchmarkTimeseriesPoint[] {
  if (!selectedProfile.value || !latestRun.value) return [];
  return timeseriesForProfile(latestRun.value.timeseries, selectedProfile.value.profile_id, provider);
}

function sparklinePoints(points: BenchmarkTimeseriesPoint[]): string {
  if (!points.length) return "";
  const values = points.map((point) => Number(point.mb_per_sec ?? point.ops_per_sec ?? 0));
  const max = Math.max(...values, 1);
  const width = 260;
  const height = 72;
  if (values.length === 1) {
    return `0,${height - (values[0] / max) * height} ${width},${height - (values[0] / max) * height}`;
  }
  return values
    .map((value, index) => {
      const x = (index / (values.length - 1)) * width;
      const y = height - (value / max) * height;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
}

function artifactHref(path: string): string {
  return resolveBenchmarkDataPath(dataBaseUrl, path);
}

async function loadReport(): Promise<void> {
  loading.value = true;
  errorMessage.value = "";
  try {
    const loadedIndex = await fetchBenchmarkIndex(parquetClient, dataBaseUrl);
    index.value = loadedIndex;
    if (loadedIndex.runs[0]) {
      latestRun.value = await fetchBenchmarkRun(parquetClient, dataBaseUrl, loadedIndex.runs[0]);
    }
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : String(error);
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  void loadReport();
});

onBeforeUnmount(() => {
  void parquetClient.close();
});
</script>

<template>
  <main class="shell">
    <nav class="topbar" aria-label="Report navigation">
      <a href="#latest">Latest</a>
      <a href="#timeseries">Time Series</a>
      <a href="#details">Run Details</a>
      <a href="#archive">Archive</a>
      <a class="repo-link" href="https://github.com/minio/warp">Warp</a>
    </nav>

    <section class="hero" id="latest">
      <div>
        <p class="eyebrow">S3 performance nightly</p>
        <h1>Warp Benchmark Report</h1>
        <p class="hero-copy">
          Latest-vs-latest Docker benchmark runs for RustFS, SeaweedFS, Ceph, and Apache Ozone using a pinned
          MinIO Warp submodule and Parquet-backed static data.
        </p>
      </div>
      <div class="run-summary">
        <span class="status" :class="latestRun?.status || latestSummary?.status || 'unknown'">
          {{ latestRun?.status || latestSummary?.status || "loading" }}
        </span>
        <strong>{{ latestSummary ? formatDate(latestSummary.finished_at) : "No run loaded" }}</strong>
        <span>{{ latestSummary?.provider_count || 0 }} providers</span>
        <span>{{ latestSummary?.profile_count || 0 }} profiles</span>
        <a v-if="latestSummary?.workflow_run_url" :href="latestSummary.workflow_run_url">Workflow run</a>
      </div>
    </section>

    <section v-if="loading" class="panel">Loading benchmark Parquet data...</section>
    <section v-else-if="errorMessage" class="panel error">{{ errorMessage }}</section>
    <section v-else-if="!latestRun" class="panel">No benchmark runs have been published yet.</section>

    <template v-else>
      <section class="panel controls">
        <div class="tabs" role="tablist" aria-label="Workloads">
          <button
            v-for="workload in workloads"
            :key="workload"
            type="button"
            :class="{ active: workload === selectedWorkload }"
            @click="selectedWorkload = workload"
          >
            {{ workload }}
          </button>
        </div>

        <label>
          Profile
          <select v-model="selectedProfileId">
            <option v-for="profile in workloadProfiles" :key="profile.profile_id" :value="profile.profile_id">
              {{ profileLabel(profile) }}
            </option>
          </select>
        </label>

        <label>
          Metric
          <select v-model="metric">
            <option value="throughput_mib_per_sec">Throughput</option>
            <option value="ops_per_sec">Ops/sec</option>
            <option value="objects_per_sec">Objects/sec</option>
          </select>
        </label>
      </section>

      <section class="panel comparison">
        <header>
          <h2>Centralized Comparison</h2>
          <p>{{ selectedWorkload }} · {{ workloadProfiles.length }} profiles · {{ metric === "throughput_mib_per_sec" ? "Throughput" : metric === "ops_per_sec" ? "Ops/sec" : "Objects/sec" }}</p>
        </header>

        <div class="chart-legend" aria-label="Provider legend">
          <span v-for="provider in chartProviders" :key="provider">
            <i :style="{ background: providerColor(provider) }"></i>
            {{ providerLabel(provider) }}
          </span>
        </div>

        <div class="comparison-chart">
          <svg
            :viewBox="`0 0 ${workloadChartWidth} ${workloadChartHeight}`"
            role="img"
            :aria-label="`${selectedWorkload} provider comparison chart`"
            preserveAspectRatio="none"
          >
            <line
              :x1="0"
              :x2="workloadChartWidth"
              :y1="workloadChartPlotTop + workloadChartPlotHeight"
              :y2="workloadChartPlotTop + workloadChartPlotHeight"
              class="chart-axis"
            />
            <g v-for="(row, rowIndex) in workloadChartRows" :key="row.profile.profile_id">
              <rect
                v-for="(entry, providerIndex) in row.results"
                :key="`${row.profile.profile_id}-${entry.provider}`"
                class="chart-bar"
                :class="{ failed: entry.result?.status !== 'completed' }"
                :x="chartBarX(rowIndex, providerIndex) + 1"
                :y="entry.value ? chartBarY(entry.value) : workloadChartPlotTop + workloadChartPlotHeight - 3"
                :width="Math.max(2, chartBarWidth() - 2)"
                :height="entry.value ? chartBarHeight(entry.value) : 3"
                :fill="entry.value ? providerColor(entry.provider) : '#c9d4e0'"
              >
                <title>
                  {{ providerLabel(entry.provider) }} · {{ profileLabel(row.profile) }} ·
                  {{ entry.result?.status === "completed" ? formatMetricNumber(entry.value) : entry.result?.status || "missing" }}
                </title>
              </rect>
              <text
                class="chart-label"
                :x="chartProfileX(rowIndex)"
                :y="workloadChartHeight - 42"
                text-anchor="end"
                transform-origin="center"
                :transform="`rotate(-35 ${chartProfileX(rowIndex)} ${workloadChartHeight - 42})`"
              >
                {{ profileLabel(row.profile) }}
              </text>
            </g>
            <text class="chart-max" x="0" y="16">{{ formatMetricNumber(workloadChartMax) }}</text>
          </svg>
        </div>
      </section>

      <section class="panel comparison">
        <header>
          <h2>Provider Comparison</h2>
          <p>{{ selectedProfile ? profileLabel(selectedProfile) : "No profile selected" }}</p>
        </header>

        <div class="result-grid">
          <article v-for="result in providerRows" :key="`${result.provider}-${result.operation}`" class="result-row">
            <div>
              <strong>{{ providerLabel(result.provider) }}</strong>
              <span>{{ providerResultStatusLabel(result, latestRun.providers) }}</span>
            </div>
            <div class="metric-value">{{ formatMetric(result) }}</div>
            <div class="bar-track">
              <div class="bar-fill" :style="{ width: resultBarWidth(result), background: providerColor(result.provider) }"></div>
            </div>
            <div class="row-meta">
              <span v-for="item in providerResultMeta(result, latestRun.providers)" :key="item">{{ item }}</span>
            </div>
          </article>
        </div>
      </section>

      <section class="panel" id="timeseries">
        <header>
          <h2>Time Series</h2>
          <p>Per-provider segments from Warp analyze CSV output.</p>
        </header>
        <div class="sparklines">
          <article v-for="result in providerRows" :key="`spark-${result.provider}`">
            <strong>{{ providerLabel(result.provider) }}</strong>
            <svg viewBox="0 0 260 72" role="img" :aria-label="`${providerLabel(result.provider)} time series`">
              <polyline
                fill="none"
                stroke-width="3"
                stroke-linejoin="round"
                stroke-linecap="round"
                :stroke="providerColor(result.provider)"
                :points="sparklinePoints(providerTimeseries(result.provider))"
              />
            </svg>
          </article>
        </div>
      </section>

      <section class="panel" id="details">
        <header>
          <h2>Run Details</h2>
          <p>{{ latestRun.run_id }}</p>
        </header>
        <div class="detail-grid">
          <div>
            <h3>Warp</h3>
            <dl>
              <div><dt>Commit</dt><dd>{{ warpCommit || "unknown" }}</dd></div>
              <div><dt>Version</dt><dd>{{ latestRun.warp.version || "unknown" }}</dd></div>
            </dl>
          </div>
          <div>
            <h3>Runner</h3>
            <dl>
              <div v-for="[key, value] in runnerFields" :key="key"><dt>{{ key }}</dt><dd>{{ value }}</dd></div>
            </dl>
          </div>
        </div>

        <h3>Provider Images</h3>
        <table>
          <thead>
            <tr><th>Provider</th><th>Image</th><th>Digest</th><th>Status</th></tr>
          </thead>
          <tbody>
            <tr v-for="provider in latestRun.providers" :key="provider.provider">
              <td>{{ provider.label }}</td>
              <td>{{ provider.image }}</td>
              <td class="digest">{{ provider.image_digest }}</td>
              <td>{{ provider.adapter_status }}</td>
            </tr>
          </tbody>
        </table>

        <h3>Commands</h3>
        <div class="command-list">
          <pre v-for="command in selectedCommands" :key="`${command.provider}-${command.profile_id}`"><code>{{ command.command.join(" ") }}</code></pre>
        </div>

        <h3>Artifacts</h3>
        <div class="artifact-list">
          <a v-for="artifact in selectedArtifacts" :key="`${artifact.provider}-${artifact.kind}-${artifact.path}`" :href="artifactHref(artifact.path)">
            {{ providerLabel(artifact.provider) }} · {{ artifact.kind }}
          </a>
        </div>
      </section>

      <section class="panel" id="archive">
        <header>
          <h2>Archive</h2>
          <p>Previous runs are kept for inspection and artifact access.</p>
        </header>
        <div class="archive-list">
          <a v-for="run in archiveRuns" :key="run.id" :href="run.workflow_run_url || '#'" class="archive-row">
            <strong>{{ formatDate(run.finished_at) }}</strong>
            <span>{{ run.status }}</span>
            <span>{{ run.provider_count }} providers</span>
          </a>
        </div>
      </section>
    </template>
  </main>
</template>
