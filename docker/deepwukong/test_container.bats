#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: deepwukong" >&3
}

# -------------------------------------------------------------------

@test "1. deepwukong 실행 환경 설정" {
    run docker exec deepwukong bash -c "if [ ! -f /code/models/DeepWukong/data/Data.7z ]; then wget https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/Data.7z -P /code/models/DeepWukong/data/; fi"
    run docker exec deepwukong 7z x /code/models/DeepWukong/data/Data.7z -o/code/models/DeepWukong/data/
    run docker exec deepwukong test -d /code/models/DeepWukong/data/CWE119
    
    run docker exec deepwukong bash -c "if [ ! -f /code/models/DeepWukong/data/DeepWukong ]; then wget https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/DeepWukong -P /code/models/DeepWukong/data/; fi"
    run docker exec deepwukong test -f /code/models/DeepWukong/data/DeepWukong

    run docker exec deepwukong sed -i "s|\"/data/dataset/.*\.csv\"|\"/data/dataset/RealVul_data.csv\"|g" config/config.yaml
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]

    echo "# deepwukong is configured successfully" >&3
}

@test "2. deepwukong 실행 가능성 점검" {
    run docker exec -w /code/models/DeepWukong -e PYTORCH_JIT=0 -e SLURM_TMPDIR=. deepwukong python evaluate.py ./data/DeepWukong --root_folder_path ./data --split_folder_name CWE119
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"test Metrics {'accuracy': 0.9836359560636628, 'precision': 0.9514978601997147, 'recall': 0.9447592067988668, 'f1': 0.9481165600568585, 'confusion_matrix': [[7442, 68], [78, 1334]]}"* ]]
    
    echo "# deepwukong is executable" >&3
}