#!/bin/bash

# =============================================================================
# PDBERT 실험 실행 스크립트
# =============================================================================

# Arguments
TRAIN_DATASET_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/realvul/Real_Vul"
TEST_DATASET_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/vpbench/Real_Vul"
MODEL_OUTPUT_DIR="/PDBERT/data/models/extrinsic/vul_detect"

echo "=== PDBERT 실험 시작 ==="

# -----------------------------------------------------------------------------
# 1. 데이터셋 전처리
# -----------------------------------------------------------------------------
echo ""
echo "[1/3] 데이터셋 전처리..."

echo "  - 학습 데이터셋 전처리: $TRAIN_DATASET_DIR"
time docker exec pdbert python /PDBERT/prepare_dataset.py \
    --path "$TRAIN_DATASET_DIR" \
    --output "$TRAIN_DATASET_DIR" \
    && echo "pdbert train dataset preprocessing done"

echo "  - 테스트 데이터셋 전처리: $TEST_DATASET_DIR"
time docker exec pdbert python /PDBERT/prepare_dataset.py \
    --path "$TEST_DATASET_DIR" \
    --output "$TEST_DATASET_DIR" \
    && echo "pdbert test dataset preprocessing done"

# -----------------------------------------------------------------------------
# 2. 모델 학습
# -----------------------------------------------------------------------------
echo ""
echo "[2/3] PDBERT 모델 학습..."

time docker exec pdbert bash -c "
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256
    cd /PDBERT/downstream && python train_eval_from_config.py \
    -config configs/vul_detect/pdbert_realvul.jsonnet \
    -task_name vul_detect/realvul \
    -data_path $TRAIN_DATASET_DIR \
    -model_dir $MODEL_OUTPUT_DIR/realvul \
    -average binary \
    --train-only" \
    && echo "pdbert train done"

# -----------------------------------------------------------------------------
# 3. 모델 평가 (VP-Bench 테스트셋)
# -----------------------------------------------------------------------------
echo ""
echo "[3/3] PDBERT 모델 평가..."

time docker exec pdbert bash -c "
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256
    cd /PDBERT/downstream && python train_eval_from_config.py \
    -config configs/vul_detect/pdbert_vpbench.jsonnet \
    -task_name vul_detect/vpbench \
    -data_path $TEST_DATASET_DIR \
    -model_dir $MODEL_OUTPUT_DIR/realvul \
    -average binary \
    --test-only" \
    && echo "pdbert test done"

echo ""
echo "=== PDBERT 실험 완료 ==="
