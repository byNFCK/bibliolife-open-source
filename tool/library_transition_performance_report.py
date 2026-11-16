"""Parse one A065 Library profile benchmark logcat capture.

The parser intentionally consumes only lines emitted during the benchmark
markers. It does not infer percentiles that the Flutter diagnostic does not
provide.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


FRAME_RE = re.compile(r"LIBRARY_FRAME_REPORT\s+(.*)")
MARKER_RE = re.compile(r"LIBRARY_BENCHMARK\s+(.*)")
COVER_RE = re.compile(r"LIBRARY_COVER_DECODE_FAILURE\s+(.*)")
FIELD_RE = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")


def fields(payload: str) -> dict[str, str]:
    return {key: value for key, value in FIELD_RE.findall(payload)}


def number(value: str | None, default: float = 0.0) -> float:
    try:
        return float(value) if value is not None else default
    except ValueError:
        return default


def integer(value: str | None, default: int = 0) -> int:
    try:
        return int(value) if value is not None else default
    except ValueError:
        return default


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16", errors="replace")
    return raw.decode("utf-8", errors="replace")


def parse_frame(payload: str) -> dict[str, object]:
    data = fields(payload)
    return {
        "transition": data.get("transition", "unknown"),
        "frames": integer(data.get("frames")),
        "over_16_67_ms": integer(data.get("over_16_67ms")),
        "over_33_3_ms": integer(data.get("over_33_3ms")),
        "worst_build_ms": number(data.get("worst_build_ms")),
        "worst_raster_ms": number(data.get("worst_raster_ms")),
        "average_build_ms": number(data.get("average_build_ms")),
        "average_raster_ms": number(data.get("average_raster_ms")),
        "classification": data.get("classification", "unknown"),
    }


def add_error(target: dict[str, int], line: str) -> None:
    if "FlutterImageDecoderImplDefault" in line and "Failed to decode image" in line:
        target["flutter_image_decoder_failed"] += 1
    if "ImageDecoder$DecodeException" in line:
        target["image_decoder_exception"] += 1
    if "Could not call release buffer callback, buffer not found" in line:
        target["surface_composer_release_buffer"] += 1
    if "HWUI" in line:
        target["hwui"] += 1
    if (
        "FlutterError" in line
        or "EXCEPTION CAUGHT BY FLUTTER" in line
        or "Unhandled Exception" in line
        or "Another exception was thrown" in line
    ):
        target["flutter_errors"] += 1


def summarize(samples: list[dict[str, object]]) -> dict[str, object]:
    frames = sum(int(sample["frames"]) for sample in samples)
    over_16 = sum(int(sample["over_16_67_ms"]) for sample in samples)
    over_33 = sum(int(sample["over_33_3_ms"]) for sample in samples)
    worst_build = max((float(sample["worst_build_ms"]) for sample in samples), default=0.0)
    worst_raster = max((float(sample["worst_raster_ms"]) for sample in samples), default=0.0)
    build_total = sum(
        float(sample["average_build_ms"]) * int(sample["frames"])
        for sample in samples
    )
    raster_total = sum(
        float(sample["average_raster_ms"]) * int(sample["frames"])
        for sample in samples
    )
    average_build = build_total / frames if frames else 0.0
    average_raster = raster_total / frames if frames else 0.0
    build_bound = worst_build > 16.667
    raster_bound = worst_raster > 16.667
    if build_bound and raster_bound:
        classification = "mixed"
    elif build_bound:
        classification = "build-bound"
    elif raster_bound:
        classification = "raster-bound"
    else:
        classification = "healthy-by-16.67ms-counter"
    return {
        "samples": len(samples),
        "frames": frames,
        "over_16_67_ms": over_16,
        "over_16_67_percent": (100.0 * over_16 / frames) if frames else 0.0,
        "over_33_3_ms": over_33,
        "over_33_3_percent": (100.0 * over_33 / frames) if frames else 0.0,
        "worst_build_ms": worst_build,
        "average_build_ms": average_build,
        "worst_raster_ms": worst_raster,
        "average_raster_ms": average_raster,
        "classification": classification,
        "sample_classifications": dict(
            Counter(str(sample["classification"]) for sample in samples)
        ),
    }


def parse(log_path: Path, refresh_path: Path | None) -> dict[str, object]:
    lines = read_text(log_path).splitlines()
    measured: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    phase = "outside"
    benchmark_started = False
    errors = Counter()
    transition_errors: dict[int, Counter[str]] = defaultdict(Counter)
    cover_failures: dict[tuple[str, str, str, str], dict[str, str]] = {}
    retention: dict[str, str] | None = None
    data_verified: dict[str, str] | None = None
    warmup_result: str | None = None

    for line in lines:
        marker_match = MARKER_RE.search(line)
        if marker_match:
            marker = fields(marker_match.group(1))
            marker_phase = marker.get("phase", "")
            if marker_phase == "benchmark_start":
                benchmark_started = True
                phase = "benchmark"
            elif marker_phase.endswith("_start"):
                phase = marker_phase.removesuffix("_start")
            elif marker_phase.endswith("_end"):
                phase = marker_phase.removesuffix("_end")
            if marker_phase == "warmup_end":
                warmup_result = marker.get("result")
            if marker_phase == "data_verified":
                data_verified = marker
            if marker_phase == "retention_check":
                retention = marker
            if marker_phase == "transition_start" and marker.get("measured") == "true":
                current = {
                    "input": marker.get("input", "unknown"),
                    "from": marker.get("from", "unknown"),
                    "to": marker.get("to", "unknown"),
                    "scope": marker.get("scope", "unknown"),
                    "sample": integer(marker.get("sample")),
                    "frames": [],
                    "errors": Counter(),
                }
            elif marker_phase == "transition_end" and current is not None:
                current["errors"] = dict(current["errors"])
                measured.append(current)
                current = None

        if not benchmark_started:
            continue

        frame_match = FRAME_RE.search(line)
        if frame_match and current is not None:
            current["frames"].append(parse_frame(frame_match.group(1)))

        cover_match = COVER_RE.search(line)
        if cover_match:
            data = fields(cover_match.group(1))
            key = (
                data.get("sourceType", "unknown"),
                data.get("sourceId", "unknown"),
                data.get("path", data.get("uri", "unknown")),
                data.get("profile", "unknown"),
            )
            cover_failures[key] = data

        if (
            "FlutterImageDecoderImplDefault" in line
            or "ImageDecoder$DecodeException" in line
            or "Could not call release buffer callback, buffer not found" in line
            or "HWUI" in line
            or "FlutterError" in line
            or "EXCEPTION CAUGHT BY FLUTTER" in line
            or "Unhandled Exception" in line
            or "Another exception was thrown" in line
        ):
            add_error(errors, line)
            if current is not None:
                add_error(current["errors"], line)

    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for sample in measured:
        key = f"{sample['input']}:{sample['from']}_to_{sample['to']}"
        reports = sample["frames"]
        if reports:
            sample["frame_report"] = reports[-1]
            grouped[key].append(reports[-1])
        else:
            sample["frame_report"] = None
            grouped[key].append(
                parse_frame(
                    "transition=missing frames=0 over_16_67ms=0 over_33_3ms=0 "
                    "worst_build_ms=0 worst_raster_ms=0 average_build_ms=0 "
                    "average_raster_ms=0 classification=missing"
                )
            )
        sample["errors"] = dict(sample["errors"])

    aggregates = {key: summarize(value) for key, value in sorted(grouped.items())}
    ranked = sorted(
        aggregates.items(),
        key=lambda item: (
            -float(item[1]["over_16_67_percent"]),
            -float(item[1]["worst_raster_ms"]),
            -float(item[1]["worst_build_ms"]),
        ),
    )
    refresh = None
    if refresh_path and refresh_path.exists():
        refresh_text = read_text(refresh_path)
        match = re.search(r"renderFrameRate\s*([0-9.]+)", refresh_text)
        if match is None:
            match = re.search(r"renderFrameRate\s*\r?\n\s*([0-9.]+)", refresh_text)
        if match:
            refresh = float(match.group(1))
        if refresh is None:
            match = re.search(r"peakRefreshRate=([0-9.]+)", refresh_text)
            if match:
                refresh = float(match.group(1))

    return {
        "log_path": str(log_path),
        "refresh_rate_hz": refresh,
        "theoretical_frame_budget_ms": 1000.0 / refresh if refresh else None,
        "warmup_result": warmup_result,
        "data_verified": data_verified,
        "retention": retention,
        "measured_transition_count": len(measured),
        "measured_transitions": measured,
        "aggregates": aggregates,
        "worst_transition": ranked[0][0] if ranked else None,
        "best_transition": ranked[-1][0] if ranked else None,
        "android_errors": dict(errors),
        "cover_failures": list(cover_failures.values()),
    }


def markdown(report: dict[str, object]) -> str:
    lines = [
        "# BiblioLife Library transition performance report",
        "",
        f"- Log: `{report['log_path']}`",
        f"- Refresh rate: `{report['refresh_rate_hz']} Hz`",
        f"- Frame budget: `{report['theoretical_frame_budget_ms']} ms`",
        f"- Measured transitions: `{report['measured_transition_count']}`",
        f"- Warm-up: `{report['warmup_result']}`",
        f"- Worst: `{report['worst_transition']}`",
        f"- Best: `{report['best_transition']}`",
        "",
        "| Transition | Samples | Frames | >16.67 ms | >33.3 ms | Worst build | Worst raster | Class |",
        "|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for key, value in report["aggregates"].items():
        lines.append(
            f"| {key} | {value['samples']} | {value['frames']} | "
            f"{value['over_16_67_ms']} ({value['over_16_67_percent']:.2f}%) | "
            f"{value['over_33_3_ms']} ({value['over_33_3_percent']:.2f}%) | "
            f"{value['worst_build_ms']:.2f} ms | {value['worst_raster_ms']:.2f} ms | "
            f"{value['classification']} |"
        )
    lines.extend(
        [
            "",
            "## Android/system counts",
            "",
            "```json",
            json.dumps(report["android_errors"], indent=2, sort_keys=True),
            "```",
            "",
            "## Cover failures",
            "",
            "```json",
            json.dumps(report["cover_failures"], indent=2, sort_keys=True),
            "```",
            "",
            "## Retention",
            "",
            "```json",
            json.dumps(report["retention"], indent=2, sort_keys=True),
            "```",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--refresh", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    report = parse(args.log, args.refresh)
    if args.json:
        args.json.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(markdown(report), encoding="utf-8")
    if not args.json and not args.markdown:
        print(markdown(report))


if __name__ == "__main__":
    main()
