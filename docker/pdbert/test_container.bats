#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: pdbert" >&3
    if ! docker ps --format '{{.Names}}' | grep -q "^pdbert$"; then
        echo "# [ERROR] Container 'pdbert' is not running. Please run 'docker compose up -d pdbert' first." >&3
        return 1
    fi
}

# -------------------------------------------------------------------
# Test 1: 마운트된 데이터 존재 확인 (prepare.sh에서 미리 다운로드)
# -------------------------------------------------------------------

@test "1. PDBERT 실행 환경 설정 확인" {
    # pdbert-base 모델 존재 확인
    run docker exec pdbert test -d /PDBERT/data/models/pdbert-base
    [ "$status" -eq 0 ]
    
    # bigvul 데이터셋 존재 확인
    run docker exec pdbert test -d /PDBERT/data/datasets/extrinsic/vul_detect/bigvul
    [ "$status" -eq 0 ]
    
    # CodeBERT pretrain 모델 존재 확인
    run docker exec pdbert test -d /PDBERT/pretrain/microsoft/codebert-base
    [ "$status" -eq 0 ]
    
    # CodeBERT downstream 모델 존재 확인
    run docker exec pdbert test -d /PDBERT/downstream/microsoft/codebert-base
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/realvul/Real_Vul/Real_Vul_data.csv
    [ "$status" -eq 0 ]

    echo "# PDBERT environment is configured successfully" >&3
}

# -------------------------------------------------------------------
# Test 2: test_bats 데이터셋 생성 (bigvul에서 샘플 추출)
# -------------------------------------------------------------------

@test "2. test_bats 데이터셋 생성 (bigvul에서 샘플 추출)" {
    run docker exec pdbert bash -c '
        set -e
        
        SRC_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/bigvul"
        DST_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/test_bats"
        
        if [ ! -d "$SRC_DIR" ]; then
            echo "[ERROR] Source directory not found: $SRC_DIR"
            exit 1
        fi
        
        rm -rf "$DST_DIR"
        mkdir -p "$DST_DIR"
        
        echo "[INFO] Creating sample dataset from bigvul for test_bats"
        
        python3 << EOF
import json
import random
import os

random.seed(42)

src_dir = "$SRC_DIR"
dst_dir = "$DST_DIR"

for filename in ["train.json", "validate.json", "test.json"]:
    src_path = os.path.join(src_dir, filename)
    dst_path = os.path.join(dst_dir, filename)
    
    if not os.path.exists(src_path):
        print(f"[WARN] File not found: {src_path}")
        continue
    
    with open(src_path, "r") as f:
        data = json.load(f)
    
    sample_size = 10 if filename == "train.json" else 5
    sample_size = min(sample_size, len(data))
    
    sampled = random.sample(data, sample_size)
    
    with open(dst_path, "w") as f:
        json.dump(sampled, f, indent=4)
    
    print(f"[INFO] Created {dst_path}: {sample_size} samples from {len(data)}")

print("[INFO] Done!")
EOF
        
        echo "[INFO] sample dataset created successfully"
    '

    echo "# $output" >&3
    
    if [ "$status" -ne 0 ]; then
        echo "[ERROR] Dataset creation failed with status $status" >&3
    fi

    # 최종 확인 - test_bats 디렉토리의 파일들 존재 확인
    run docker exec pdbert bash -c '
        test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/train.json && \
        test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/validate.json && \
        test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/test.json
    '
    [ "$status" -eq 0 ]
}

# -------------------------------------------------------------------
# Test 3: test_bats용 jsonnet 설정 파일 생성
# -------------------------------------------------------------------

@test "3. test_bats용 jsonnet 설정 파일 생성" {
    run docker exec pdbert bash -c '
        set -e
        
        SRC_CONFIG="/PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet"
        DST_CONFIG="/PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet"
        
        if [ ! -f "$SRC_CONFIG" ]; then
            echo "[ERROR] Source config not found: $SRC_CONFIG"
            exit 1
        fi
        
        cp "$SRC_CONFIG" "$DST_CONFIG"
        sed -i "s|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/test_bats/|g" "$DST_CONFIG"
        
        echo "[INFO] Created config: $DST_CONFIG"
        head -n 5 "$DST_CONFIG"
    '

    echo "# $output" >&3

    # 최종 확인 - jsonnet 파일 존재 확인
    run docker exec pdbert bash -c '
        test -f /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    '
    [ "$status" -eq 0 ]
}

# -------------------------------------------------------------------
# Test 4: PDBERT 학습 및 평가 (test_bats 데이터셋)
# -------------------------------------------------------------------

# bats test_tags=timeout:1200
@test "4. PDBERT 학습 및 평가 (test_bats 데이터셋)" {
    run docker exec pdbert bash -c 'cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_test_bats.jsonnet -task_name vul_detect/test_bats -average binary --train-only'

    # 실행 실패 시 에러 출력
    if [ "$status" -ne 0 ]; then
        echo "# [ERROR] Training failed with status $status" >&3
        echo "# $output" >&3
    fi
    [ "$status" -eq 0 ]
    
    run docker exec pdbert bash -c 'cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_test_bats.jsonnet -task_name vul_detect/test_bats -average binary --test-only'

    # 실행 실패 시 에러 출력
    if [ "$status" -ne 0 ]; then
        echo "# [ERROR] Test failed with status $status" >&3
        echo "# $output" >&3
    fi
    [ "$status" -eq 0 ]

    # 최종 확인 - 학습 및 평가 결과로그 확인
    [[ "$output" == *"Start to test File"* ]]
    [[ "$output" == *"Accuracy"* ]]
    [[ "$output" == *"F1-Score"* ]]
    [[ "$output" == *"Precision"* ]]
    [[ "$output" == *"Recall"* ]]
}
