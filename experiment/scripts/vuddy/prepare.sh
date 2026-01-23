#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"

prepare_dataset() {
    local variant="${1:-vpbench}"
    case "$variant" in
        vpbench) 
            DS_NAME="VP-Bench_Test_Dataset";;
        realvul) 
            DS_NAME="VP-Bench_Train_Dataset";;
        *)
            echo "Error: invalid dataset source '$variant' (use 'vpbench' or 'realvul')"
            exit 1
            ;;
    esac

    mkdir -p "$DOWNLOADS_DIR/vuddy/$DS_NAME"

    # 작업 디렉토리를 보존하기 위해 pushd/popd 사용
    pushd "$DOWNLOADS_DIR/vuddy/$DS_NAME" > /dev/null

    local input_root="../../../dataset_pipeline/output/$variant"
    # Real_Vul_data.csv
    if [ ! -f "Real_Vul_data.csv" ]; then
        echo "  - Real_Vul_data.csv 가져오는 중... (from $input_root)"
        if [ -f "$input_root/Real_Vul_data.csv" ]; then
            cp "$input_root/Real_Vul_data.csv" .
        else
            echo "Error: 소스에서 Real_Vul_data.csv를 찾을 수 없습니다: $input_root"
            popd > /dev/null
            exit 1
        fi
    else
        echo "  - Real_Vul_data.csv 이미 존재 (스킵)"
    fi

    # all_source_code: 검증 단계는 tar.xz를 기대하므로 우선 tarball을 복사, 없으면 생성
    if [ ! -d "all_source_code" ]; then
        echo "  - all_source_code 가져오는 중... (from $input_root)"
        cp -r "$input_root/all_source_code" .
    else
        echo "  - all_source_code 이미 존재 (스킵)"
    fi

    popd > /dev/null
}

echo "=== Vuddy 데이터 준비 스크립트 ==="

# VP-Bench 테스트 데이터셋 다운로드 및 압축 해제
echo "[1/2] VP-Bench 테스트 데이터셋 다운로드 및 압축 해제..."
prepare_dataset vpbench
echo "✅ VP-Bench 테스트 데이터셋 준비 완료!"

# RealVul 데이터셋 다운로드 및 압축 해제
prepare_dataset realvul
echo "✅ RealVul 데이터셋 준비 완료!"

echo ""
echo "=========================================="
echo "✅ 모든 데이터 준비 완료!"
echo "=========================================="