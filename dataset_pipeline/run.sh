#!/bin/bash
# VP-Bench 데이터셋 생성 워크플로우 (Step 1)
# Step 1: scrape_vpbench_test_cve.sh 실행

set -e

# 디렉토리 경우
set -a
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="$BASE_DIR/archive"
INPUT_DIR="$BASE_DIR/input"
OUTPUT_BASE="$BASE_DIR/output"
SCRIPT_DIR="$BASE_DIR/scripts"
PROJECT_ROOT="$(cd "$BASE_DIR/.." && pwd)"
set +a

LOG_DIR="$PROJECT_ROOT/logs/dataset_pipeline"
PROJECTS=("FFmpeg" "ImageMagick" "jasper" "krb5" "openssl" "php-src" "qemu" "tcpdump" "linux" "Chrome")
SELECTED_PROJECTS=("jasper")  # 기본값
ORIG_ARGS=("$@")
MODE="vpbench"
LABELS=("train_val" "test")  # 기본값

usage() {
    echo "Usage: $0 [--projects <target_project>] [--mode <vpbench|realvul>] [--labels <label1,label2,...>]"
    echo "  --projects: 처리할 프로젝트 (기본값: jasper)"
    echo "              'all'을 지정하면 모든 프로젝트 처리"
    echo "  --mode: 출력 루트 모드 (vpbench|realvul, 기본값: vpbench)"
    echo "  --labels: 데이터셋 라벨 (쉼표로 구분, 기본값: train_val,test)"
}

# 스텝 실행 함수
run_step() {
    local step_num=$1
    local output=$2
    local script=$3
    shift 3
    local args=("$@")
    
    if [ -f "$output" ]; then
        echo "Step $step_num 결과 파일이 이미 존재합니다. 스킵합니다."
    else
        "$SCRIPT_DIR/$script" "${args[@]}"
        echo "Step $step_num 완료: $output 생성 여부를 확인하세요."
    fi
}

# 모든 출력을 로그 파일과 화면에 동시에 출력
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/$(date +"%Y%m%d_%H%M%S")_dataset_pipeline.log") 2>&1
echo "[$(date)] Command: $0 ${ORIG_ARGS[*]}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --projects)
            if [ "$2" = "all" ]; then
                SELECTED_PROJECTS=("${PROJECTS[@]}")
            else
                IFS=',' read -ra SELECTED_PROJECTS <<< "$2"
            fi
            shift 2
            ;;
        --mode)
            if [ -n "$2" ]; then
                MODE="$2"
            fi
            shift 2
            ;;
        --labels)
            if [ -n "$2" ]; then
                IFS=',' read -ra LABELS <<< "$2"
            fi
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

export OUTPUT_DIR="$OUTPUT_BASE/$MODE"

# 각 프로젝트마다 반복 처리
for PROJECT in "${SELECTED_PROJECTS[@]}"; do
    echo "=========================================="
    echo "Processing project: $PROJECT"
    echo "=========================================="
    
    # Step 1: codeLink, CVE ID, project 추출
    STEP1_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_(codeLink,CVE ID).csv"
    run_step 1 "$STEP1_OUT" "scrape_vpbench_test_cve.sh" "$PROJECT"

    # Step 2: files_changed, lang 컬럼 추가
    STEP2_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed.csv"
    run_step 2 "$STEP2_OUT" "get_files_changed_with_lang.py" --input "$STEP1_OUT" --output "$STEP2_OUT"

    # Step 3: vulnerable function 확장
    STEP3_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_vulfunc.csv"
    run_step 3 "$STEP3_OUT" "extract_functions.py" --input "$STEP2_OUT" --output "$STEP3_OUT" --project "$PROJECT" --output-dir "$OUTPUT_DIR"

    # Step 4: flaw_line_index, processed_func 컬럼 추가
    STEP4_OUT="$OUTPUT_DIR/$PROJECT/VP-Bench_${PROJECT}_files_changed_with_targets.csv"
    run_step 4 "$STEP4_OUT" "add_processed_columns.py" --input "$STEP3_OUT" --output "$STEP4_OUT"

    # Step 5: RealVul 형식 변환 (project_dataset.csv 생성)
    STEP5_OUT="$OUTPUT_DIR/$PROJECT/${PROJECT}_dataset.csv"
    run_step 5 "$STEP5_OUT" "data_collection.py" --input "$STEP4_OUT" --output "$STEP5_OUT" --project "$PROJECT" --output-dir "$OUTPUT_DIR" --labels "${LABELS[@]}"

    # Step 6: all_functions pickle 생성
    STEP6_OUT="$OUTPUT_DIR/$PROJECT/all_functions/${PROJECT}_new_all_functions.pkl"
    run_step 6 "$STEP6_OUT" "generate_all_functions.py" --input "$OUTPUT_DIR/$PROJECT/source_code" --output "$STEP6_OUT" --project "$PROJECT"

done

# Step 7: data_filtration.py 실행
STEP7_OUT="$OUTPUT_DIR/real_vul_functions_dataset.csv"
run_step 7 "$STEP7_OUT" "data_filtration.py" --output-dir "$OUTPUT_DIR" --projects "${SELECTED_PROJECTS[@]}"