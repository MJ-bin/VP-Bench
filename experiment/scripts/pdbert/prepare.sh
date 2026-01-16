#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"

# 프로젝트 루트 디렉토리 저장 (검증 단계에서 사용)
PROJECT_ROOT="$(pwd)"

echo "=== PDBERT 데이터 준비 스크립트 ==="

# 디렉토리 구조 생성
echo "[1/10] 디렉토리 구조 생성..."
mkdir -p "$DOWNLOADS_DIR/PDBERT"
mkdir -p "$DOWNLOADS_DIR/PDBERT/pretrain/microsoft"
mkdir -p "$DOWNLOADS_DIR/PDBERT/downstream/microsoft"
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets"

# ===================================================================
# PDBERT_data.zip 다운로드 (pdbert-base 모델 + 데이터셋 포함, 약 1.1GB)
# ===================================================================
echo "[2/10] PDBERT_data.zip 다운로드..."
cd "$DOWNLOADS_DIR/PDBERT"

if [ -d "data/models/pdbert-base" ]; then
    echo "  - pdbert-base 이미 존재 (스킵)"
elif [ -f "PDBERT_data.zip" ]; then
    FILE_SIZE=$(stat -c%s "PDBERT_data.zip" 2>/dev/null || stat -f%z "PDBERT_data.zip" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 1000000000 ]; then
        echo "  - PDBERT_data.zip 이미 다운로드됨 (size: $FILE_SIZE bytes)"
    else
        echo "  - PDBERT_data.zip 파일 크기가 작음, 재다운로드..."
        rm -f PDBERT_data.zip
        wget -nc https://github.com/MJ-bin/PDBERT/releases/download/v0.1.0/PDBERT_data.zip
    fi
else
    echo "  - PDBERT_data.zip 다운로드 중 (약 1.1GB)..."
    wget -nc https://github.com/MJ-bin/PDBERT/releases/download/v0.1.0/PDBERT_data.zip
fi

# PDBERT_data.zip 압축 해제
echo "[3/10] PDBERT_data.zip 압축 해제..."
if [ -d "data/models/pdbert-base" ]; then
    echo "  - pdbert-base 이미 존재 (스킵)"
