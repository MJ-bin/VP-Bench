#!/bin/bash
# 1. train_val + test 병합
time docker exec linevul bash -c "cat /app/RealVul/Dataset/VP-Bench_Train_Dataset/Real_Vul_data.csv > /app/RealVul/Dataset/Real_Vul_data.csv && tail -n +2 /app/RealVul/Dataset/VP-Bench_Test_Dataset/Real_Vul_data.csv >> /app/RealVul/Dataset/Real_Vul_data.csv"
echo "1. train_val + test 병합 완료."

# 2. 데이터셋의 pickle 생성 (--prepare_dataset)
time docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/Real_Vul_data.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --prepare_dataset
echo "2. 데이터셋의 pickle 생성 완료."

# 3. 데이터셋으로 학습 (--train)
time docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/Real_Vul_data.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 64 \
    --per_device_eval_batch_size 64 \
    --num_train_epochs 10 \
    --train
echo "3. 학습 완료."

# 4. 테스트 데이터셋으로 테스트 (--test_predict)
time docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
    --dataset_csv_path /app/RealVul/Dataset/Real_Vul_data.csv \
    --dataset_path /app/RealVul/Dataset/ \
    --output_dir /app/RealVul/Experiments/LineVul \
    --tokenizer_name microsoft/codebert-base \
    --model_name /app/RealVul/Experiments/LineVul/best_model \
    --per_device_train_batch_size 8 \
    --per_device_eval_batch_size 8 \
    --num_train_epochs 10 \
    --test_predict
echo "4. 테스트 완료."
