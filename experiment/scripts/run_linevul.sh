#!/bin/bash

# 0. LineVul 모델 및 데이터셋 다운로드 (없을 경우에만)
docker exec linevul bash -c '
    MODEL_PATH="/app/RealVul/LineVul/linevul/saved_models/checkpoint-best-f1/12heads_linevul_model.bin"
    
    if [ -f "$MODEL_PATH" ]; then
        echo "[SKIP] 모델 파일이 이미 존재합니다: $MODEL_PATH"
    else
        echo "[INFO] LineVul 모델 다운로드 시작..."
        mkdir -p "$(dirname "$MODEL_PATH")"
        gdown --fuzzy "https://drive.google.com/uc?id=1oodyQqRb9jEcvLMVVKILmu8qHyNwd-zH" -O "$MODEL_PATH"
        echo "[OK] 모델 다운로드 완료: $MODEL_PATH"
    fi

    # RealVul 데이터셋 다운로드
    ARCHIVE_1="/app/RealVul/Dataset/dataset_without_src.7z"
    ARCHIVE_2="/app/RealVul/Dataset/all_source_code.tar.xz"

    if [ -f "$ARCHIVE_1" ] && [ -f "$ARCHIVE_2" ]; then
        echo "[SKIP] RealVul 데이터셋 파일이 이미 다운로드되어 있습니다."
    else
        echo "[INFO] RealVul 데이터셋 다운로드 시작..."
        mkdir -p /app/RealVul/Dataset/
        wget https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z -P /app/RealVul/Dataset/
        wget https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz -P /app/RealVul/Dataset/
    fi

    # RealVul 데이터셋 압축 해제
    echo "[INFO] RealVul 데이터셋 압축 해제 중..."
    7z x "$ARCHIVE_1" -y -o/app/RealVul/Dataset/
    tar -xvf "$ARCHIVE_2" -C /app/RealVul/Dataset/
'

# 1. 모델 파일 및 config.json 생성
docker exec linevul bash -c '
    MODEL_PATH="/app/RealVul/Experiments/LineVul/best_model/12heads_linevul_model.bin"
    PYTORCH_MODEL_PATH="/app/RealVul/Experiments/LineVul/best_model/pytorch_model.bin"
    CONFIG_PATH="/app/RealVul/Experiments/LineVul/best_model/config.json"
    
    echo "[INFO] best_model 디렉토리 설정..."
    mkdir -p /app/RealVul/Experiments/LineVul/best_model
    
    # 1. 모델 파일 복사 (이미 존재하면 스킵)
    if [ -f "$MODEL_PATH" ] && [ -f "$PYTORCH_MODEL_PATH" ]; then
        echo "[SKIP] 모델 파일이 이미 존재합니다."
    else
        echo "[INFO] 모델 파일 복사 중..."
        cp /app/RealVul/LineVul/linevul/saved_models/checkpoint-best-f1/12heads_linevul_model.bin "$MODEL_PATH"
        cp "$MODEL_PATH" "$PYTORCH_MODEL_PATH"
        echo "[OK] 모델 파일 복사 완료"
    fi
    
    # 2. config.json 생성 (이미 존재하면 스킵)
    if [ -f "$CONFIG_PATH" ]; then
        echo "[SKIP] config.json 파일이 이미 존재합니다."
    else
        echo "[INFO] HuggingFace config.json 생성 중..."
        python - <<PY
from transformers import RobertaConfig
config = RobertaConfig.from_pretrained("microsoft/codebert-base")
config.num_labels = 2
config.save_pretrained("/app/RealVul/Experiments/LineVul/best_model")
print("[OK] config.json 생성 완료")
PY
    fi
'

# 2. Jasper 데이터셋 전처리 - processed_func 열 추가
docker exec linevul python /app/RealVul/Experiments/LineVul/append_datasetjasper.py --path Dataset

# 3. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --prepare_dataset

# 4. Jasper 데이터셋으로 학습 (--train)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --train

# 5. VP-Bench Jasper 데이터셋 다운로드
docker exec linevul bash -c '
    DATASET_PATH="/app/RealVul/Dataset/test/jasper_dataset.csv"
    SOURCE_PATH="/app/RealVul/Dataset/test/jasper_source_code.tar.gz"

    if [ -f "$DATASET_PATH" && -f "$SOURCE_PATH" ]; then
        echo "[SKIP] 데이터셋 파일이 이미 존재합니다: $DATASET_PATH, $SOURCE_PATH"
    else
        echo "[INFO] VP-Bench Jasper 데이터셋 다운로드 시작..."
        mkdir -p /app/RealVul/Dataset/test
        gdown --fuzzy "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv" -O "$DATASET_PATH"
        gdown --fuzzy "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz" -O "$SOURCE_PATH"
        echo "[OK] VP-Bench Jasper 데이터셋 다운로드 완료: $DATASET_PATH, $SOURCE_PATH"
    fi
'

# 6. VP-Bench Jasper 데이터셋 압축 해제
docker exec linevul bash -c '
    SOURCE_PATH="/app/RealVul/Dataset/test/jasper_source_code.tar.gz"
    
    if [ -f "$SOURCE_PATH" ]; then
        echo "[SKIP] 데이터셋 파일이 이미 존재합니다: $SOURCE_PATH"
    else
        echo "[INFO] VP-Bench Jasper 데이터셋 압축 해제 중..."
        mkdir -p /app/RealVul/Dataset/test
        tar -xvf "$SOURCE_PATH" -C /app/RealVul/Dataset/test
        echo "[OK] VP-Bench Jasper 데이터셋 압축 해제 완료"
    fi
'

# 7. VP-Bench Jasper 데이터셋 전처리
docker exec linevul python /app/RealVul/Experiments/LineVul/append_datasetjasper.py --path Dataset/test

# 8. VP-Bench Jasper 데이터셋의 pickle 생성 (--prepare_dataset)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/test/jasper_dataset.csv \
    --dataset_path /app/RealVul/Dataset/test/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --prepare_dataset

# 9. VP-Bench Jasper 데이터셋으로 테스트 (--test_predict)
docker exec -it linevul-container python /app/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/Dataset/test/jasper_dataset.csv \
    --dataset_path /app/Dataset/test/ \
    --output_dir /app/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --test_predict

