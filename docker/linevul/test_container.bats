#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: linevul" >&3
}

# ------------------------------------------
# 1~2 테스트: 데이터/모델 마운트 검증
# ------------------------------------------

@test "1. LineVul 데이터/모델 마운트 검증" {
    echo "# 모델 파일 존재 확인..." >&3
    
    # 모델 파일 존재 확인
    run docker exec linevul test -f /app/RealVul/LineVul/linevul/saved_models/checkpoint-best-f1/12heads_linevul_model.bin
    [ "$status" -eq 0 ]
    
    echo "# 데이터셋 파일 존재 확인..." >&3
    
    # RealVul 데이터셋 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/Real_Vul_data.csv && \
        test -d /app/RealVul/Dataset/all_source_code
    '
    [ "$status" -eq 0 ]
    
    echo "# LineVul 데이터/모델 마운트 검증 완료" >&3
}

@test "2. 모델 파일 및 config.json 생성" {
    echo "# best_model 디렉토리 설정..." >&3
    
    run docker exec linevul bash -c '
        MODEL_PATH="/app/RealVul/Experiments/LineVul/best_model/12heads_linevul_model.bin"
        PYTORCH_MODEL_PATH="/app/RealVul/Experiments/LineVul/best_model/pytorch_model.bin"
        CONFIG_PATH="/app/RealVul/Experiments/LineVul/best_model/config.json"
        
        mkdir -p /app/RealVul/Experiments/LineVul/best_model
        
        # 모델 파일 복사
        if [ ! -f "$MODEL_PATH" ]; then
            cp /app/RealVul/LineVul/linevul/saved_models/checkpoint-best-f1/12heads_linevul_model.bin "$MODEL_PATH"
            cp "$MODEL_PATH" "$PYTORCH_MODEL_PATH"
        fi
        
        # config.json 생성
        if [ ! -f "$CONFIG_PATH" ]; then
            python - <<PY
from transformers import RobertaConfig
config = RobertaConfig.from_pretrained("microsoft/codebert-base")
config.num_labels = 2
config.save_pretrained("/app/RealVul/Experiments/LineVul/best_model")
PY
        fi
    '
    [ "$status" -eq 0 ]
    
    # 최종 확인 - 모든 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Experiments/LineVul/best_model/config.json && \
        test -f /app/RealVul/Experiments/LineVul/best_model/pytorch_model.bin && \
        test -f /app/RealVul/Experiments/LineVul/best_model/12heads_linevul_model.bin
    '
    [ "$status" -eq 0 ]
}

# ---------------------------------------------
# 5~8 테스트: Jasper 데이터셋 전처리 및 학습/테스트
# ---------------------------------------------

# bats test_tags=timeout:600
@test "3. 불완전한 jasper 데이터셋에 processed_func 열 추가" {
    run docker exec linevul bash -c '
        python /app/RealVul/Experiments/LineVul/append_datasetjasper.py
    '
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"Loading source code mapping"* ]]
    [[ "$output" == *"Jasper rows processed"* ]]
    [[ "$output" == *"Source merged"* ]]
    [[ "$output" == *"Output:"* ]]
    
    # test 3 최종 확인 - 소스코드가 추가된 데이터셋 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/jasper_data_append_processed_func.csv
   '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1200
@test "4. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)" {
    run docker exec linevul bash -c '
        python /app/RealVul/Experiments/LineVul/line_vul.py \
        --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
        --dataset_path /app/RealVul/Dataset/ \
        --output_dir /app/RealVul/Experiments/LineVul \
        --tokenizer_name microsoft/codebert-base \
        --model_name /app/RealVul/Experiments/LineVul/best_model \
        --per_device_train_batch_size 8 \
        --per_device_eval_batch_size 8 \
        --num_train_epochs 10 \
        --prepare_dataset
    '
    [ "$status" -eq 0 ]
    
    # test 6 최종 확인 - pickle 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/train_dataset.pickle && \
        test -f /app/RealVul/Dataset/val_dataset.pickle && \
        test -f /app/RealVul/Dataset/test_dataset.pickle
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "5. Jasper 데이터셋으로 학습 (--train)" {
    run docker exec linevul bash -c '
        python /app/RealVul/Experiments/LineVul/line_vul.py \
        --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
        --dataset_path /app/RealVul/Dataset/ \
        --output_dir /app/RealVul/Experiments/LineVul \
        --tokenizer_name microsoft/codebert-base \
        --model_name /app/RealVul/Experiments/LineVul/best_model \
        --per_device_train_batch_size 8 \
        --per_device_eval_batch_size 8 \
        --num_train_epochs 10 \
        --train
    '
    [ "$status" -eq 0 ]
    
    # test 7 최종 확인 - 학습과정 중 출력에서 필수 패턴 매칭 (학습 시작, 완료, 모델 저장)
    [[ "$output" == *"Running training"* ]]
    [[ "$output" == *"Training completed"* ]]
    [[ "$output" == *"Saving model checkpoint"* ]]
    [[ "$output" == *"best_model"* ]]
}

# bats test_tags=timeout:1800
@test "6. Jasper 데이터셋으로 테스트 (--test_predict)" {
    run docker exec linevul bash -c '
        python /app/RealVul/Experiments/LineVul/line_vul.py \
        --dataset_csv_path /app/RealVul/Dataset/jasper_data_append_processed_func.csv \
        --dataset_path /app/RealVul/Dataset/ \
        --output_dir /app/RealVul/Experiments/LineVul \
        --tokenizer_name microsoft/codebert-base \
        --model_name /app/RealVul/Experiments/LineVul/best_model \
        --per_device_train_batch_size 8 \
        --per_device_eval_batch_size 8 \
        --num_train_epochs 10 \
        --test_predict
    '
    [ "$status" -eq 0 ]

    # test 8 최종 확인 - 테스트과정 중 출력에서 필수 패턴 매칭 (테스트 실행 및 결과)
    [[ "$output" == *"Test Results"* ]]
    [[ "$output" == *"Running Prediction"* ]]
    [[ "$output" == *"Test Metrics"* ]]
    [[ "$output" == *"accuracy"* ]]
}
