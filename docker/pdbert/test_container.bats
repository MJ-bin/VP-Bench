#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: pdbert" >&3
}

# -------------------------------------------------------------------
# Test 0: 데이터셋 및 모델 다운로드 (세분화된 단위로 실행)
# -------------------------------------------------------------------

# === 1~2: PDBERT_data (pdbert-base 모델 포함) ===

@test "1. PDBERT_data.zip 다운로드" {
    run docker exec pdbert bash -c '
        cd /PDBERT
        
        # 이미 설치후 압축해제까지 완료된 경우
        if [ -d "/PDBERT/data/models/pdbert-base" ]; then
            echo "[SKIP] pdbert-base already exists"
            exit 0
        fi
        
        # 이미 다운로드된 경우
        if [ -f "PDBERT_data.zip" ]; then
            echo "[SKIP] PDBERT_data.zip already downloaded"
            exit 0
        fi
        
        # 다운로드 실행
        echo "[INFO] Downloading PDBERT_data.zip (약 1.1GB)..."
        curl -L --progress-bar "https://github.com/MJ-bin/PDBERT/releases/download/v0.1.0/PDBERT_data.zip" -o PDBERT_data.zip
        
        # 다운로드 결과 확인
        if [ -f /PDBERT/PDBERT_data.zip ]; then
            echo "[OK] PDBERT_data.zip download complete"
        else
            echo "[ERROR] PDBERT_data.zip not found after download!"
            exit 1
        fi
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

@test "2. PDBERT_data 압축해제 및 설치" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -d "/PDBERT/data/models/pdbert-base" ]; then
            echo "[SKIP] pdbert-base already exists"
            exit 0
        fi

        echo "[INFO] Extracting PDBERT_data.zip..."
        7z x PDBERT_data.zip -y
        mkdir -p ./data
        cp -r PDBERT_data/data/* ./data/
        rm -rf PDBERT_data PDBERT_data.zip
        echo "[INFO] PDBERT_data installation complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

# === 3~6: RealVul 데이터셋 ===

@test "3. RealVul 소스코드 다운로드" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -d "/PDBERT/data/datasets/extrinsic/vul_detect/realvul/all_source_code" ]; then
            echo "[SKIP] RealVul source already exists"
            exit 0
        fi

        mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul
        echo "[INFO] Downloading all_source_code.tar.xz..."
        curl -L --progress-bar "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz" -o all_source_code.tar.xz
        echo "[INFO] Download complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

@test "4. RealVul 소스코드 압축해제" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -d "/PDBERT/data/datasets/extrinsic/vul_detect/realvul/all_source_code" ]; then
            echo "[SKIP] RealVul source already extracted"
            exit 0
        fi

        if [ ! -f "all_source_code.tar.xz" ]; then
            echo "[ERROR] all_source_code.tar.xz not found"
            exit 1
        fi

        echo "[INFO] Extracting all_source_code.tar.xz..."
        tar -xvf all_source_code.tar.xz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul
        rm -f all_source_code.tar.xz
        echo "[INFO] Extraction complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

@test "5. RealVul CSV 다운로드" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -f "/PDBERT/data/datasets/extrinsic/vul_detect/realvul/Real_Vul_data.csv" ]; then
            echo "[SKIP] RealVul CSV already exists"
            exit 0
        fi

        echo "[INFO] Downloading dataset_without_src.7z..."
        curl -L --progress-bar "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z" -o dataset_without_src.7z
        echo "[INFO] RealVul CSV Download complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

@test "6. RealVul CSV 압축해제" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -f "/PDBERT/data/datasets/extrinsic/vul_detect/realvul/Real_Vul_data.csv" ]; then
            echo "[SKIP] RealVul CSV already extracted"
            exit 0
        fi

        if [ ! -f "dataset_without_src.7z" ]; then
            echo "[ERROR] dataset_without_src.7z not found"
            exit 1
        fi

        echo "[INFO] Extracting dataset_without_src.7z..."
        7z x dataset_without_src.7z -o/PDBERT/data/datasets/extrinsic/vul_detect/realvul -y
        rm -f dataset_without_src.7z
        echo "[INFO] RealVul CSV Extraction complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

# === 7~8: CodeBERT 모델 ===

@test "7. CodeBERT pretrain 다운로드" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -d "/PDBERT/pretrain/microsoft/codebert-base" ]; then
            echo "[SKIP] CodeBERT pretrain already exists"
            exit 0
        fi

        echo "[INFO] Downloading CodeBERT pretrain..."
        git lfs install
        git clone https://huggingface.co/microsoft/codebert-base pretrain/microsoft/codebert-base
        echo "[INFO] CodeBERT pretrain Download complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

@test "8. CodeBERT downstream 다운로드" {
    run docker exec pdbert bash -c '
        cd /PDBERT

        if [ -d "/PDBERT/downstream/microsoft/codebert-base" ]; then
            echo "[SKIP] CodeBERT downstream already exists"
            exit 0
        fi

        echo "[INFO] Downloading CodeBERT downstream..."
        git lfs install
        git clone https://huggingface.co/microsoft/codebert-base downstream/microsoft/codebert-base
        echo "[INFO] CodeBERT downstream Download complete"
    '
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

# -------------------------------------------------------------------
# Test bats: bigvul 데이터셋에서 샘플을 추출하여 빠른 테스트 수행
# -------------------------------------------------------------------

@test "9. test_bats 데이터셋 생성 (bigvul에서 샘플 추출)" {
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
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"sample dataset created successfully"* ]]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/train.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/validate.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/test_bats/test.json
    [ "$status" -eq 0 ]
}


@test "10. test_bats용 jsonnet 설정 파일 생성" {
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
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created config:"* ]]
    
    run docker exec pdbert test -f /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    [ "$status" -eq 0 ]
    
    run docker exec pdbert grep -q "test_bats" /PDBERT/downstream/configs/vul_detect/pdbert_test_bats.jsonnet
    [ "$status" -eq 0 ]
}


@test "11. PDBERT 학습 및 평가 (test_bats 데이터셋)" {
    run docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_test_bats.jsonnet -task_name vul_detect/test_bats -model_path vul_detect/test_bats -average binary"
    
    # 실행 실패 시 에러 출력
    if [ "$status" -ne 0 ]; then
        echo "# [ERROR] Training failed with status $status" >&3
        echo "# $output" >&3
    fi
    [ "$status" -eq 0 ]
    
    # 핵심 결과만 출력
    echo "# === PDBERT Training & Evaluation Results ===" >&3
    echo "# [Training]" >&3
    echo "$output" | grep "best_validation_f1" | head -1 | sed 's/^/# /' >&3
    echo "$output" | grep "training_duration" | head -1 | sed 's/^/# /' >&3
    echo "# [Evaluation]" >&3
    echo "$output" | grep "{'Accuracy'" | head -1 | sed 's/^/# /' >&3
    
    # 모든 키워드가 있어야 성공
    [[ "$output" == *"best_validation_f1"* ]]
    [[ "$output" == *"training_duration"* ]]
    [[ "$output" == *"Start to test File"* ]]
    [[ "$output" == *"Accuracy"* ]]
    [[ "$output" == *"F1-Score"* ]]
    [[ "$output" == *"Precision"* ]]
    [[ "$output" == *"Recall"* ]]
}
