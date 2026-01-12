#!/bin/bash
# 1. Jasper 데이터셋 압축 해제
docker exec linevul bash -c '
    SOURCE_PATH="/app/RealVul/Dataset/jasper_source_code.tar.gz"
    EXTRACTED_DIR="/app/RealVul/Dataset/source_code"
    
    if [ -d "$EXTRACTED_DIR" ]; then
        echo "[SKIP] 압축 해제된 디렉토리가 이미 존재합니다: $EXTRACTED_DIR"
    else
        echo "[INFO] Jasper 데이터셋 압축 해제 중..."
        mkdir -p /app/RealVul/Dataset
        tar -xf "$SOURCE_PATH" -C /app/RealVul/Dataset
        echo "[OK] Jasper 데이터셋 압축 해제 완료"
    fi
'

# 2. Jasper 데이터셋 전처리 - processed_func 열 추가
docker exec linevul python /app/RealVul/Experiments/LineVul/append_processed_func.py \
                        --csv_path /app/RealVul/Dataset/jasper_dataset.csv \
                        --src_path /app/RealVul/Dataset/source_code

# 3. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/jasper_dataset_append_processed_func.csv \
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
    --dataset_csv_path /app/RealVul/Dataset/jasper_dataset_append_processed_func.csv \
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

    if [ -f "$DATASET_PATH" ] && [ -f "$SOURCE_PATH" ]; then
        echo "[SKIP] 데이터셋 파일이 이미 존재합니다: $DATASET_PATH, $SOURCE_PATH"
    else
        echo "[INFO] VP-Bench Jasper 데이터셋 다운로드 시작..."
        mkdir -p /app/RealVul/Dataset/test
        wget https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv -O "$DATASET_PATH"
        wget https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz -O "$SOURCE_PATH"
        echo "[OK] VP-Bench Jasper 데이터셋 다운로드 완료: $DATASET_PATH, $SOURCE_PATH"
    fi
'

# 6. VP-Bench Jasper 데이터셋 압축 해제
docker exec linevul bash -c '
    SOURCE_PATH="/app/RealVul/Dataset/test/jasper_source_code.tar.gz"
    EXTRACTED_DIR="/app/RealVul/Dataset/test/source_code"
    
    if [ -d "$EXTRACTED_DIR" ]; then
        echo "[SKIP] 압축 해제된 디렉토리가 이미 존재합니다: $EXTRACTED_DIR"
    else
        echo "[INFO] VP-Bench Jasper 데이터셋 압축 해제 중..."
        mkdir -p /app/RealVul/Dataset/test
        tar -xf "$SOURCE_PATH" -C /app/RealVul/Dataset/test
        echo "[OK] VP-Bench Jasper 데이터셋 압축 해제 완료"
    fi
'

# 7. VP-Bench Jasper 데이터셋 전처리
docker exec linevul python /app/RealVul/Experiments/LineVul/append_processed_func.py \
                        --csv_path /app/RealVul/Dataset/test/jasper_dataset.csv \
                        --src_path /app/RealVul/Dataset/test/source_code

# 8. VP-Bench Jasper 데이터셋의 pickle 생성 (--prepare_dataset)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/test/jasper_dataset_append_processed_func.csv \
    --dataset_path /app/RealVul/Dataset/test/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --prepare_dataset

# 9. VP-Bench Jasper 데이터셋으로 테스트 (--test_predict)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/test/jasper_dataset_append_processed_func.csv \
    --dataset_path /app/RealVul/Dataset/test/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --test_predict
