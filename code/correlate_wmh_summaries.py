#!/usr/bin/env python3
"""Correlate DeepWMH summary volumes with TrUE-Net summary volumes.

The default inputs match the RF1 project layout:

  derivatives/deepwmh/deepwmh-summary_ses-<SES>.tsv
  derivatives/truenet-evaluate/truenet-summary_ses-<SES>.tsv

No third-party Python packages are required.
"""

from __future__ import annotations

import argparse
import csv
import io
import math
import re
import sys
from pathlib import Path


MISSING = {"", "NA", "NaN", "nan", "NAN", "None", "none", "null", "NULL"}


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(
        description=(
            "Correlate DeepWMH native-space WMH volume with TrUE-Net summary "
            "volume columns."
        )
    )
    parser.add_argument(
        "--ses",
        default="02",
        help="Session label without the ses- prefix. Default: 02.",
    )
    parser.add_argument(
        "--deepwmh",
        type=Path,
        help="DeepWMH summary TSV. Defaults to derivatives/deepwmh/deepwmh-summary_ses-<SES>.tsv.",
    )
    parser.add_argument(
        "--truenet",
        type=Path,
        help="TrUE-Net summary TSV. Defaults to derivatives/truenet-evaluate/truenet-summary_ses-<SES>.tsv.",
    )
    parser.add_argument(
        "--outdir",
        type=Path,
        default=project_root / "derivatives" / "wmh-correlations",
        help="Output directory. Default: derivatives/wmh-correlations.",
    )
    parser.add_argument(
        "--deepwmh-column",
        default="mm3",
        help="DeepWMH numeric column to correlate. Default: mm3.",
    )
    parser.add_argument(
        "--truenet-columns",
        default="",
        help=(
            "Comma-separated TrUE-Net numeric columns to correlate. "
            "Default: every column ending in _mm3."
        ),
    )
    parser.add_argument(
        "--include-status",
        default="ok,exists",
        help=(
            "Comma-separated DeepWMH statuses to include. Use 'all' to ignore "
            "status. Default: ok,exists."
        ),
    )
    parser.add_argument(
        "--min-pairs",
        type=int,
        default=3,
        help="Minimum complete subject pairs required to report a correlation. Default: 3.",
    )
    parser.add_argument(
        "--prefix",
        default="",
        help="Output filename prefix. Default: deepwmh-vs-truenet_ses-<SES>.",
    )

    args = parser.parse_args()
    args.ses = normalize_session(args.ses)

    if args.deepwmh is None:
        args.deepwmh = (
            project_root
            / "derivatives"
            / "deepwmh"
            / f"deepwmh-summary_ses-{args.ses}.tsv"
        )
    if args.truenet is None:
        args.truenet = (
            project_root
            / "derivatives"
            / "truenet-evaluate"
            / f"truenet-summary_ses-{args.ses}.tsv"
        )
    if not args.prefix:
        args.prefix = f"deepwmh-vs-truenet_ses-{args.ses}"

    return args


def normalize_session(value: str) -> str:
    value = str(value).strip()
    value = re.sub(r"^ses-", "", value)
    if value.isdigit():
        return f"{int(value):02d}"
    return value


def sniff_delimiter(path: Path, sample: str) -> str:
    if path.suffix.lower() == ".tsv":
        return "\t"
    if path.suffix.lower() == ".csv":
        return ","

    first_line = sample.splitlines()[0] if sample.splitlines() else ""
    if "\t" in sample and "," not in first_line:
        return "\t"
    try:
        return csv.Sniffer().sniff(sample).delimiter
    except csv.Error:
        return "\t"


