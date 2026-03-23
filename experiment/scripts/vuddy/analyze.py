#! /bin/python3

import os
import sys
import csv
import pandas as pd
import json
import requests
import re
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score,
    f1_score, matthews_corrcoef, confusion_matrix as sk_confusion_matrix
)

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
from baseline.vuddy.hmark import parseutility2 as parser


PROJECT_GIT_URLS = {
    "FFmpeg": "https://github.com/FFmpeg/FFmpeg",
    "ImageMagick": "https://github.com/ImageMagick/ImageMagick",
    "jasper": "https://github.com/jasper-software/jasper",
    "krb5": "https://github.com/krb5/krb5",
    "openssl": "https://github.com/openssl/openssl",
    "php-src": "https://github.com/php/php-src",
    "qemu": "https://github.com/qemu/qemu",
    "tcpdump": "https://github.com/the-tcpdump-group/tcpdump",
    "linux": "https://github.com/torvalds/linux",
    "Chrome": "https://github.com/chromium/chromium"
}


def extract_function_diff(diff_content, func_name):
    """
    Extract lines related to a specific function from a git diff.
    Returns a string containing the relevant diff hunks.
    """
    lines = diff_content.split('\n')
    relevant_lines = []
    in_hunk = False
    hunk_lines = []
    
    for line in lines:
        # Check if this is a hunk header
        if line.startswith('@@'):
            if hunk_lines and func_name in '\n'.join(hunk_lines):
                relevant_lines.extend(hunk_lines)
            hunk_lines = [line]
            in_hunk = True
        elif in_hunk:
            hunk_lines.append(line)
            # Check if function name appears in added/removed lines
            if func_name in line:
                if not relevant_lines or relevant_lines[-1].startswith('@@'):
                    relevant_lines.extend(hunk_lines)
    
    # Check last hunk
    if hunk_lines and func_name in '\n'.join(hunk_lines):
        relevant_lines.extend(hunk_lines)
    
    return '\n'.join(relevant_lines) if relevant_lines else None

# parse the results into a structured format
with open("experiment/result/vuddy/vuddy_result.txt", "r") as f:
    lines = f.readlines()

clone_matches = []
i = 1
while i < len(lines):
    line = lines[i].strip()
    if line.startswith("[+]"):
        func_hash = lines[i - 1].strip()
        parts = line.split()
        test_func_index_raw = int(parts[1].split("-th")[0])
        test_src_file = parts[4]
        train_src_file = parts[-1]
        test_unique_id = int(os.path.basename(test_src_file).split(".c")[0])
        train_unique_id = int(os.path.basename(train_src_file).split(".c")[0])
        clone_matches.append({
            "function_hash": func_hash,
            "test_unique_id": test_unique_id,
            "train_unique_id": train_unique_id,
            "test_function_index_raw": test_func_index_raw
        })
    i += 1

train_df = pd.read_csv("downloads/vuddy/VP-Bench_Train_Dataset/Real_Vul_data.csv")

results = []

# === VUDDY Detection Analysis ===
# Step A: 탐지된 test_unique_id 집합 구성
detected_test_ids = set(m["test_unique_id"] for m in clone_matches)
print(f"VUDDY detected {len(detected_test_ids)} unique test samples from {len(clone_matches)} clone matches")

# Paths
GROUND_TRUTH_CSV = "downloads/vuddy/VP-Bench_Test_Dataset/Real_Vul_data.csv"
OUTPUT_DIR = "experiment/result/vuddy"
EVAL_RESULT_CSV = os.path.join(OUTPUT_DIR, "eval_result.csv")
ANALYSIS_JSON = os.path.join(OUTPUT_DIR, "prediction_analysis.json")

os.makedirs(OUTPUT_DIR, exist_ok=True)
csv.field_size_limit(sys.maxsize)

# Step B: Ground truth CSV 스트리밍 처리
all_ref = []
all_pred = []
fn_samples = []
fp_samples = []

print(f"Processing ground truth: {GROUND_TRUTH_CSV}")
print(f"Writing per-sample results to: {EVAL_RESULT_CSV}")

with open(GROUND_TRUTH_CSV, "r", encoding="utf-8") as f_in, \
     open(EVAL_RESULT_CSV, "w", encoding="utf-8", newline="") as f_out:

    reader = csv.DictReader(f_in)
    fieldnames = reader.fieldnames + ["model_predict", "confusion_matrix"]
    writer = csv.DictWriter(f_out, fieldnames=fieldnames)
    writer.writeheader()

    for row_idx, row in enumerate(reader):
        unique_id = int(row["unique_id"])
        target = int(row["target"])

        pred = 1 if unique_id in detected_test_ids else 0

        if target == 1 and pred == 1:
            cm_label = "TP"
        elif target == 0 and pred == 0:
            cm_label = "TN"
        elif target == 0 and pred == 1:
            cm_label = "FP"
        else:
            cm_label = "FN"

        all_ref.append(target)
        all_pred.append(pred)

        if cm_label in ("FN", "FP"):
            sample_info = {
                "index": row_idx,
                "unique_id": row["unique_id"],
                "project": row["project"],
                "commit_hash": row["commit_hash"],
                "target": target,
                "predicted": pred,
            }
            if cm_label == "FN":
                fn_samples.append(sample_info)
            else:
                fp_samples.append(sample_info)

        row["model_predict"] = pred
        row["confusion_matrix"] = cm_label
        writer.writerow(row)

        if (row_idx + 1) % 10000 == 0:
            print(f"  Processed {row_idx + 1} rows...")

print(f"Finished processing {row_idx + 1} rows total")

# Step C: 메트릭 계산 및 출력
cm = sk_confusion_matrix(all_ref, all_pred)
tn, fp_count, fn_count, tp = cm.ravel()

