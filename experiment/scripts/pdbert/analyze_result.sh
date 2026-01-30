#!/bin/bash

# =============================================================================
# PDBERT 모델 분석 스크립트
# 독립적으로 모델을 테스트하여 Confusion Matrix 분석 및 FN/FP 샘플 추출
# 본 스크립트는 모델 학습, 테스트가 종료된후 실행합니다.
# =============================================================================

set -e

# 분석 스크립트 경로(호스트 경로)
SCRIPT_DIR="experiment/scripts/pdbert"
ANALYSIS_SCRIPT="$SCRIPT_DIR/analyze_prediction.py"

# Arguments(도커 container 내부경로: run.sh와 동일한 경로 사용)
TEST_DATASET_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/vpbench/Real_Vul"
MODEL_OUTPUT_DIR="/PDBERT/data/models/extrinsic/vul_detect/realvul"

echo "=== PDBERT 모델 세부분석 시작 ==="
echo ""
echo "테스트 데이터: $TEST_DATASET_DIR"
echo "모델 경로: $MODEL_OUTPUT_DIR"
echo "분석 스크립트: $ANALYSIS_SCRIPT"
echo ""

# -----------------------------------------------------------------------------
# 1. 분석 스크립트를 Docker 컨테이너로 복사
# -----------------------------------------------------------------------------
echo "[1/2] 분석 스크립트 복사 중..."

docker cp "$ANALYSIS_SCRIPT" pdbert:/PDBERT/analyze_prediction.py
echo "  - 복사 완료: /PDBERT/analyze_prediction.py"

# -----------------------------------------------------------------------------
# 2. 정밀 분석 수행
# -----------------------------------------------------------------------------
echo ""
echo "[2/2] 정밀 분석 수행 (FN/FP 샘플 추출)..."
echo ""

time docker exec pdbert bash -c "
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256
    cd /PDBERT/downstream && python /PDBERT/analyze_prediction.py \
        --data-path $TEST_DATASET_DIR \
        --model-dir $MODEL_OUTPUT_DIR \
        --batch-size 32 \
        --cuda 0"

echo ""
echo "=== PDBERT 모델 분석 완료 ==="
echo ""
echo "분석 결과 파일 위치:"
echo "  - Docker 내부: $MODEL_OUTPUT_DIR/prediction_analysis.json"
echo "  - 로컬 (마운트): downloads/PDBERT/data/models/extrinsic/vul_detect/realvul/prediction_analysis.json"
