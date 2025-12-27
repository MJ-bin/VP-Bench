#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import argparse
import traceback

try:
    import pandas as pd
except Exception:
    print("pandas is required. Please install it: pip install pandas")
    sys.exit(1)

# Helper: inline vulnerable line extractor
def calculate_vulnerable_lines(vul_func_with_fix: str) -> tuple[str, list[str], list[int]]:
    lines = vul_func_with_fix.split('\n') if isinstance(vul_func_with_fix, str) else []
    vulnerable_lines: list[str] = []
    vulnerable_lines_index: list[int] = []
    processed_func: list[str] = []
    is_flaw_line = False
    is_fix_line = False
    for index, line in enumerate(lines):
        if is_fix_line:
            is_fix_line = False
            continue
        if is_flaw_line:
            vulnerable_lines_index.append(len(processed_func))
            vulnerable_lines.append(line)
            is_flaw_line = False
        if line.startswith("//flaw_line_below:"):
            is_flaw_line = True
        elif line.startswith('//fix_flaw_line_below:'):
            is_fix_line = True
        elif not is_fix_line:
            processed_func.append(line)
    return '\n'.join(processed_func), vulnerable_lines, vulnerable_lines_index


def main():
    parser = argparse.ArgumentParser(description="Add processed_func and target columns to VP-Bench CSV.")
    default_input = os.path.join(os.path.dirname(__file__), "../DSGen/output/jasper/VP-Bench_jasper_files_changed_with_vulfunc.csv")
    default_output = os.path.join(os.path.dirname(__file__), "../DSGen/output/jasper/VP-Bench_jasper_files_changed_with_targets.csv")
    parser.add_argument(
        "--input-csv",
        default=default_input,
        help=f"Path to input CSV (default: {default_input})",
    )
    parser.add_argument(
        "--output-csv",
        default=default_output,
        help=f"Path to output CSV (default: {default_output})",
    )
    args = parser.parse_args()

    # Load CSV
    try:
        df = pd.read_csv(args.input_csv)
    except Exception as e:
        print(f"Failed to read input CSV {args.input_csv}: {e}")
        sys.exit(1)

    # Ensure columns exist
    if "vul_func_with_fix" not in df.columns:
        print("Input CSV is missing 'vul_func_with_fix' column.")
        sys.exit(2)
    if "vul" not in df.columns:
        df["vul"] = 0

    processed_funcs = []
    flaw_lines = []
    flaw_line_indexes = []

    for idx, row in df.iterrows():
        try:
            func_code = row.get("vul_func_with_fix", "")
            # Support rows without vulnerable function (vul==0)
            if not isinstance(func_code, str):
                func_code = ""
            processed_func, vulnerable_lines, vulnerable_lines_index = calculate_vulnerable_lines(func_code)
            processed_funcs.append(processed_func)
            # Store vulnerable lines and their indices as JSON strings for CSV safety
            flaw_lines.append(json.dumps(vulnerable_lines, ensure_ascii=False))
            flaw_line_indexes.append(json.dumps(vulnerable_lines_index, ensure_ascii=False))
        except Exception as e:
            traceback.print_exc(file=sys.stdout)
            print(f"Row {idx} processing failed: {e}")
            processed_funcs.append("")
            flaw_lines.append("[]")
            flaw_line_indexes.append("[]")

    df["processed_func"] = processed_funcs
    df["flaw_line"] = flaw_lines
    df["flaw_line_index"] = flaw_line_indexes

    # Add unique_id (row index) and commit_id (derived from codeLink)
    df.reset_index(drop=True, inplace=True)
    df["unique_id"] = df.index.astype(str)
    try:
        df["commit_id"] = df["codeLink"].astype(str).str.rsplit('/', n=1).str[-1]
        # Place commit_id immediately after codeLink
        cols = df.columns.tolist()
        if "codeLink" in cols and "commit_id" in cols:
            cols.remove("commit_id")
            insert_pos = cols.index("codeLink") + 1
            cols.insert(insert_pos, "commit_id")
            df = df[cols]
        # Place unique_id as the first column if desired
        if "unique_id" in cols:
            cols.remove("unique_id")
            cols.insert(0, "unique_id")
            df = df[cols]
    except Exception:
        # If codeLink missing or malformed, keep commit_id as-is at the end
        pass

    # Write output
    try:
        out_dir = os.path.dirname(args.output_csv)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        # Restrict output to requested columns only
        desired_cols = [
            "unique_id",
            "project",
            "commit_id",
            "flaw_line_index",
            "processed_func",
        ]
        for col in desired_cols:
            if col not in df.columns:
                # Create missing columns with empty values to ensure consistent output schema
                df[col] = ""

        # Subset and order columns
        df = df[desired_cols]

        # flaw_line_index 컬럼을 쉼표로만 구분된 값으로 변환 (대괄호, 공백 제거)
        def clean_list_str(val):
            if isinstance(val, str) and val.startswith("[") and val.endswith("]"):
                return val[1:-1].replace(" ", "")
            return val
        df["flaw_line_index"] = df["flaw_line_index"].apply(clean_list_str)

        df.to_csv(args.output_csv, index=False)
        print(
            f"Saved CSV with selected columns {desired_cols}: {args.output_csv}"
        )
        vul_rows = (df["vul"] == 1).sum() if "vul" in df.columns else "n/a"
        print(f"Total rows: {len(df)}; vul rows: {vul_rows}")
    except Exception as e:
        print(f"Failed to write output CSV {args.output_csv}: {e}")
        sys.exit(3)


if __name__ == "__main__":
    main()
