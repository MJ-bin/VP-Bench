#!/bin/bash

# 0. PDBERT 데이터셋 및 모델 다운로드 (없을 경우에만)
docker exec pdbert bash -c '
    cd /PDBERT
    # PDBERT_data 다운로드 (pdbert-base 모델이 없으면 다운로드)
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
        
        sync  # 디스크에 완전히 기록 대기
        
        echo "[INFO] Extracting PDBERT_data.zip..."
        7z x PDBERT_data.zip
        
        mkdir -p ./data
        cp -r PDBERT_data/data/* ./data/
        rm -rf PDBERT_data PDBERT_data.zip
    else
        echo "[INFO] PDBERT_data already exists, skipping download"
    fi

    # RealVul 데이터셋 다운로드
    if [ ! -d "/PDBERT/data/datasets/extrinsic/vul_detect/realvul/all_source_code" ]; then
        echo "[INFO] Downloading RealVul dataset..."
        mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul && \
        curl -L "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz" -o all_source_code.tar.xz && \
        tar -xvf all_source_code.tar.xz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul && \
        rm -rf all_source_code.tar.xz && \
        curl -L "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z" -o dataset_without_src.7z && \
        7z x dataset_without_src.7z -o/PDBERT/data/datasets/extrinsic/vul_detect/realvul -y && \
        rm -f dataset_without_src.7z
    else
        echo "[INFO] RealVul dataset already exists, skipping download"
    fi

    # CodeBERT 모델 다운로드
    if [ ! -d "/PDBERT/pretrain/microsoft/codebert-base" ]; then
        echo "[INFO] Downloading CodeBERT model..."
        git lfs install && \
        git clone https://huggingface.co/microsoft/codebert-base pretrain/microsoft/codebert-base && \
        git clone https://huggingface.co/microsoft/codebert-base downstream/microsoft/codebert-base
    else
        echo "[INFO] CodeBERT model already exists, skipping download"
    fi
'

# 1. 테스트 데이터셋 다운로드 (없을 경우에만)
docker exec pdbert bash -c '
    if [ ! -f "/PDBERT/data/datasets/extrinsic/vul_detect/realvul_test/jasper_dataset.csv" ]; then
        echo "[INFO] Downloading jasper test dataset..."
        mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
        curl -L "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv" -o jasper_dataset.csv && \
        mv jasper_dataset.csv /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
        curl -L "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz" -o jasper_source_code.tar.gz && \
        tar -xvf jasper_source_code.tar.gz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
        mv jasper_source_code.tar.gz /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test
    else
        echo "[INFO] Jasper test dataset already exists, skipping download"
    fi
'

# 2. 데이터셋 전처리
docker exec pdbert python /PDBERT/prepare_dataset.py --path realvul/jasper
docker exec pdbert python /PDBERT/prepare_dataset.py --path realvul_test/jasper

# 3. Config 파일 생성 (pdbert_realvul.jsonnet, pdbert_realvul_test.jsonnet)
docker exec pdbert bash -c "cp /PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet && \
    sed -i 's|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul/|g' /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet && \
    cp /PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet /PDBERT/downstream/configs/vul_detect/pdbert_realvul_test.jsonnet && \
    sed -i 's|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul_test/|g' /PDBERT/downstream/configs/vul_detect/pdbert_realvul_test.jsonnet"

# 4. 모델 학습
docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul.jsonnet -task_name vul_detect/realvul -model_path vul_detect/realvul -average binary --train-only"

# 5. 모델 평가
docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul_test.jsonnet -task_name vul_detect/realvul_test -model_path vul_detect/realvul -average binary --test-only"
