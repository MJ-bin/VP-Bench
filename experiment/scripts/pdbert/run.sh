#!/bin/bash

# =============================================================================
# PDBERT 실험 실행 스크립트
# - 데이터 다운로드는 prepare.sh에서 이미 완료됨
# - 이 스크립트는 데이터 전처리, 학습, 평가만 수행
# =============================================================================

# Arguments
TRAIN_DATASET="realvul/jasper"
TEST_DATASET="realvul_test/jasper"

echo "=== PDBERT 실험 시작 ==="
echo "학습 데이터셋: $TRAIN_DATASET"
echo "테스트 데이터셋: $TEST_DATASET"

# -----------------------------------------------------------------------------
# 1. 테스트 데이터셋 준비 (VP-Bench_Test_Dataset)
# -----------------------------------------------------------------------------
echo ""
echo "[1/5] VP-Bench 테스트 데이터셋 준비..."

docker exec pdbert bash -c '
    TEST_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/realvul_test"
    
    if [ -f "$TEST_DIR/jasper_dataset.csv" ]; then
        echo "  - 테스트 데이터셋 이미 존재 (스킵)"
    else
        echo "  - 테스트 데이터셋 다운로드 및 압축 해제..."
        mkdir -p "$TEST_DIR"
        cd "$TEST_DIR"
        curl -L --progress-bar "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv" -o jasper_dataset.csv
        curl -L --progress-bar "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz" -o jasper_source_code.tar.gz
        tar -xf jasper_source_code.tar.gz
        echo "  - 테스트 데이터셋 준비 완료"
    fi
'

# -----------------------------------------------------------------------------
# 2. 데이터셋 전처리
# -----------------------------------------------------------------------------
echo ""
echo "[2/5] 데이터셋 전처리..."

echo "  - 학습 데이터셋 전처리: $TRAIN_DATASET"
docker exec pdbert python /PDBERT/prepare_dataset.py --path "$TRAIN_DATASET"

echo "  - 테스트 데이터셋 전처리: $TEST_DATASET"
docker exec pdbert python /PDBERT/prepare_dataset.py --path "$TEST_DATASET"

# -----------------------------------------------------------------------------
# 3. Config 파일 생성
# -----------------------------------------------------------------------------
echo ""
echo "[3/5] Config 파일 생성..."

docker exec pdbert bash -c '
    CONFIG_DIR="/PDBERT/downstream/configs/vul_detect"
    BASE_CONFIG="$CONFIG_DIR/pdbert_reveal.jsonnet"
    
    # 학습용 config
    cp "$BASE_CONFIG" "$CONFIG_DIR/pdbert_realvul.jsonnet"
    sed -i "s|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul/|g" "$CONFIG_DIR/pdbert_realvul.jsonnet"
    echo "  - pdbert_realvul.jsonnet 생성 완료"
    
    # 테스트용 config
    cp "$BASE_CONFIG" "$CONFIG_DIR/pdbert_realvul_test.jsonnet"
    sed -i "s|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul_test/|g" "$CONFIG_DIR/pdbert_realvul_test.jsonnet"
    echo "  - pdbert_realvul_test.jsonnet 생성 완료"
'

# -----------------------------------------------------------------------------
# 4. 모델 학습
# -----------------------------------------------------------------------------
echo ""
echo "[4/5] PDBERT 모델 학습..."

docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py \
    -config configs/vul_detect/pdbert_realvul.jsonnet \
    -task_name vul_detect/realvul \
    -model_path vul_detect/realvul \
    -average binary \
    --train-only"

# -----------------------------------------------------------------------------
# 5. 모델 평가
# -----------------------------------------------------------------------------
echo ""
echo "[5/5] PDBERT 모델 평가..."

docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py \
    -config configs/vul_detect/pdbert_realvul_test.jsonnet \
    -task_name vul_detect/realvul_test \
    -model_path vul_detect/realvul \
    -average binary \
    --test-only"

echo ""
echo "=== PDBERT 실험 완료 ==="
