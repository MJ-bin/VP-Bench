#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"
LOCK_FILE="datasets.lock.json"

echo "=== LineVul 데이터 준비 스크립트 ==="

# 디렉토리 구조 생성
echo "[1/5] 디렉토리 구조 생성..."
mkdir -p "$DOWNLOADS_DIR/LineVul/models"
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets"

# RealVul 공통 데이터셋 (이미 존재하면 스킵)
echo "[2/5] RealVul 데이터셋 다운로드..."
cd "$DOWNLOADS_DIR/RealVul/datasets"

if [ ! -f "dataset_without_src.7z" ]; then
    echo "  - dataset_without_src.7z 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z
else
    echo "  - dataset_without_src.7z 이미 존재 (스킵)"
fi

if [ ! -f "all_source_code.tar.xz" ]; then
    echo "  - all_source_code.tar.xz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz
else
    echo "  - all_source_code.tar.xz 이미 존재 (스킵)"
fi

# 데이터셋 압축 해제
echo "[3/5] RealVul 데이터셋 압축 해제..."
if [ ! -f "Real_Vul_data.csv" ]; then
    7z x dataset_without_src.7z -y
    echo "  - dataset_without_src.7z 압축 해제 완료"
else
    echo "  - Real_Vul_data.csv 이미 존재 (스킵)"
fi

if [ ! -d "all_source_code" ]; then
    tar -xf all_source_code.tar.xz
    echo "  - all_source_code.tar.xz 압축 해제 완료"
else
    echo "  - all_source_code 디렉토리 이미 존재 (스킵)"
fi

# LineVul 모델 다운로드
echo "[4/5] LineVul 모델 다운로드..."
cd - > /dev/null
cd "$DOWNLOADS_DIR/LineVul/models"
mkdir -p checkpoint-best-f1

if [ ! -f "checkpoint-best-f1/12heads_linevul_model.bin" ]; then
    echo "  - 모델 파일 다운로드 중..."
    gdown --fuzzy "https://drive.google.com/uc?id=1oodyQqRb9jEcvLMVVKILmu8qHyNwd-zH" \
        -O checkpoint-best-f1/12heads_linevul_model.bin
    echo "  - 모델 파일 다운로드 완료"
else
    echo "  - 모델 파일 이미 존재 (스킵)"
fi

# 검증
echo "[5/5] 파일 검증..."
echo ${PWD}
test -f "../../RealVul/datasets/Real_Vul_data.csv" || { echo "Error: Real_Vul_data.csv를 찾을 수 없습니다"; exit 1; }
test -d "../../RealVul/datasets/all_source_code" || { echo "Error: all_source_code 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "checkpoint-best-f1/12heads_linevul_model.bin" || { echo "Error: 모델 파일을 찾을 수 없습니다"; exit 1; }

echo "✅ LineVul 데이터 준비 완료!"
echo "   - RealVul 데이터셋: $(pwd)/../RealVul/datasets"
echo "   - LineVul 모델: $(pwd)/checkpoint-best-f1"
echo "   - Real_Vul_data.csv: $(du -sh ../RealVul/datasets/Real_Vul_data.csv | cut -f1)"
echo "   - 모델 파일: $(ls -lh checkpoint-best-f1/12heads_linevul_model.bin | awk '{print $5}')"

# datasets.lock.json 업데이트
echo ""
cd - > /dev/null
cd ../..

if [ -f "$LOCK_FILE" ]; then
    echo "  - $LOCK_FILE 업데이트 중..."
fi

cat > "$LOCK_FILE" <<EOF
{
  "version": "1.0.0",
  "generated": "$(date -Iseconds)",
  "datasets": {
    "RealVul": {
      "dataset_without_src.7z": {
        "url": "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z",
        "sha256": "$(sha256sum $DOWNLOADS_DIR/RealVul/datasets/dataset_without_src.7z | cut -d' ' -f1)",
        "extracted": ["Real_Vul_data.csv"]
      },
      "all_source_code.tar.xz": {
        "url": "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz",
        "sha256": "$(sha256sum $DOWNLOADS_DIR/RealVul/datasets/all_source_code.tar.xz | cut -d' ' -f1)",
        "extracted": ["all_source_code"]
      }
    },
    "LineVul": {
      "12heads_linevul_model.bin": {
        "url": "https://drive.google.com/uc?id=1oodyQqRb9jEcvLMVVKILmu8qHyNwd-zH",
        "sha256": "$(sha256sum $DOWNLOADS_DIR/LineVul/models/checkpoint-best-f1/12heads_linevul_model.bin | cut -d' ' -f1)",
        "type": "model"
      }
    }
  }
}
EOF

echo "✅ datasets.lock.json 업데이트 완료!"
echo ""
echo "다음 단계:"
echo "  1. docker compose down linevul"
echo "  2. docker compose up -d linevul"
echo "  3. bats ./docker/linevul/test_container.bats"
