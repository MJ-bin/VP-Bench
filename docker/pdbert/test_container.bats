#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: pdbert" >&3
}

# -------------------------------------------------------------------
# Test 0: 데이터셋 및 모델 다운로드 (없을 경우에만, 순차 실행)
# -------------------------------------------------------------------

@test "0a. PDBERT_data 다운로드" {
    # run 없이 직접 실행 (긴 다운로드 작업에서 타임아웃 방지)
    docker exec pdbert bash -c '
        cd /PDBERT
        # pdbert-base 모델이 없으면 다운로드
        if [ ! -d "/PDBERT/data/models/pdbert-base" ]; then
            echo "[INFO] Downloading PDBERT_data.zip (약 1.1GB, 시간이 걸립니다)..."
            curl -L --progress-bar "https://github.com/MJ-bin/PDBERT/releases/download/v0.1.0/PDBERT_data.zip" -o PDBERT_data.zip
            
            # 다운로드 완료 확인 (파일 크기 1GB 이상이어야 함)
            FILE_SIZE=$(stat -c%s "PDBERT_data.zip" 2>/dev/null || echo "0")
            if [ "$FILE_SIZE" -lt 1000000000 ]; then
                echo "[ERROR] Download failed or incomplete. File size: $FILE_SIZE bytes"
                rm -f PDBERT_data.zip
                exit 1
            fi
            echo "[INFO] Download complete. File size: $FILE_SIZE bytes"
            
            sync
            
            echo "[INFO] Extracting PDBERT_data.zip..."
            7z x PDBERT_data.zip
            
            mkdir -p ./data
            cp -r PDBERT_data/data/* ./data/
            rm -rf PDBERT_data PDBERT_data.zip
            echo "[INFO] PDBERT_data download complete"
        else
            echo "[INFO] PDBERT_data already exists, skipping download"
        fi
    ' >&3 2>&3
    
    # 결과 확인 (pdbert-base 모델 존재 여부)
    docker exec pdbert test -d /PDBERT/data/models/pdbert-base
}

@test "0b. RealVul 데이터셋 다운로드" {
    docker exec pdbert bash -c '
        cd /PDBERT
        if [ ! -d "/PDBERT/data/datasets/extrinsic/vul_detect/realvul/all_source_code" ]; then
            echo "[INFO] Downloading RealVul dataset..."
            mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul
            curl -L --progress-bar "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz" -o all_source_code.tar.xz
            tar -xvf all_source_code.tar.xz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul
            rm -rf all_source_code.tar.xz
            curl -L --progress-bar "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z" -o dataset_without_src.7z
            7z x dataset_without_src.7z -o/PDBERT/data/datasets/extrinsic/vul_detect/realvul -y
            rm -f dataset_without_src.7z
            echo "[INFO] RealVul dataset download complete"
        else
            echo "[INFO] RealVul dataset already exists, skipping download"
        fi
    ' >&3 2>&3
    
    docker exec pdbert test -d /PDBERT/data/datasets/extrinsic/vul_detect/realvul/all_source_code
}

@test "0c. CodeBERT 모델 다운로드" {
    docker exec pdbert bash -c '
        cd /PDBERT
        if [ ! -d "/PDBERT/pretrain/microsoft/codebert-base" ]; then
            echo "[INFO] Downloading CodeBERT model..."
            git lfs install
            git clone https://huggingface.co/microsoft/codebert-base pretrain/microsoft/codebert-base
            git clone https://huggingface.co/microsoft/codebert-base downstream/microsoft/codebert-base
            echo "[INFO] CodeBERT model download complete"
        else
            echo "[INFO] CodeBERT model already exists, skipping download"
        fi
    ' >&3 2>&3
    
    docker exec pdbert test -d /PDBERT/pretrain/microsoft/codebert-base
}

# -------------------------------------------------------------------
# Test bats: bigvul 데이터셋에서 샘플을 추출하여 빠른 테스트 수행
# -------------------------------------------------------------------

@test "1. test_bats 데이터셋 생성 (bigvul에서 샘플 추출)" {
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
        
        echo "[INFO] Creating test_bats dataset from bigvul..."
        
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
        
        echo "[INFO] test_bats dataset created successfully"
    '
    
    echo "# test_bats dataset creation output:" >&3
    echo "$output" >&3
    
    if [ "$status" -ne 0 ]; then
        echo "[ERROR] Dataset creation failed with status $status" >&3
    fi
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_bats dataset created successfully"* ]]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/train.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/validate.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/test.json
    [ "$status" -eq 0 ]
}


@test "2. test_bats용 jsonnet 설정 파일 생성" {
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
    
    echo "# jsonnet config creation output:" >&3
    echo "$output" >&3
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created config:"* ]]
    
    run docker exec pdbert test -f /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    [ "$status" -eq 0 ]
    
    run docker exec pdbert grep -q "test_bats" /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    [ "$status" -eq 0 ]
}


@test "3. PDBERT 학습 및 평가 (test_bats 데이터셋)" {
    run docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_test_bats.jsonnet -task_name vul_detect/test_bats -model_path vul_detect/test_bats -average binary"
    echo "# PDBERT training output (test_bats):" >&3
    echo "$output" >&3
    
    if [ "$status" -ne 0 ]; then
        echo "[ERROR] Training failed with status $status" >&3
    fi
    
    [ "$status" -eq 0 ]
    
    [[ "$output" == *"best_validation_f1"* ]]
    [[ "$output" == *"training_duration"* ]]
    [[ "$output" == *"Start to test File"* ]]
    [[ "$output" == *"Accuracy"* ]]
    [[ "$output" == *"F1-Score"* ]]
    [[ "$output" == *"Precision"* ]]
    [[ "$output" == *"Recall"* ]]
}