def read_table(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    if not path.exists():
        raise FileNotFoundError(path)

    text = path.read_text()
    delimiter = sniff_delimiter(path, text[:4096])
    reader = csv.DictReader(io.StringIO(text), delimiter=delimiter)
    headers = reader.fieldnames or []
    rows = [{k: clean_cell(v) for k, v in row.items()} for row in reader]

    if not headers:
        raise ValueError(f"No header found in {path}")
    return headers, rows


def clean_cell(value: object) -> str:
    if value is None:
        return ""
    return str(value).strip()


def find_subject_column(headers: list[str], table_name: str) -> str:
    for candidate in ("subject", "sub", "participant_id", "sub_id"):
        if candidate in headers:
            return candidate
    raise ValueError(
        f"Could not find a subject column in {table_name}; expected one of "
        "subject, sub, participant_id, or sub_id."
    )


def normalize_subject(value: str) -> str:
    subject = clean_cell(value)
    subject = re.sub(r"^sub-", "", subject)
    if re.fullmatch(r"\d+\.0+", subject):
        subject = subject.split(".", 1)[0]
    return subject


def parse_float(value: str) -> float | None:
    value = clean_cell(value)
    if value in MISSING:
        return None
    try:
        parsed = float(value)
    except ValueError:
        return None
    if math.isnan(parsed) or math.isinf(parsed):
        return None
    return parsed


def pearson(xs: list[float], ys: list[float]) -> float | None:
    n = len(xs)
    if n < 2:
        return None

    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    dx = [x - mean_x for x in xs]
    dy = [y - mean_y for y in ys]
    ss_x = sum(x * x for x in dx)
    ss_y = sum(y * y for y in dy)
    if ss_x == 0 or ss_y == 0:
        return None
    return sum(x * y for x, y in zip(dx, dy)) / math.sqrt(ss_x * ss_y)


def average_ranks(values: list[float]) -> list[float]:
    ordered = sorted(enumerate(values), key=lambda item: item[1])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(ordered):
        j = i + 1
        while j < len(ordered) and ordered[j][1] == ordered[i][1]:
            j += 1
        rank = (i + 1 + j) / 2.0
        for k in range(i, j):
            ranks[ordered[k][0]] = rank
        i = j
    return ranks


def spearman(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 2:
        return None
    return pearson(average_ranks(xs), average_ranks(ys))


def fmt(value: float | None) -> str:
    if value is None:
        return "NA"
    return f"{value:.6g}"


def include_status_filter(value: str) -> set[str] | None:
    statuses = {item.strip().lower() for item in value.split(",") if item.strip()}
    if "all" in statuses:
        return None
    return statuses


def load_deepwmh(
    path: Path,
    value_column: str,
    statuses: set[str] | None,
) -> tuple[list[str], dict[str, dict[str, str]]]:
    headers, rows = read_table(path)
    subject_column = find_subject_column(headers, str(path))
    if value_column not in headers:
        raise ValueError(f"DeepWMH summary is missing column: {value_column}")

    by_subject: dict[str, dict[str, str]] = {}
    for row in rows:
        status = row.get("status", "")
        if statuses is not None and status and status.lower() not in statuses:
            continue
        subject = normalize_subject(row.get(subject_column, ""))
        if not subject:
            continue
        by_subject[subject] = row
    return headers, by_subject


def choose_truenet_columns(
    headers: list[str],
    rows: list[dict[str, str]],
    subject_column: str,
    requested: str,
) -> list[str]:
    if requested.strip():
        columns = [item.strip() for item in requested.split(",") if item.strip()]
        missing = [column for column in columns if column not in headers]
        if missing:
            raise ValueError(f"TrUE-Net summary is missing requested columns: {', '.join(missing)}")
        return columns

    mm3_columns = [
        column
        for column in headers
        if column != subject_column and column.lower().endswith("_mm3")
    ]
    if mm3_columns:
        return mm3_columns

    numeric_columns = []
    for column in headers:
        if column == subject_column:
            continue
        if any(parse_float(row.get(column, "")) is not None for row in rows):
            numeric_columns.append(column)
    return numeric_columns


def load_truenet(
    path: Path,
    requested_columns: str,
) -> tuple[list[str], list[str], dict[str, dict[str, str]]]:
    headers, rows = read_table(path)
    subject_column = find_subject_column(headers, str(path))
    columns = choose_truenet_columns(headers, rows, subject_column, requested_columns)

    by_subject: dict[str, dict[str, str]] = {}
    for row in rows:
        subject = normalize_subject(row.get(subject_column, ""))
        if subject:
            by_subject[subject] = row
    return headers, columns, by_subject


def sort_subjects(subjects: set[str]) -> list[str]:
    def key(subject: str) -> tuple[int, object]:
        if subject.isdigit():
            return (0, int(subject))
        return (1, subject)

    return sorted(subjects, key=key)


def transformed_pairs(
    pairs: list[tuple[float, float]],
    transform: str,
) -> tuple[list[float], list[float]]:
    if transform == "raw":
        return [x for x, _ in pairs], [y for _, y in pairs]
    if transform == "log10p1":
        usable = [(x, y) for x, y in pairs if x >= -1 and y >= -1]
        return [math.log10(x + 1) for x, _ in usable], [math.log10(y + 1) for _, y in usable]
    raise ValueError(transform)


def main() -> int:
    args = parse_args()
    statuses = include_status_filter(args.include_status)

    try:
        deep_headers, deep_by_subject = load_deepwmh(
            args.deepwmh,
            args.deepwmh_column,
            statuses,
        )
        truenet_headers, truenet_columns, truenet_by_subject = load_truenet(
            args.truenet,
            args.truenet_columns,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    matched_subjects = sort_subjects(set(deep_by_subject) & set(truenet_by_subject))
    if not matched_subjects:
        print("[ERROR] No overlapping subjects between DeepWMH and TrUE-Net summaries.", file=sys.stderr)
        return 1

    args.outdir.mkdir(parents=True, exist_ok=True)
    merged_tsv = args.outdir / f"{args.prefix}_merged.tsv"
    corr_tsv = args.outdir / f"{args.prefix}_correlations.tsv"

    with merged_tsv.open("w", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "subject",
                "session",
                "deepwmh_status",
                f"deepwmh_{args.deepwmh_column}",
                *truenet_columns,
            ]
        )
        for subject in matched_subjects:
            deep_row = deep_by_subject[subject]
            truenet_row = truenet_by_subject[subject]
            writer.writerow(
                [
                    f"sub-{subject}",
                    deep_row.get("session", f"ses-{args.ses}"),
                    deep_row.get("status", ""),
                    deep_row.get(args.deepwmh_column, "NA"),
                    *[truenet_row.get(column, "NA") for column in truenet_columns],
                ]
            )

    correlation_rows = []
    deep_values_by_subject = {
        subject: parse_float(deep_by_subject[subject].get(args.deepwmh_column, ""))
        for subject in matched_subjects
    }

    for column in truenet_columns:
        raw_pairs = []
        for subject in matched_subjects:
            deep_value = deep_values_by_subject[subject]
            other_value = parse_float(truenet_by_subject[subject].get(column, ""))
            if deep_value is not None and other_value is not None:
                raw_pairs.append((deep_value, other_value))

        for transform in ("raw", "log10p1"):
            xs, ys = transformed_pairs(raw_pairs, transform)
            n = len(xs)
            if n < args.min_pairs:
                r = None
                rho = None
            else:
                r = pearson(xs, ys)
                rho = spearman(xs, ys)
            correlation_rows.append(
                [
                    "DeepWMH",
                    args.deepwmh_column,
                    "TrUE-Net",
                    column,
                    transform,
                    n,
                    fmt(r),
                    fmt(rho),
                ]
            )

    with corr_tsv.open("w", newline="") as f:
        writer = csv.writer(f, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
                "x_program",
                "x_column",
                "y_program",
                "y_column",
                "transform",
                "n",
                "pearson_r",
                "spearman_rho",
            ]
        )
        writer.writerows(correlation_rows)

    print(f"DeepWMH summary : {args.deepwmh}")
    print(f"TrUE-Net summary: {args.truenet}")
    print(f"Matched subjects: {len(matched_subjects)}")
    print(f"Merged TSV      : {merged_tsv}")
    print(f"Correlations TSV: {corr_tsv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
