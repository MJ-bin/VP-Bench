#!/usr/bin/env bats

# [설정] 테스트 시작 전 1회 실행 (컨테이너 실행)
setup_file() {
    echo "# Setting up: Cleaning old container and starting new one..." >&3
    
    # 0. 컨테이너 실행 (백그라운드 모드 -d)
    run docker run -d --gpus all --name linevul linevul
    
    if [ "$status" -ne 0 ]; then
        echo "# Error: Failed to start container" >&3
        return 1
    fi
    
    # 컨테이너가 완전히 뜰 때까지 대기
    sleep 5
}

# [정리] 모든 테스트 종료 후 1회 실행 (컨테이너 삭제)
teardown_file() {
    echo "# Teardown: Removing container..." >&3
    docker rm -f linevul
}

# -------------------------------------------------------------------

@test "1. 불완전한 jasper 데이터셋에 processed_func 열 추가" {
    run docker exec linevul python /app/RealVul/Experiments/LineVul/append_datasetjasper.py
    
    # 실행 결과 출력 (디버깅용)
    echo "$output"
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
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

    echo "$output"
    [ "$status" -eq 0 ]
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

    echo "$output"
    [ "$status" -eq 0 ]
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

    echo "$output"
    [ "$status" -eq 0 ]
}
