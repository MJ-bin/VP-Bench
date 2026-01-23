#!/usr/bin/env python3

import argparse
from pathlib import Path
import pickle
import subprocess

def list_function_starts(file_path: Path, lang: str) -> list[int]:
    kinds_flag = "--c-kinds=f" if lang == "c" else "--c++-kinds=f"
    lang_flag = f"--language-force={'C' if lang == 'c' else 'C++'}"
    cmd = ["ctags", "-x", lang_flag, kinds_flag, str(file_path)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        return []
    starts = []
    for line in proc.stdout.splitlines():
        tokens = [t for t in line.split() if t]
        if len(tokens) >= 5 and tokens[4].startswith("}"):
            print(f"[SKIP_CTAG_BROKEN] file={file_path} excmd={' '.join(tokens[4:])}")
            continue
        if tokens[2].isdigit():
            starts.append(int(tokens[2]))
    return starts

def read_function_block(file_path: Path, start_line: int) -> int:
    depth = 0
    in_body = False
    with file_path.open("r", errors="ignore") as f:
        for idx, line in enumerate(f, start=1):
            if idx < start_line:
                continue
            if not line.lstrip().startswith("//"):
                depth += line.count("{")
                depth -= line.count("}")
                if line.count("{") > 0:
                    in_body = True
            if in_body and depth == 0:
                return idx
    return 0

def build_all_functions(source_dir: Path) -> dict:
    all_funcs: dict[str, list[dict]] = {}
    for path in sorted(source_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(source_dir).as_posix()
        starts = list_function_starts(path, 'C')
        ranges = []
        for start in starts:
            end = read_function_block(path, start)
            if end > 0:
                ranges.append({"start": start, "end": end})
        if ranges:
            all_funcs[rel] = ranges
    return all_funcs

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project")
    parser.add_argument("--input")
    parser.add_argument("--output")
    parser.add_argument("--uncertain-unit", choices=["file", "function"], default="file")
    args = parser.parse_args()

    source_dir = Path(args.input) # if args.source_dir else base_dir / "output" / project / "source_code"
    output_pickle = Path(args.output) # if args.output else base_dir / "output" / project / "all_functions" / f"{project}_new_all_functions.pickle"

    output_pickle.parent.mkdir(parents=True, exist_ok=True)
    all_funcs: dict[str, list[dict]] = {}
    
    if args.uncertain_unit == "file":
        for path in sorted(source_dir.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(source_dir).as_posix()
            
            # 파일 전체를 하나의 범위로 (start=1, end=파일끝)
            with path.open("r", errors="ignore") as f:
                total_lines = sum(1 for _ in f)
            if total_lines > 0:
                all_funcs[rel] = [{"start": 1, "end": total_lines}]
    elif args.uncertain_unit == "function":
        all_funcs = build_all_functions(source_dir)
    
    with output_pickle.open("wb") as f:
        pickle.dump(all_funcs, f)

if __name__ == "__main__":
    main()