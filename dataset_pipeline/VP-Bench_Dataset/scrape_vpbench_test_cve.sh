#!/bin/bash
# run_cve_pipeline.sh - 메인 실행 스크립트

# 현재 스크립트의 디렉토리 경로 가져오기 (VP-Bench_Dataset 기준)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 모듈 로드
source "$SCRIPT_DIR/scripts/config.sh"
source "$SCRIPT_DIR/scripts/utils.sh"
source "$SCRIPT_DIR/scripts/download.sh"
source "$SCRIPT_DIR/scripts/filter.sh"
source "$SCRIPT_DIR/scripts/merge.sh"

# ==============================================================================
# 메인 실행 로직
# ==============================================================================

# 1. 인자 파싱
INPUT_ARG=${1:-all}

# 로그 파일 경로 지정 (날짜/시간 포함)
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +"%Y%m%d_%H%M%S")_${INPUT_ARG}_execution.log"

# 전체 실행을 tee로 로그 파일에 저장
{
    if [ "$INPUT_ARG" == "all" ]; then
        echo "🎯 Target: 전체 프로젝트 (${#ALL_PROJECTS[@]}개) 처리 시작"
        TARGET_LIST=("${ALL_PROJECTS[@]}")
    else
        echo "🎯 Target: 단일 프로젝트 '$INPUT_ARG' 처리 시작"
        TARGET_LIST=("$INPUT_ARG")
    fi

    # 2. 디렉토리 설정
    setup_directories "${TARGET_LIST[@]}"

    # 3. 배너 출력
    print_banner "${TARGET_LIST[@]}"

    # 4. CVE 데이터 추출
    extract_all_cves "${TARGET_LIST[@]}"

    # 5. 데이터 통합
    merge_all_projects "${TARGET_LIST[@]}"

    # 6. 빈 폴더 정리
    cleanup_empty_projects "${TARGET_LIST[@]}"

    echo ""
    echo "✨ 모든 작업이 완료되었습니다!"
} | tee "$LOG_FILE"