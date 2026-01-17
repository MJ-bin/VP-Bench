#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads/vuddy"

echo "=== Vuddy 데이터 준비 스크립트 ==="

# VP-Bench 테스트 데이터셋 다운로드 및 압축 해제
echo "[1/2] VP-Bench 테스트 데이터셋 다운로드 및 압축 해제..."
PROJECT_NAME="jasper"
DS_NAME="VP-Bench_Test_Dataset"
INPUT_DIR="${DOWNLOADS_DIR}/${DS_NAME}/${PROJECT_NAME}"
mkdir -p "${INPUT_DIR}"

if [ ! -f "${INPUT_DIR}/${PROJECT_NAME}_dataset.csv" ]; then
    echo "  - ${PROJECT_NAME}_dataset.csv 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/${DS_NAME}/${PROJECT_NAME}_dataset.csv -P "${INPUT_DIR}"
else
    echo "  - ${PROJECT_NAME}_dataset.csv 이미 존재 (스킵)"
fi

if [ ! -f "${INPUT_DIR}/${PROJECT_NAME}_source_code.tar.gz" ]; then
    echo "  - ${PROJECT_NAME}_source_code.tar.gz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/${DS_NAME}/${PROJECT_NAME}_source_code.tar.gz -P "${INPUT_DIR}"
else
    echo "  - ${PROJECT_NAME}_source_code.tar.gz 이미 존재 (스킵)"
fi

# 압축 해제 (매번 실행하여 최신 상태 유지)
echo "  - ${PROJECT_NAME}_source_code.tar.gz 압축 해제 중..."
rm -rf "${INPUT_DIR}/source_code"
tar -xf "${INPUT_DIR}/${PROJECT_NAME}_source_code.tar.gz" -C "${INPUT_DIR}"
echo "  - 압축 해제 완료"

echo "✅ VP-Bench 테스트 데이터셋 준비 완료!"

# RealVul 데이터셋 다운로드 및 압축 해제
echo ""
echo "[2/2] RealVul 데이터셋 다운로드 및 압축 해제..."
DS_NAME="RealVul_Dataset"
INPUT_DIR="${DOWNLOADS_DIR}/${DS_NAME}/${PROJECT_NAME}"
mkdir -p "${INPUT_DIR}"

if [ ! -f "${INPUT_DIR}/${PROJECT_NAME}_dataset.csv" ]; then
    echo "  - ${PROJECT_NAME}_dataset.csv 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/${DS_NAME}/${PROJECT_NAME}_dataset.csv -P "${INPUT_DIR}"
else
    echo "  - ${PROJECT_NAME}_dataset.csv 이미 존재 (스킵)"
fi

if [ ! -f "${INPUT_DIR}/${PROJECT_NAME}_source_code.tar.gz" ]; then
    echo "  - ${PROJECT_NAME}_source_code.tar.gz 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/${DS_NAME}/${PROJECT_NAME}_source_code.tar.gz -P "${INPUT_DIR}"
else
    echo "  - ${PROJECT_NAME}_source_code.tar.gz 이미 존재 (스킵)"
fi

# 압축 해제 (매번 실행하여 최신 상태 유지)
echo "  - ${PROJECT_NAME}_source_code.tar.gz 압축 해제 중..."
rm -rf "${INPUT_DIR}/source_code"
tar -xf "${INPUT_DIR}/${PROJECT_NAME}_source_code.tar.gz" -C "${INPUT_DIR}"
echo "  - 압축 해제 완료"

echo "✅ RealVul 데이터셋 준비 완료!"

echo ""
echo "=========================================="
echo "✅ 모든 데이터 준비 완료!"
echo "=========================================="