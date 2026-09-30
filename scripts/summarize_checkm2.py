"""Summarize LorBin-paper quality thresholds from a CheckM2 quality_report.tsv.

Usage: python summarize_checkm2.py PATH_TO_QUALITY_REPORT.tsv
This reads an existing report; it does not run or install CheckM2.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def summarize(path: Path) -> tuple[int, int, int, int]:
    total = high = medium_condition = medium_only = 0
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {"Completeness", "Contamination"}
        missing = required - set(reader.fieldnames or ())
        if missing:
            raise ValueError(f"missing CheckM2 columns: {', '.join(sorted(missing))}")
        for line_number, row in enumerate(reader, start=2):
            try:
                completeness = float(row["Completeness"])
                contamination = float(row["Contamination"])
            except (TypeError, ValueError) as exc:
                raise ValueError(f"non-numeric quality value on line {line_number}") from exc
            if not (math.isfinite(completeness) and math.isfinite(contamination)):
                raise ValueError(f"non-finite quality value on line {line_number}")
            is_high = completeness >= 90 and contamination <= 5
            is_medium_condition = completeness >= 50 and contamination < 10
            total += 1
            high += is_high
            medium_condition += is_medium_condition
            medium_only += is_medium_condition and not is_high
    return total, high, medium_condition, medium_only


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("quality_report", type=Path)
    args = parser.parse_args()
    total, high, medium_condition, medium_only = summarize(args.quality_report)
    print(f"CheckM2 rows: {total}")
    print(f"hBin (completeness >=90, contamination <=5): {high}")
    print(f"mBin condition (completeness >=50, contamination <10): {medium_condition}")
    print(f"mBin excluding hBin (mutually exclusive): {medium_only}")
    print("Keep the raw quality_report.tsv and CheckM2/database versions with these counts.")


if __name__ == "__main__":
    main()