else
    if [ -f "PDBERT_data.zip" ]; then
        echo "  - 압축 해제 중 (시간이 다소 소요될 수 있습니다)..."
        7z x PDBERT_data.zip -y
        mkdir -p ./data
        cp -r PDBERT_data/data/* ./data/
        rm -rf PDBERT_data
        echo "  - 압축 해제 완료"
    else
        echo "  - [ERROR] PDBERT_data.zip 파일을 찾을 수 없습니다"
        exit 1
    fi
fi

# ===================================================================
# RealVul 데이터셋 다운로드
# ===================================================================
echo "[4/10] RealVul 소스코드 다운로드..."
cd - > /dev/null
cd "$DOWNLOADS_DIR/RealVul/datasets"

if [ -d "all_source_code" ]; then
    echo "  - all_source_code 이미 존재 (스킵)"
elif [ -f "all_source_code.tar.xz" ]; then
    echo "  - all_source_code.tar.xz 이미 다운로드됨"
else
    echo "  - all_source_code.tar.xz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz
fi

echo "[5/10] RealVul 소스코드 압축 해제..."
if [ -d "all_source_code" ]; then
    echo "  - all_source_code 이미 압축 해제됨 (스킵)"
else
    if [ -f "all_source_code.tar.xz" ]; then
        echo "  - 압축 해제 중..."
        tar -xf all_source_code.tar.xz
        echo "  - 압축 해제 완료"
    else
        echo "  - [ERROR] all_source_code.tar.xz 파일을 찾을 수 없습니다"
        exit 1
    fi
fi

echo "[6/10] RealVul CSV 데이터셋 다운로드..."
if [ -f "Real_Vul_data.csv" ]; then
    echo "  - Real_Vul_data.csv 이미 존재 (스킵)"
elif [ -f "dataset_without_src.7z" ]; then
    echo "  - dataset_without_src.7z 이미 다운로드됨"
else
    echo "  - dataset_without_src.7z 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z
fi

echo "[7/10] RealVul CSV 데이터셋 압축 해제..."
if [ -f "Real_Vul_data.csv" ]; then
    echo "  - Real_Vul_data.csv 이미 압축 해제됨 (스킵)"
else
    if [ -f "dataset_without_src.7z" ]; then
        echo "  - 압축 해제 중..."
        7z x dataset_without_src.7z -y
        echo "  - 압축 해제 완료"
    else
        echo "  - [ERROR] dataset_without_src.7z 파일을 찾을 수 없습니다"
        exit 1
    fi
fi

# ===================================================================
# CodeBERT 모델 다운로드 (pretrain & downstream)
# ===================================================================
echo "[8/10] CodeBERT pretrain 모델 다운로드..."
cd - > /dev/null
cd "$DOWNLOADS_DIR/PDBERT/pretrain/microsoft"

if [ -d "codebert-base" ]; then
    echo "  - codebert-base (pretrain) 이미 존재 (스킵)"
else
    echo "  - codebert-base 클론 중..."
    git lfs install
    git clone https://huggingface.co/microsoft/codebert-base codebert-base
    echo "  - codebert-base (pretrain) 다운로드 완료"
fi

echo "[9/10] CodeBERT downstream 모델 다운로드..."
cd - > /dev/null
cd "$DOWNLOADS_DIR/PDBERT/downstream/microsoft"

if [ -d "codebert-base" ]; then
    echo "  - codebert-base (downstream) 이미 존재 (스킵)"
else
    echo "  - codebert-base 클론 중..."
    git lfs install
    git clone https://huggingface.co/microsoft/codebert-base codebert-base
    echo "  - codebert-base (downstream) 다운로드 완료"
fi

# ===================================================================
# 파일 검증
# ===================================================================
echo "[10/10] 파일 검증..."
cd "$PROJECT_ROOT"

# PDBERT 데이터 검증
test -d "$DOWNLOADS_DIR/PDBERT/data/models/pdbert-base" || { echo "Error: pdbert-base 모델을 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/PDBERT/data/datasets/extrinsic/vul_detect/bigvul" || { echo "Error: bigvul 데이터셋을 찾을 수 없습니다"; exit 1; }

# RealVul 데이터 검증
test -d "$DOWNLOADS_DIR/RealVul/datasets/all_source_code" || { echo "Error: all_source_code 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/Real_Vul_data.csv" || { echo "Error: Real_Vul_data.csv를 찾을 수 없습니다"; exit 1; }

# CodeBERT 모델 검증
test -d "$DOWNLOADS_DIR/PDBERT/pretrain/microsoft/codebert-base" || { echo "Error: CodeBERT pretrain 모델을 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/PDBERT/downstream/microsoft/codebert-base" || { echo "Error: CodeBERT downstream 모델을 찾을 수 없습니다"; exit 1; }

echo "✅ 모든 파일 검증 완료!"

echo ""
echo "=========================================="
echo "✅ 모든 데이터 준비 완료!"
echo "=========================================="
echo ""
echo "데이터 위치:"
echo "  - PDBERT 모델: $DOWNLOADS_DIR/PDBERT/data/models/pdbert-base"
echo "  - PDBERT 데이터셋: $DOWNLOADS_DIR/PDBERT/data/datasets"
echo "  - RealVul 데이터셋: $DOWNLOADS_DIR/RealVul/datasets"
echo "  - CodeBERT (pretrain): $DOWNLOADS_DIR/PDBERT/pretrain/microsoft/codebert-base"
echo "  - CodeBERT (downstream): $DOWNLOADS_DIR/PDBERT/downstream/microsoft/codebert-base"
echo ""
echo "다음 단계:"
echo "  1. docker compose down pdbert"
echo "  2. docker compose up -d pdbert"
echo "  3. bats ./docker/pdbert/test_container.bats"
