#!/bin/bash
# VP-Bench 데이터셋 생성 워크플로우 (Step 1)
# Step 1: scrape_vpbench_test_cve.sh 실행

set -e

# 디렉토리 경우
set -a
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="$BASE_DIR/archive"
INPUT_DIR="$BASE_DIR/input"
OUTPUT_DIR="$BASE_DIR/output"
SCRIPT_DIR="$BASE_DIR/scripts"
PROJECT_ROOT="$(cd "$BASE_DIR/.." && pwd)"
PROJECT="jasper"
set +a

ORIG_ARGS=("$@")

usage() {
    echo "Usage: $0 [--project <name>]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            if [[ -z "${2:-}" ]]; then
                echo "[ERROR] --project requires a value"
                usage
                exit 1
            fi
            PROJECT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# 로그 디렉토리 생성 및 워크플로우 로그 기록
LOG_DIR="$PROJECT_ROOT/logs/dataset_pipeline"
mkdir -p "$LOG_DIR"

# 모든 출력을 로그 파일과 화면에 동시에 출력
exec > >(tee -a "$LOG_DIR/$(date +"%Y%m%d_%H%M%S")_dataset_pipeline.log") 2>&1
echo "[$(date)] Command: $0 ${ORIG_ARGS[*]}"

# Step 1: codeLink, CVE ID, project 추출
STEP1_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_(codeLink,CVE ID).csv"
if [ -f "$STEP1_OUT" ]; then
    echo "Step 1 결과 파일이 이미 존재합니다. 스킵합니다."
else
    bash "$SCRIPT_DIR/scrape_vpbench_test_cve.sh" "$PROJECT"
    echo "Step 1 완료: $STEP1_OUT 생성 여부를 확인하세요."
fi



# Step 2: files_changed, lang 컬럼 추가
STEP2_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed.csv"
if [ -f "$STEP2_OUT" ]; then
    echo "Step 2 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$SCRIPT_DIR"
    python3 get_files_changed_with_lang.py --project "$PROJECT"
    echo "Step 2 완료: $STEP2_OUT 생성 여부를 확인하세요."
fi


# Step 3: vulnerable function 확장
STEP3_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_vulfunc.csv"
if [ -f "$STEP3_OUT" ]; then
    echo "Step 3 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$SCRIPT_DIR"
    python3 extract_functions.py \
        --input_csv "$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed.csv" \
        --output_csv "$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_vulfunc.csv"
    echo "Step 3 완료: $STEP3_OUT 생성 여부를 확인하세요."
fi


# Step 4: flaw_line_index, processed_func 컬럼 추가
STEP4_IN="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_vulfunc.csv"
STEP4_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_targets.csv"
if [ -f "$STEP4_OUT" ]; then
    echo "Step 4 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$SCRIPT_DIR"
    python3 add_processed_columns.py --input-csv "$STEP4_IN" --output-csv "$STEP4_OUT"
    echo "Step 4 완료: $STEP4_OUT 생성 여부를 확인하세요."
fi

# Step 5: RealVul 형식 변환 (project_dataset.csv 생성)
STEP5_IN="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_targets.csv"
STEP5_OUT="$OUTPUT_DIR/$PROJECT/${PROJECT}_dataset.csv"
if [ -f "$STEP5_OUT" ]; then
    echo "Step 5 결과 파일이 이미 존재합니다. 스킵합니다."
else
    mkdir -p "$OUTPUT_DIR/$PROJECT/repository"
    cd "$SCRIPT_DIR"
    SLURM_TMPDIR="$OUTPUT_DIR/$PROJECT/repository" python3 data_collection.py --input-csv "$STEP5_IN" --output-csv "$STEP5_OUT"
    echo "Step 5 완료: $STEP5_OUT 생성 여부를 확인하세요."
fi

# Step 5.5: all_functions pickle 생성
STEP55_OUT="$OUTPUT_DIR/$PROJECT/all_functions/${PROJECT}_new_all_functions.pickle"
if [ -f "$STEP55_OUT" ]; then
    echo "Step 5.5 결과 파일이 이미 존재합니다. 스킵합니다."
else
    mkdir -p "$OUTPUT_DIR/$PROJECT/all_functions"
    cd "$SCRIPT_DIR"
    python3 generate_all_functions.py --project "$PROJECT"
    echo "Step 5.5 완료: $STEP55_OUT 생성 여부를 확인하세요."
fi

# Step 6: data_filtration.py 실행
STEP6_OUT="$OUTPUT_DIR/$PROJECT/real_vul_functions_dataset.csv"
if [ -f "$STEP6_OUT" ]; then
    echo "Step 6 결과 파일이 이미 존재합니다. 스킵합니다."
else
    cd "$SCRIPT_DIR"
    python3 data_filtration.py --projects "$PROJECT"
    echo "Step 6 완료: $STEP6_OUT 생성 여부를 확인하세요."
fi