result_dict = {
    "Accuracy": float(accuracy_score(all_ref, all_pred)),
    "Precision": float(precision_score(all_ref, all_pred, average="binary", zero_division=0)),
    "Recall": float(recall_score(all_ref, all_pred, average="binary", zero_division=0)),
    "F1-Score": float(f1_score(all_ref, all_pred, average="binary", zero_division=0)),
    "MCC": float(matthews_corrcoef(all_ref, all_pred)),
    "TP (True Positive)": int(tp),
    "TN (True Negative)": int(tn),
    "FP (False Positive)": int(fp_count),
    "FN (False Negative)": int(fn_count),
    "Total Samples": len(all_ref),
    "Total Clone Matches": len(clone_matches),
    "Unique Detected Samples": len(detected_test_ids),
}

print("\n" + "=" * 80)
print("VUDDY Detection Analysis Results")
print("=" * 80)
for k, v in result_dict.items():
    if isinstance(v, float):
        print(f"  {k}: {v:.4f}")
    else:
        print(f"  {k}: {v}")

print(f"\nFN (missed vulnerabilities): {len(fn_samples)}")
print(f"FP (false alarms): {len(fp_samples)}")

# Step D: JSON 분석 리포트 저장
analysis_result = {
    "summary": result_dict,
    "ground_truth_csv": GROUND_TRUTH_CSV,
    "fn_count": len(fn_samples),
    "fp_count": len(fp_samples),
    "fn_samples": fn_samples,
    "fp_samples": fp_samples,
    "detected_test_ids": sorted(list(detected_test_ids)),
}

with open(ANALYSIS_JSON, "w", encoding="utf-8") as f:
    json.dump(analysis_result, f, indent=2, ensure_ascii=False)

print(f"\nResults saved:")
print(f"  - Per-sample CSV: {EVAL_RESULT_CSV}")
print(f"  - Analysis JSON:  {ANALYSIS_JSON}")
print("=" * 80)

# for idx, clone_match in enumerate(clone_matches):
#     # test_unique_id 이름의 파일(output/VP-Bench_Test_Dataset/vulnerable_code/에 위치)에서 "function_index of test" 번째 함수 추출 by 동일한 func-opt.jar 방식 이용 혹은 이전에 추출된 정보가 있다면 활용하는 방안 검토
#     src = f"baseline/vuddy/output/VP-Bench_Test_Dataset/vulnerable_source_code/all_source_code/{clone_match['test_unique_id']}.c"
#     funcs = parser.parseFile_deep(src, "")  # 함수 목록+본문 파싱
#     test_target = next(f for f in funcs if f.funcId == clone_match['test_function_index_raw'])  # funcId가 vuddy의 n-th 인덱스
    
#     # 추출한 함수와 train_unique_id의 취약 함수 diff 생성
#     with open(f"baseline/vuddy/output/VP-Bench_Train_Dataset/vulnerable_source_code/{clone_match['train_unique_id']}.c", "r") as f:
#         train_func_source = f.read()

#     # train 함수 이름 추출 (첫 번째 함수 기준)
#     train_src = f"baseline/vuddy/output/VP-Bench_Train_Dataset/vulnerable_source_code/{clone_match['train_unique_id']}.c"
#     train_funcs = parser.parseFile_deep(train_src, "")
#     train_target = train_funcs[0] if train_funcs else None
#     train_func_name = train_target.name.decode('utf-8') if train_target and isinstance(train_target.name, bytes) else (train_target.name if train_target else None)

#     # train_unique_id로 VP-Bench_Train_Dataset/Real_Vul_data.csv에서 project와 commit_hash 획득
#     row = df[df['unique_id'] == clone_match['train_unique_id']].iloc[0]
#     project = row['project']
#     train_commit_hash = row['commit_hash']
    
#     # commit_hash로 diff에서 이 함수와 관련된 변경사항 추출
#     diff_url = f"{PROJECT_GIT_URLS[project]}/commit/{train_commit_hash}.diff"
#     try:
#         diff_response = requests.get(diff_url, timeout=10)
#         if diff_response.status_code == 200:
#             diff_content = diff_response.text
#             # train_func_name으로 함수 변경사항 추출
#             func_diff = extract_function_diff(diff_content, train_func_name) if train_func_name else None
#         else:
#             func_diff = None
#     except Exception as e:
#         print(f"Error downloading diff for {train_commit_hash}: {e}")
#         func_diff = None
    
#     # 결과 저장
#     test_func_name = test_target.name.decode('utf-8') if isinstance(test_target.name, bytes) else test_target.name
#     result_item = {
#         "index": idx + 1,
#         "project": project,
#         "train_commit_hash": train_commit_hash,
#         # "diff_url": diff_url,
#         # "function_hash": clone_match["function_hash"],
#         "test_unique_id": clone_match["test_unique_id"],
#         "train_unique_id": clone_match["train_unique_id"],
#         "test_function_name": test_func_name,
#         "test_function_index": clone_match["test_function_index_raw"],
#         "train_function_source": train_func_source,
#         "test_function_body": test_target.funcBody.decode('utf-8') if isinstance(test_target.funcBody, bytes) else test_target.funcBody,
#         # "train_function_name": train_func_name,
#         "function_diff": func_diff
#     }
#     results.append(result_item)

# # 결과를 csv 형식으로 저장
# output_path = "experiment/result/vuddy/clone_analysis_results.csv"
# os.makedirs(os.path.dirname(output_path), exist_ok=True)
# df_results = pd.DataFrame(results)
# df_results.to_csv(output_path, index=False, encoding='utf-8')
# print(f"Results saved to {output_path}")
