#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: pdbert" >&3
}

# -------------------------------------------------------------------

@test "1. jasper 데이터셋 생성 for pdbert" {
    # prepare_dataset.py를 사용하여 jasper 데이터셋 JSON 생성
    # (tar 압축 해제 + CSV → JSON 변환을 모두 처리)
    run docker exec pdbert python /PDBERT/prepare_dataset.py jasper
    
    # 실행 결과 출력 (항상 표시)
    echo "# prepare_dataset.py output:" >&3
    echo "$output" >&3
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"Project: jasper"* ]]
    [[ "$output" == *"Train:"* ]]
    [[ "$output" == *"Validate:"* ]]
    [[ "$output" == *"Test:"* ]]
    [[ "$output" == *"Done!"* ]]
    
    # JSON 파일 생성 확인
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/realvul/train.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/realvul/validate.json
    [ "$status" -eq 0 ]
    
    run docker exec pdbert test -f /PDBERT/data/datasets/extrinsic/vul_detect/realvul/test.json
    [ "$status" -eq 0 ]
    
    echo "# JSON files created successfully" >&3
}


@test "2. PDBERT 학습 및 평가 (Jasper 데이터셋)" {
    # pdbert_realvul.jsonnet은 Dockerfile에서 이미 생성됨
    run docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul.jsonnet -task_name vul_detect/realvul -average binary"

    # 실행 결과 출력 (항상 표시)
    echo "# PDBERT training output:" >&3
    echo "$output" >&3
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 학습 완료 패턴 확인
    [[ "$output" == *"best_validation_f1"* ]]
    [[ "$output" == *"training_duration"* ]]
    
    # 테스트 실행 및 결과 패턴 확인
    [[ "$output" == *"Start to test File"* ]]
    [[ "$output" == *"Accuracy"* ]]
    [[ "$output" == *"F1-Score"* ]]
    [[ "$output" == *"Precision"* ]]
    [[ "$output" == *"Recall"* ]]
    
    echo "# Training and evaluation completed successfully" >&3
}
