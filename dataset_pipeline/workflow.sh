#!/bin/bash
# VP-Bench 데이터셋 생성 워크플로우 (Step 1)
# Step 1: scrape_vpbench_test_cve.sh 실행

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATASET_DIR="$SCRIPT_DIR/VP-Bench_Dataset"

# 전체 워크플로우 로그 기록
exec > >(tee -a "$DATASET_DIR/workflow.log") 2>&1

# Step 1: codeLink, CVE ID, project 추출 (jasper만)
STEP1_OUT="$DATASET_DIR/output/jasper/VP-Bench_jasper_(codeLink,CVE ID).csv"
if [ -f "$STEP1_OUT" ]; then
    echo "Step 1 결과 파일이 이미 존재합니다. 스킵합니다."
else
    bash "$DATASET_DIR/scrape_vpbench_test_cve.sh" jasper
    echo "Step 1 완료: $STEP1_OUT 생성 여부를 확인하세요."
fi



# Step 2: files_changed, lang 컬럼 추가
STEP2_OUT="$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed.csv"
if [ -f "$STEP2_OUT" ]; then
    echo "Step 2 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$DATASET_DIR"
    python3 ../get_files_changed_with_lang.py
    echo "Step 2 완료: $STEP2_OUT 생성 여부를 확인하세요."
fi


# Step 3: vulnerable function 확장
STEP3_OUT="$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed_with_vulfunc.csv"
if [ -f "$STEP3_OUT" ]; then
    echo "Step 3 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$SCRIPT_DIR"
    python3 VP-Bench_step3.py \
        --input_csv "$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed.csv" \
        --output_csv "$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed_with_vulfunc.csv"
    echo "Step 3 완료: $STEP3_OUT 생성 여부를 확인하세요."
fi


# Step 4: flaw_line_index, processed_func 컬럼 추가
STEP4_IN="$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed_with_vulfunc.csv"
STEP4_OUT="$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed_with_targets.csv"
if [ -f "$STEP4_OUT" ]; then
    echo "Step 4 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$SCRIPT_DIR"
    python3 add_processed_columns.py --input-csv "$STEP4_IN" --output-csv "$STEP4_OUT"
    echo "Step 4 완료: $STEP4_OUT 생성 여부를 확인하세요."
fi

# Step 5: RealVul 형식 변환 (jasper_dataset.csv 생성)
STEP5_IN="$DATASET_DIR/output/jasper/VP-Bench_jasper_files_changed_with_targets.csv"
STEP5_OUT="$DATASET_DIR/output/jasper/jasper_dataset.csv"
if [ -f "$STEP5_OUT" ]; then
    echo "Step 5 결과 파일이 이미 존재합니다. 스킵합니다."
else
    mkdir -p "$SCRIPT_DIR/SLURM_TMPDIR"
    cd "$SCRIPT_DIR"
    SLURM_TMPDIR="$SCRIPT_DIR/SLURM_TMPDIR" python3 Data_Collection.py --input-csv "$STEP5_IN" --output-csv "$STEP5_OUT"
    echo "Step 5 완료: $STEP5_OUT 생성 여부를 확인하세요."
fi