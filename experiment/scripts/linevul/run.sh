#!/bin/bash
# 1. train_val + test 병합
docker exec linevul bash -c "cat /app/RealVul/Dataset/VP-Bench_Train_Dataset/Real_Vul_data.csv > /app/RealVul/Dataset/Real_Vul_data.csv && tail -n +2 /app/RealVul/Dataset/VP-Bench_Test_Dataset/Real_Vul_data.csv >> /app/RealVul/Dataset/Real_Vul_data.csv"

# 2. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/Real_Vul_data.csv \
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
    --dataset_csv_path /app/RealVul/Dataset/Real_Vul_data.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --train

# 4. VP-Bench 테스트 데이터셋으로 테스트 (--test_predict)
docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/Real_Vul_data.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --test_predict
