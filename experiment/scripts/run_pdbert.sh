#!/bin/bash

# 1. 테스트 데이터셋 다운로드
docker exec pdbert bash -c "mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
    curl -L 'https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv' -o jasper_dataset.csv && \
    mv jasper_dataset.csv /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
    curl -L 'https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz' -o jasper_source_code.tar.gz && \
    tar -xvf jasper_source_code.tar.gz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
    mv jasper_source_code.tar.gz /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test"

# 2. 데이터셋 전처리
docker exec pdbert python /PDBERT/prepare_dataset.py --train jasper
docker exec pdbert python /PDBERT/prepare_dataset.py --test jasper

# 3. Config 파일 생성 (pdbert_realvul.jsonnet, pdbert_realvul_test.jsonnet)
docker exec pdbert bash -c "cp /PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet && \
    sed -i 's|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul/|g' /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet && \
    cp /PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet /PDBERT/downstream/configs/vul_detect/pdbert_realvul_test.jsonnet && \
    sed -i 's|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul_test/|g' /PDBERT/downstream/configs/vul_detect/pdbert_realvul_test.jsonnet"

# 4. 모델 학습
docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul.jsonnet -task_name vul_detect/realvul -model_task_name vul_detect/realvul -average binary --train-only"

# 5. 모델 평가
docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul_test.jsonnet -task_name vul_detect/realvul_test -model_task_name vul_detect/realvul -average binary --test-only"
