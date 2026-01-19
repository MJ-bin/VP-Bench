#!/usr/bin/env python3
"""
회귀 테스트: golden dataset과 비교
경로는 golden JSON에서 동적으로 로드
"""

import pandas as pd
import hashlib
import json
import sys
from pathlib import Path
import argparse

def get_csv_hash(csv_path):
    """CSV 파일의 MD5 해시"""
    df = pd.read_csv(csv_path)
    content = df.to_csv(index=False)
    return hashlib.md5(content.encode()).hexdigest()

def load_all_golden(golden_dir: Path):
    """validation 폴더의 모든 golden dataset 로드"""
    golden_files = sorted(golden_dir.glob("step*.json"))
    
    golden_data = {}
    for f in golden_files:
        with open(f) as fp:
            golden_data[f.stem] = json.load(fp)  # step1, step2, ...
    
    return golden_data

def compare_step(golden):
    """하나의 step golden dataset과 비교"""
    
    step_num = golden["step"]
    csv_path = Path(golden["file"])
    
    # CSV 파일 없으면 실패
    if not csv_path.exists():
        return False, f"✗ Step {step_num}: {csv_path} 파일 없음"
    
    # 현재 파일 분석
    df = pd.read_csv(csv_path)
    current_hash = get_csv_hash(csv_path)
    
    # 1. 해시 일치 확인
    if current_hash == golden["hash"]:
        return True, f"✓ Step {step_num}: 정확히 일치"
    
    # 2. 행/컬럼 확인
    if len(df) != golden["rows"]:
        return False, f"✗ Step {step_num}: 행 수 변경 ({golden['rows']} → {len(df)})"
    
    if list(df.columns) != golden["columns"]:
        return False, f"✗ Step {step_num}: 컬럼 변경"
    
    # 3. 샘플 비교 (첫 3행)
    sample_df = df.head(3)
    sample_expected = pd.DataFrame(golden["first_3_rows"])
    
    if not sample_df.equals(sample_expected):
        return False, f"✗ Step {step_num}: 데이터 내용 변경"
    
    # 내용 변경됨
    return False, f"✗ Step {step_num}: 내용 변경됨"

def main():
    """회귀 테스트 실행 엔트리포인트"""
    parser = argparse.ArgumentParser(description="Golden Dataset 회귀 테스트")
    parser.add_argument(
        "action",
        nargs="?",
        default="test",
        choices=["test", "save-golden"],
        help="실행 모드: test 또는 save-golden (기본: test)",
    )
    parser.add_argument(
        "--output-base",
        default="output/jasper",
        help="산출물 기본 경로 (예: output/jasper)",
    )
    parser.add_argument(
        "--validation-dir",
        default="validation",
        help="Golden 파일 저장/로드 경로 (기본: validation)",
    )
    args = parser.parse_args()
    save_mode = args.action == "save-golden"
    
    # Golden dataset 로드 또는 생성
    if save_mode:
        # 현재 산출물에서 golden 데이터 생성
        base = Path(args.output_base)
        golden_specs = [
            {"step": 1, "file": str(base / "VP-Bench_jasper_(codeLink,CVE ID).csv")},
            {"step": 2, "file": str(base / "VP-Bench_jasper_files_changed.csv")},
            {"step": 3, "file": str(base / "VP-Bench_jasper_files_changed_with_vulfunc.csv")},
            {"step": 4, "file": str(base / "VP-Bench_jasper_files_changed_with_targets.csv")},
            {"step": 5, "file": str(base / "jasper_dataset.csv")},
            {"step": 6, "file": str(base / "real_vul_functions_dataset.csv")},
        ]
        
        print("\n" + "━"*60)
        print("  Golden Dataset 저장")
        print("━"*60 + "\n")
        
        validation_dir = Path(args.validation_dir)
        validation_dir.mkdir(exist_ok=True)
        
        for spec in golden_specs:
            csv_path = Path(spec["file"])
            
            if not csv_path.exists():
                print(f"⊘ Step {spec['step']}: {csv_path} 파일 없음 (스킵)")
                continue
            
            df = pd.read_csv(csv_path)
            
            golden = {
                "step": spec["step"],
                "file": spec["file"],
                "hash": get_csv_hash(csv_path),
                "rows": len(df),
                "columns": list(df.columns),
                "first_3_rows": df.head(3).to_dict(orient="records"),
            }
            
            golden_file = validation_dir / f"step{spec['step']}.json"
            with open(golden_file, "w") as f:
                json.dump(golden, f, indent=2)
            
            print(f"✓ Step {spec['step']}: {len(df)} rows ({golden_file})")
        
        print("\n" + "━"*60)
        print("✓ Golden dataset 저장 완료\n")
        
        return 0
    
    # 테스트 모드: golden과 비교
    golden_data = load_all_golden(Path(args.validation_dir))
    
    if not golden_data:
        print("\n✗ Golden dataset 없음")
        print("먼저 저장하세요: python3 scripts/regression_test.py save-golden\n")
        return 1
    
    print("\n" + "━"*60)
    print("  회귀 테스트")
    print("━"*60 + "\n")
    
    all_passed = True
    for step_key in sorted(golden_data.keys()):
        golden = golden_data[step_key]
        result, msg = compare_step(golden)
        print(msg)
        
        if result is False:
            all_passed = False
    
    # Step 5.5 (pickle) 간단히 확인
    pickle_path = Path("output/jasper/all_functions/jasper_new_all_functions.pickle")
    if pickle_path.exists():
        size = pickle_path.stat().st_size / (1024*1024)
        print(f"✓ Step 5.5: {size:.1f} MB")
    else:
        print(f"⊘ Step 5.5: pickle 파일 없음 (스킵)")
    
    print("\n" + "━"*60 + "\n")
    
    if all_passed:
        print("✓ 모든 테스트 통과\n")
    else:
        print("✗ 테스트 실패\n")
        print("의도된 변경인 경우:")
        print("  $ python3 scripts/regression_test.py save-golden\n")
    
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())
