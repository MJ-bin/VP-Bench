#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: linevul" >&3
}

# ------------------------------------------
# 1~7 테스트: 환경 설정 및 데이터/모델 다운로드
# ------------------------------------------

# bats test_tags=timeout:600
@test "1. RealVul 저장소 클론" {
    # 이미 존재하면 스킵
    run docker exec linevul bash -c '
        if [ -d "/app/RealVul/.git" ]; then
            echo "[SKIP] RealVul 저장소가 이미 존재합니다."
            exit 0
        fi
        
        echo "[INFO] RealVul 저장소 클론 시작..."
        cd /app
        git clone https://github.com/seokjeon/RealVul.git
        cd RealVul
        git submodule update --init --recursive
        echo "[OK] RealVul 저장소 클론 완료"
    '
    [ "$status" -eq 0 ]
    
    # test 1 최종 확인 - linevul 저장소 존재 확인
    run docker exec linevul bash -c '
        test -d /app/RealVul/.git
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "2. LineVul 모델 다운로드 (12heads_linevul_model.bin)" {
    run docker exec linevul bash -c '
        MODEL_PATH="/app/RealVul/LineVul/linevul/saved_models/checkpoint-best-f1/12heads_linevul_model.bin"
        
        if [ -f "$MODEL_PATH" ]; then
            echo "[SKIP] 모델 파일이 이미 존재합니다: $MODEL_PATH"
            exit 0
        fi
        
        echo "[INFO] LineVul 모델 다운로드 시작..."
        mkdir -p "$(dirname "$MODEL_PATH")"
        gdown --fuzzy "https://drive.google.com/uc?id=1oodyQqRb9jEcvLMVVKILmu8qHyNwd-zH" -O "$MODEL_PATH"
        echo "[OK] 모델 다운로드 완료: $MODEL_PATH"
    '
    [ "$status" -eq 0 ]
    
    # test 2 최종 확인 - 모델 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/LineVul/linevul/saved_models/checkpoint-best-f1/12heads_linevul_model.bin
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "3 big-vul 데이터셋 다운로드" {
    run docker exec linevul bash -c '
        ARCHIVE_PATH="/app/RealVul/LineVul/data/big-vul_dataset/big-vul_dataset.7z"
        
        # 이미 다운로드된 경우 스킵
        if [ -f "$ARCHIVE_PATH" ]; then
            echo "[SKIP] big-vul_dataset.7z 파일이 이미 존재합니다."
            exit 0
        fi
        
        echo "[INFO] big-vul 데이터셋 다운로드 시작..."
        mkdir -p /app/RealVul/LineVul/data/big-vul_dataset/
        wget https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/big-vul_dataset.7z -P /app/RealVul/LineVul/data/big-vul_dataset/
    '
    [ "$status" -eq 0 ]
    
    # test 3 최종 확인 - 데이터셋 또는 압축 해제된 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/LineVul/data/big-vul_dataset/big-vul_dataset.7z
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "4 big-vul 데이터셋 압축 해제" {
    run docker exec linevul bash -c '
        ARCHIVE_PATH="/app/RealVul/LineVul/data/big-vul_dataset/big-vul_dataset.7z"
        
        # 이미 압축 해제된 경우에도 이전 실험에서의 데이터셋과 겹칠수 있으므로, 압축해제하여 덮어씁니다.
        
        echo "[INFO] big-vul 데이터셋 압축 해제 중..."
        7z x "$ARCHIVE_PATH" -y -o/app/RealVul/LineVul/data/big-vul_dataset/
    '
    [ "$status" -eq 0 ]
    
    # test 4 최종 확인 - 압축 해제된 데이터셋 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/LineVul/data/big-vul_dataset/train.csv && \
        test -f /app/RealVul/LineVul/data/big-vul_dataset/test.csv && \
        test -f /app/RealVul/LineVul/data/big-vul_dataset/val.csv
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "5 RealVul 데이터셋 다운로드" {
    run docker exec linevul bash -c '
        ARCHIVE_1="/app/RealVul/Dataset/dataset_without_src.7z"
        ARCHIVE_2="/app/RealVul/Dataset/all_source_code.tar.xz"

        # 이미 다운로드된 경우 스킵
        if [ -f "$ARCHIVE_1" ] && [ -f "$ARCHIVE_2" ]; then
            echo "[SKIP] RealVul 데이터셋 파일이 이미 다운로드되어 있습니다."
            exit 0
        fi
        
        echo "[INFO] RealVul 데이터셋 다운로드 시작..."
        mkdir -p /app/RealVul/Dataset/
        wget https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z -P /app/RealVul/Dataset/
        wget https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz -P /app/RealVul/Dataset/
    '
    [ "$status" -eq 0 ]
    
    # test 5 최종 확인 - 다운로드된 데이터셋 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/dataset_without_src.7z && \
        test -f /app/RealVul/Dataset/all_source_code.tar.xz
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "6 RealVul 데이터셋 압축 해제" {
    run docker exec linevul bash -c '
        ARCHIVE_1="/app/RealVul/Dataset/dataset_without_src.7z"
        ARCHIVE_2="/app/RealVul/Dataset/all_source_code.tar.xz"
        
        # 이미 압축 해제된 경우에도 이전 실험에서의 데이터셋과 겹칠수 있으므로, 압축해제하여 덮어씁니다.
        
        echo "[INFO] RealVul 데이터셋 압축 해제 중..."
        7z x "$ARCHIVE_1" -y -o/app/RealVul/Dataset/
        tar -xvf "$ARCHIVE_2" -C /app/RealVul/Dataset/
    '
    [ "$status" -eq 0 ]
    
    # test 6 최종 확인 - 압축 해제된 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/Real_Vul_data.csv && \
        test -d /app/RealVul/Dataset/all_source_code
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1200
@test "7 모델 파일 및 config.json 생성" {
    run docker exec linevul bash -c '
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
    [ "$status" -eq 0 ]
    
    # test 7 최종 확인 - 모델 파일 및 config.json 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Experiments/LineVul/best_model/config.json && \
        test -f /app/RealVul/Experiments/LineVul/best_model/pytorch_model.bin && \
        test -f /app/RealVul/Experiments/LineVul/best_model/12heads_linevul_model.bin
   '
    [ "$status" -eq 0 ]
}

# ---------------------------------------------
# 8~11 테스트: Jasper 데이터셋 전처리 및 학습/테스트
# ---------------------------------------------

# bats test_tags=timeout:600
@test "8. 불완전한 jasper 데이터셋에 processed_func 열 추가" {
    run docker exec linevul bash -c '
        python /app/RealVul/Experiments/LineVul/append_datasetjasper.py
    '
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"Loading source code mapping"* ]]
    [[ "$output" == *"Jasper rows processed"* ]]
    [[ "$output" == *"Source merged"* ]]
    [[ "$output" == *"Output:"* ]]
    
    # test 8 최종 확인 - 소스코드가 추가된 데이터셋 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/jasper_data_append_processed_func.csv
   '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1200
@test "9. Jasper 데이터셋의 pickle 생성 (--prepare_dataset)" {
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
    
    # test 9 최종 확인 - pickle 파일 존재 확인
    run docker exec linevul bash -c '
        test -f /app/RealVul/Dataset/train_dataset.pickle && \
        test -f /app/RealVul/Dataset/val_dataset.pickle && \
        test -f /app/RealVul/Dataset/test_dataset.pickle
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=timeout:1800
@test "10. Jasper 데이터셋으로 학습 (--train)" {
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
    
    # test 10 최종 확인 - 학습과정 중 출력에서 필수 패턴 매칭 (학습 시작, 완료, 모델 저장)
    [[ "$output" == *"Running training"* ]]
    [[ "$output" == *"Training completed"* ]]
    [[ "$output" == *"Saving model checkpoint"* ]]
    [[ "$output" == *"best_model"* ]]
}

# bats test_tags=timeout:1800
@test "11. Jasper 데이터셋으로 테스트 (--test_predict)" {
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

    # test 11 최종 확인 - 테스트과정 중 출력에서 필수 패턴 매칭 (테스트 실행 및 결과)
    [[ "$output" == *"Test Results"* ]]
    [[ "$output" == *"Running Prediction"* ]]
    [[ "$output" == *"Test Metrics"* ]]
    [[ "$output" == *"accuracy"* ]]
}
