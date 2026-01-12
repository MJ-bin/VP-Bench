#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"

echo "=== LineVul 데이터 준비 스크립트 ==="

# 디렉토리 구조 생성
echo "[1/9] 디렉토리 구조 생성..."
mkdir -p "$DOWNLOADS_DIR/LineVul/models"
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets"

# RealVul 공통 데이터셋 (이미 존재하면 스킵)
echo "[2/9] RealVul 데이터셋 다운로드..."
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
echo "[3/9] RealVul 데이터셋 압축 해제..."
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
echo "[4/9] LineVul 모델 다운로드..."
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

# Jasper 데이터셋 압축 해제 (호스트)
echo ""
echo "[5/9] Jasper 데이터셋 압축 해제 (호스트)..."
cd - > /dev/null
cd "$DOWNLOADS_DIR/RealVul/datasets"

if [ -f "jasper_source_code.tar.gz" ]; then
    rm -rf source_code  # 기존 폴더 제거
    tar -xf jasper_source_code.tar.gz
    echo "  - jasper_source_code.tar.gz 압축 해제 완료"
else
    echo "  - jasper_source_code.tar.gz 파일을 찾을 수 없습니다"
fi

# VP-Bench 테스트 데이터셋 다운로드
echo "[6/9] VP-Bench 테스트 데이터셋 다운로드..."
mkdir -p test
cd test

if [ ! -f "jasper_dataset.csv" ]; then
    echo "  - jasper_dataset.csv 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv
else
    echo "  - jasper_dataset.csv 이미 존재 (스킵)"
fi

if [ ! -f "jasper_source_code.tar.gz" ]; then
    echo "  - jasper_source_code.tar.gz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz
else
    echo "  - jasper_source_code.tar.gz 이미 존재 (스킵)"
fi

# VP-Bench 테스트 데이터셋 압축 해제 (호스트)
echo "[7/9] VP-Bench 테스트 데이터셋 압축 해제 (호스트)..."
if [ -f "jasper_source_code.tar.gz" ]; then
    rm -rf source_code  # 기존 폴더 제거
    tar -xf jasper_source_code.tar.gz
    echo "  - jasper_source_code.tar.gz 압축 해제 완료"
else
    echo "  - jasper_source_code.tar.gz 파일을 찾을 수 없습니다"
fi

echo "✅ VP-Bench 테스트 데이터셋 다운로드 및 압축 해제 완료!"

# 파일 검증 (모든 데이터 준비 후, lock 파일 생성 이전)
echo ""
echo "[8/9] 파일 검증..."
cd - > /dev/null
cd ../../../

test -f "$DOWNLOADS_DIR/RealVul/datasets/Real_Vul_data.csv" || { echo "Error: Real_Vul_data.csv를 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/RealVul/datasets/all_source_code" || { echo "Error: all_source_code 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/LineVul/models/checkpoint-best-f1/12heads_linevul_model.bin" || { echo "Error: 모델 파일을 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/jasper_dataset.csv" || { echo "Error: jasper_dataset.csv를 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/RealVul/datasets/source_code" || { echo "Error: Jasper source_code 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "$DOWNLOADS_DIR/RealVul/datasets/test/jasper_dataset.csv" || { echo "Error: VP-Bench jasper_dataset.csv를 찾을 수 없습니다"; exit 1; }
test -d "$DOWNLOADS_DIR/RealVul/datasets/test/source_code" || { echo "Error: VP-Bench source_code 디렉토리를 찾을 수 없습니다"; exit 1; }

echo "✅ 모든 파일 검증 완료!"

# TODO: datasets.lock.json 생성 기능 추가 예정
# - 다운로드한 모든 파일의 메타데이터(URL, SHA256) 기록
# - 데이터 무결성 검증 및 버전 관리용

echo ""
echo "=========================================="
echo "✅ 모든 데이터 준비 완료!"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "  1. docker compose down linevul"
echo "  2. docker compose up -d linevul"
echo "  3. bats ./docker/linevul/test_container.bats"
