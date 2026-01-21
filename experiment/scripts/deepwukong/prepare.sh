#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"

# RealVul Train 데이터셋 준비 함수 (vpbench | realvul)
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

    mkdir -p "$DOWNLOADS_DIR/RealVul/datasets/$DS_NAME"

    # 작업 디렉토리를 보존하기 위해 pushd/popd 사용
    pushd "$DOWNLOADS_DIR/RealVul/datasets/$DS_NAME" > /dev/null

    local input_root="../../../../dataset_pipeline/output/$variant"
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

echo "=== DeepWukong 데이터 준비 스크립트 ==="

# 디렉토리 구조 생성
echo "[1/7] 디렉토리 구조 생성..."
mkdir -p "$DOWNLOADS_DIR/DeepWukong/data"
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets"

# DeepWukong 모델 데이터 다운로드
echo "[2/7] DeepWukong Data.7z 다운로드..."
pushd "$DOWNLOADS_DIR/DeepWukong/data"

if [ ! -f "Data.7z" ]; then
    echo "  - Data.7z 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/Data.7z
else
    echo "  - Data.7z 이미 존재 (스킵)"
fi

# Data.7z 압축 해제
echo "[3/7] Data.7z 압축 해제..."
if [ ! -d "CWE119" ]; then
    7z x Data.7z -y
    echo "  - 압축 해제 완료"
else
    echo "  - CWE119 디렉토리 이미 존재 (스킵)"
fi

# DeepWukong 모델 파일 다운로드
echo "[4/7] DeepWukong 모델 파일 다운로드..."
if [ ! -f "DeepWukong" ]; then
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/DeepWukong
    echo "  - 모델 파일 다운로드 완료"
else
    echo "  - DeepWukong 모델 파일 이미 존재 (스킵)"
fi
popd

# RealVul 데이터셋 다운로드
echo "[5/7] RealVul 데이터셋 다운로드..."
prepare_dataset "realvul"


# VP-Bench 테스트 데이터셋 다운로드
echo "[6/7] VP-Bench 테스트 데이터셋 다운로드..."
prepare_dataset "vpbench"

# 파일 검증
echo "[7/7] 파일 검증..."
cd - > /dev/null
cd ../../../../
echo ${PWD}

test -d "$DOWNLOADS_DIR/DeepWukong/data/CWE119" || { echo "Error: CWE119 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/DeepWukong/data/DeepWukong" || { echo "Error: DeepWukong 모델 파일을 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Train_Dataset/Real_Vul_data.csv" || { echo "Error: VP-Bench_Train_Dataset/Real_Vul_data.csv를 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Train_Dataset/all_source_code" || { echo "Error: VP-Bench_Train_Dataset/all_source_code를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Test_Dataset/Real_Vul_data.csv" || { echo "Error: VP-Bench_Test_Dataset/Real_Vul_data.csv를 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Test_Dataset/all_source_code" || { echo "Error: VP-Bench_Test_Dataset/all_source_code를 찾을 수 없습니다"; exit 1; }

echo "✅ 모든 파일 검증 완료!"

echo ""
echo "=========================================="
echo "✅ 모든 데이터 준비 완료!"
echo "=========================================="
echo ""
echo "데이터 위치:"
echo "  - DeepWukong 모델: $DOWNLOADS_DIR/DeepWukong/data"
echo "  - VP-Bench Train 데이터: $DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Train_Dataset"
echo "  - VP-Bench Test 데이터: $DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Test_Dataset"
