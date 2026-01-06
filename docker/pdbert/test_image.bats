#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: pdbert" >&3
}

# -------------------------------------------------------------------
# Test bats: bigvul 데이터셋에서 샘플을 추출하여 빠른 테스트 수행
# -------------------------------------------------------------------

@test "1. test_bats 데이터셋 생성 (bigvul에서 샘플 추출)" {
    # bigvul 데이터셋에서 train/validate/test 각각 약 10개씩 랜덤 추출하여 test_bats 폴더 생성
    run docker exec pdbert bash -c '
        set -e
        
        SRC_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/bigvul"
        DST_DIR="/PDBERT/data/datasets/extrinsic/vul_detect/test_bats"
        
        # 소스 디렉토리 확인
        if [ ! -d "$SRC_DIR" ]; then
            echo "[ERROR] Source directory not found: $SRC_DIR"
            exit 1
        fi
        
        # 대상 디렉토리 생성 (이미 존재하면 삭제 후 재생성)
        rm -rf "$DST_DIR"
        mkdir -p "$DST_DIR"
        
        echo "[INFO] Creating test_bats dataset from bigvul..."
        
        # Python으로 각 JSON 파일에서 랜덤 샘플 추출
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
    
    # train은 10개, validate/test는 5개씩 추출
    sample_size = 10 if filename == "train.json" else 5
    sample_size = min(sample_size, len(data))
    
    sampled = random.sample(data, sample_size)
    
    with open(dst_path, "w") as f:
        json.dump(sampled, f, indent=4)
    
    print(f"[INFO] Created {dst_path}: {sample_size} samples from {len(data)}")

print("[INFO] Done!")
EOF
        
        echo "[INFO] test_bats dataset created successfully"
    '
    
    # 실행 결과 출력
    echo "# test_bats dataset creation output:" >&3
    echo "$output" >&3
    
    # 에러 시 상세 로그 출력
    if [ "$status" -ne 0 ]; then
        echo "[ERROR] Dataset creation failed with status $status" >&3
        echo "$output" >&3
    fi
    
    # 종료 코드 확인
    [ "$status" -eq 0 ]
    
    # 패턴 매칭
    [[ "$output" == *"test_bats dataset created successfully"* ]]
    
    # 파일 생성 확인
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/train.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/validate.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/test.json
    [ "$status" -eq 0 ]
    
    echo "# test_bats JSON files created successfully" >&3
}


@test "2. test_bats용 jsonnet 설정 파일 생성" {
    # pdbert_reveal.jsonnet을 복사하여 test_bats용 설정 파일 생성
    run docker exec pdbert bash -c '
        set -e
        
        SRC_CONFIG="/PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet"
        DST_CONFIG="/PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet"
        
        # 소스 설정 파일 확인
        if [ ! -f "$SRC_CONFIG" ]; then
            echo "[ERROR] Source config not found: $SRC_CONFIG"
            exit 1
        fi
        
        # 설정 파일 복사 및 경로 수정
        cp "$SRC_CONFIG" "$DST_CONFIG"
        sed -i "s|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/test_bats/|g" "$DST_CONFIG"
        
        echo "[INFO] Created config: $DST_CONFIG"
        echo "[INFO] Config file content (first 5 lines):"
        head -n 5 "$DST_CONFIG"
    '
    
    # 실행 결과 출력
    echo "# jsonnet config creation output:" >&3
    echo "$output" >&3
    
    # 에러 시 상세 로그 출력
    if [ "$status" -ne 0 ]; then
        echo "[ERROR] Config creation failed with status $status" >&3
        echo "$output" >&3
    fi
    
    # 종료 코드 확인
    [ "$status" -eq 0 ]
    
    # 패턴 매칭
    [[ "$output" == *"Created config:"* ]]
    [[ "$output" == *"pdbert_test_bats.jsonnet"* ]]
    
    # 설정 파일 존재 확인
    run docker exec pdbert test -f /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    [ "$status" -eq 0 ]
    
    # 설정 파일 내용에 test_bats 경로가 포함되어 있는지 확인
    run docker exec pdbert grep -q "test_bats" /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    [ "$status" -eq 0 ]
    
    echo "# jsonnet config created and verified successfully" >&3
}


@test "3. PDBERT 학습 및 평가 (test_bats 데이터셋)" {
    # test_bats 데이터셋으로 모델 학습 및 평가
    run docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_test_bats.jsonnet -task_name vul_detect/test_bats -average binary"

    # 실행 결과 출력
    echo "# PDBERT training output (test_bats):" >&3
    echo "$output" >&3
    
    # 에러 시 상세 로그 출력
    if [ "$status" -ne 0 ]; then
        echo "[ERROR] Training failed with status $status" >&3
        echo "Full output:" >&3
        echo "$output" >&3
    fi
    
    # 종료 코드 확인
    [ "$status" -eq 0 ]
    
    # 학습 완료 패턴 확인
    [[ "$output" == *"best_validation_f1"* ]]
    [[ "$output" == *"training_duration"* ]]
    
    # 테스트 실행 및 결과 패턴 확인
    [[ "$output" == *"Start to test File"* ]]
    [[ "$output" == *"Accuracy"* ]]
    [[ "$output" == *"F1-Score"* ]]
    [[ "$output" == *"Precision"* ]]
    [[ "$output" == *"Recall"* ]]
    
    echo "# Training and evaluation completed successfully (test_bats)" >&3
}
