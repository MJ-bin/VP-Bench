# PDBERT 사용법
---
## 1. 데이터셋 다운로드 및 컨테이너 복사

```bash
    # jasper_test_dataset 다운로드(추후 test_dataset이 확장되면 아래 코드를 수정하세요.)
    mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
    curl -L "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_dataset.csv" -o jasper_dataset.csv && \
    mv jasper_dataset.csv /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
    curl -L "https://github.com/seokjeon/VP-Bench/releases/download/VP-Bench_Test_Dataset/jasper_source_code.tar.gz" -o jasper_source_code.tar.gz && \
    tar -xvf jasper_source_code.tar.gz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test && \
    mv jasper_source_code.tar.gz /PDBERT/data/datasets/extrinsic/vul_detect/realvul_test
```

## 2. 데이터셋 전처리

```bash
# prepare_dataset.py 복사
docker cp prepare_dataset.py pdbert:/PDBERT/prepare_dataset.py

# 학습 데이터셋 전처리(schema: RealVul -> pdbert)
docker exec pdbert python /PDBERT/prepare_dataset.py --train {project_name}

# 테스트 데이터셋 전처리(schema: RealVul_test -> pdbert)
docker exec pdbert python /PDBERT/prepare_dataset.py --test {project_name}
```

## 3. 모델 학습(realvul)
```bash
docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul.jsonnet -task_name vul_detect/realvul -model_task_name vul_detect/realvul -average binary --train-only"
```
> 참고: 모델이 학습하는 데이터셋 경로는 `/PDBERT/downstream/vul_detect/realvul` 입니다.

## 4. 모델 평가(realvul_test)
```bash
docker exec pdbert bash -c "cd /PDBERT/downstream && python train_eval_from_config.py -config configs/vul_detect/pdbert_realvul_test.jsonnet -task_name vul_detect/realvul_test -model_task_name vul_detect/realvul -average binary --test-only"
```
> 참고: 모델이 평가하는 데이터셋 경로는 `/PDBERT/downstream/vul_detect/realvul_test` 입니다.

**학습과 테스트를 하나의 데이터셋으로 수행하려면 --train-only, --test-only 인자 없이 명령어를 실행하세요.**