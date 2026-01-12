#!/bin/bash
# 1. Jasper 데이터셋 전처리 - processed_func 열 추가
docker exec linevul python /app/RealVul/Experiments/LineVul/append_processed_func.py \
                        --csv_path /app/RealVul/Dataset/jasper_dataset.csv \
                        --src_path /app/RealVul/Dataset/source_code

# 2. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)
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

# 3. Jasper 데이터셋으로 학습 (--train)
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

# 4. VP-Bench 테스트 데이터셋 전처리
docker exec linevul python /app/RealVul/Experiments/LineVul/append_processed_func.py \
                        --csv_path /app/RealVul/Dataset/test/jasper_dataset.csv \
                        --src_path /app/RealVul/Dataset/test/source_code

# 5. VP-Bench 테스트 데이터셋의 pickle 생성 (--prepare_dataset)
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

# 6. VP-Bench 테스트 데이터셋으로 테스트 (--test_predict)
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
