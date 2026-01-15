#!/usr/bin/env python3

import argparse
from pathlib import Path
import pickle

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="jasper")
    parser.add_argument("--input")
    parser.add_argument("--output")
    args = parser.parse_args()

    base_dir = Path(__file__).resolve().parent.parent
    source_dir = Path(args.input) # if args.source_dir else base_dir / "output" / project / "source_code"
    output_pickle = Path(args.output) # if args.output else base_dir / "output" / project / "all_functions" / f"{project}_new_all_functions.pickle"

    output_pickle.parent.mkdir(parents=True, exist_ok=True)
    all_funcs: dict[str, list[dict]] = {}
    
    for path in sorted(source_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(source_dir).as_posix()
        
        # 파일 전체를 하나의 범위로 (start=1, end=파일끝)
        with path.open("r", errors="ignore") as f:
            total_lines = sum(1 for _ in f)
        if total_lines > 0:
            all_funcs[rel] = [{"start": 1, "end": total_lines}]
    with output_pickle.open("wb") as f:
        pickle.dump(all_funcs, f)
    print(f"saved: {output_pickle} (files with functions: {len(all_funcs)})")

if __name__ == "__main__":
    main()