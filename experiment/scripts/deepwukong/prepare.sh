#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"

echo "=== DeepWukong 데이터 준비 스크립트 ==="

# 디렉토리 구조 생성
echo "[1/7] 디렉토리 구조 생성..."
mkdir -p "$DOWNLOADS_DIR/DeepWukong/data"
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets"

# DeepWukong 모델 데이터 다운로드
echo "[2/7] DeepWukong Data.7z 다운로드..."
cd "$DOWNLOADS_DIR/DeepWukong/data"

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

# RealVul Jasper 데이터셋 다운로드 (압축 파일만 다운로드, 압축 해제는 pipeline에서)
echo "[5/7] RealVul Jasper 데이터셋 다운로드..."
cd - > /dev/null
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets/RealVul_Dataset"
cd "$DOWNLOADS_DIR/RealVul/datasets/RealVul_Dataset"

if [ ! -f "jasper_dataset.csv" ]; then
    echo "  - jasper_dataset.csv 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/jasper_dataset.csv
else
    echo "  - jasper_dataset.csv 이미 존재 (스킵)"
fi

if [ ! -f "jasper_source_code.tar.gz" ]; then
    echo "  - jasper_source_code.tar.gz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/jasper_source_code.tar.gz -O "jasper_source_code.tar.gz"
else
    echo "  - jasper_source_code.tar.gz 이미 존재 (스킵)"
fi


# VP-Bench 테스트 데이터셋 다운로드 (압축 파일만 다운로드, 압축 해제는 pipeline에서)
echo "[6/7] VP-Bench 테스트 데이터셋(Jasper) 다운로드..."
cd - > /dev/null && cd "$DOWNLOADS_DIR/RealVul/datasets"
mkdir -p VP-Bench_Test_Dataset
cd VP-Bench_Test_Dataset

if [ ! -f "jasper_dataset.csv" ]; then
    echo "  - jasper_dataset.csv 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv
else
    echo "  - jasper_dataset.csv 이미 존재 (스킵)"
fi

if [ ! -f "jasper_source_code.tar.gz" ]; then
    echo "  - jasper_source_code.tar.gz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz -O "jasper_source_code.tar.gz"
else
    echo "  - jasper_source_code.tar.gz 이미 존재 (스킵)"
fi

# 파일 검증
echo "[7/7] 파일 검증..."
cd - > /dev/null
cd ../../../
echo ${PWD}

test -d "$DOWNLOADS_DIR/DeepWukong/data/CWE119" || { echo "Error: CWE119 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/DeepWukong/data/DeepWukong" || { echo "Error: DeepWukong 모델 파일을 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/RealVul_Dataset/jasper_dataset.csv" || { echo "Error: RealVul jasper_dataset.csv를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/RealVul_Dataset/jasper_source_code.tar.gz" || { echo "Error: RealVul_Dataset-jasper_source_code.tar.gz를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Test_Dataset/jasper_dataset.csv" || { echo "Error: VP-Bench jasper_dataset.csv를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Test_Dataset/jasper_source_code.tar.gz" || { echo "Error: VP-Bench jasper_source_code.tar.gz를 찾을 수 없습니다"; exit 1; }

echo "✅ 모든 파일 검증 완료!"

echo ""
echo "=========================================="
echo "✅ 모든 데이터 준비 완료!"
echo "=========================================="
echo ""
echo "데이터 위치:"
echo "  - DeepWukong 모델: $DOWNLOADS_DIR/DeepWukong/data"
echo "  - RealVul Jasper 데이터: $DOWNLOADS_DIR/RealVul/datasets/RealVul_Dataset"
echo "  - VP-Bench Jasper 데이터: $DOWNLOADS_DIR/RealVul/datasets/VP-Bench_Test_Dataset"
