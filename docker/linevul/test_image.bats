#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: linevul" >&3
}

# -------------------------------------------------------------------

@test "1. 불완전한 jasper 데이터셋에 processed_func 열 추가" {
    run docker exec linevul python /app/RealVul/Experiments/LineVul/append_datasetjasper.py
    
    # 실행 결과 출력 (항상 표시)
    echo "# append_datasetjasper.py output:" >&3
    echo "$output" >&3
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"Loading source code mapping"* ]]
    [[ "$output" == *"Jasper rows processed"* ]]
    [[ "$output" == *"Source merged"* ]]
    [[ "$output" == *"Output:"* ]]
    
    echo "# Dataset append completed successfully" >&3
}

@test "2. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)" {
    run docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
        --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
        --dataset_path /app/RealVul/Dataset/ \
        --output_dir /app/RealVul/Experiments/LineVul \
        --tokenizer_name microsoft/codebert-base \
        --model_name /app/RealVul/Experiments/LineVul/best_model \
        --per_device_train_batch_size 8 \
        --per_device_eval_batch_size 8 \
        --num_train_epochs 10 \
        --prepare_dataset

    # 실행 결과 출력 (항상 표시)
    echo "# prepare_dataset output:" >&3
    echo "$output" >&3
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"Preparing Dataset"* ]]
    [[ "$output" == *"100%"* ]]
    
    echo "# Dataset preparation completed successfully" >&3
}

@test "3. Jasper 데이터셋으로 학습 (--train)" {
    run docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
        --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
        --dataset_path /app/RealVul/Dataset/ \
        --output_dir /app/RealVul/Experiments/LineVul \
        --tokenizer_name microsoft/codebert-base \
        --model_name /app/RealVul/Experiments/LineVul/best_model \
        --per_device_train_batch_size 8 \
        --per_device_eval_batch_size 8 \
        --num_train_epochs 10 \
        --train

    # 실행 결과 출력 (항상 표시)
    echo "# train output:" >&3
    echo "$output" >&3
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭 (학습 시작, 완료, 모델 저장)
    [[ "$output" == *"Running training"* ]]
    [[ "$output" == *"Training completed"* ]]
    [[ "$output" == *"Saving model checkpoint"* ]]
    [[ "$output" == *"best_model"* ]]
    
    echo "# Training completed successfully" >&3
}

@test "4. Jasper 데이터셋으로 테스트 (--test_predict)" {
    run docker exec linevul python /app/RealVul/Experiments/LineVul/line_vul.py \
        --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
        --dataset_path /app/RealVul/Dataset/ \
        --output_dir /app/RealVul/Experiments/LineVul \
        --tokenizer_name microsoft/codebert-base \
        --model_name /app/RealVul/Experiments/LineVul/best_model \
        --per_device_train_batch_size 8 \
        --per_device_eval_batch_size 8 \
        --num_train_epochs 10 \
        --test_predict

    # 실행 결과 출력 (항상 표시)
    echo "# test_predict output:" >&3
    echo "$output" >&3
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭 (테스트 실행 및 결과)
    [[ "$output" == *"Test Results"* ]]
    [[ "$output" == *"Running Prediction"* ]]
    [[ "$output" == *"Test Metrics"* ]]
    [[ "$output" == *"accuracy"* ]]
    
    echo "# Test prediction completed successfully" >&3
}
