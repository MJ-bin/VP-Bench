# Ubuntu 기반 CUDA 11.1 + PyTorch 1.10.2 + AllenNLP 환경
FROM nvidia/cuda:11.1.1-cudnn8-runtime-ubuntu20.04

# 환경 변수 설정
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
# ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH} # h100 에서 CUDA 라이브러리 경로 문제

# 필수 패키지 설치 (C++ 컴파일러 포함)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.8 \
    python3.8-dev \
    python3-pip \
    git \
    git-lfs \
    curl \
    unzip \
    p7zip-full \
    build-essential \
    g++ \
    p7zip-full \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# python3를 기본으로 설정
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1 \
    && update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# pip 업그레이드
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# PyTorch 및 관련 패키지 설치 (CUDA 11.1 버전)
RUN pip install --no-cache-dir \
    torch==1.10.2+cu111 \
    torchvision==0.11.3+cu111 \
    torchtext==0.11.2 \
    -f https://download.pytorch.org/whl/cu111/torch_stable.html

# 기타 의존성 패키지 설치
RUN pip install --no-cache-dir \
    numpy==1.22.4 \
    scipy==1.8.1 \
    transformers==4.12.5

# AllenNLP 설치 (notebook 7.x 호환성 문제 해결)
RUN pip install --no-cache-dir "notebook<7.0" "jupyter<1.1"
RUN pip install --no-cache-dir \
    allennlp==2.8.0 \
    allennlp_models==2.8.0

# PDBERT 클론 및 데이터 설정
WORKDIR /
RUN git clone https://github.com/MJ-bin/PDBERT.git

WORKDIR /PDBERT
RUN curl -L "https://github.com/MJ-bin/PDBERT/releases/download/v0.1.0/PDBERT_data.zip" -o PDBERT_data.zip && \
    7z x PDBERT_data.zip && \
    mv PDBERT_data/data ./data && \
    rm -rf PDBERT_data PDBERT_data.zip && \
    # RealVul dataset 다운로드
    mkdir -p /PDBERT/data/datasets/extrinsic/vul_detect/realvul && \
    curl -L "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/all_source_code.tar.xz" -o all_source_code.tar.xz && \
    tar -xvf all_source_code.tar.xz -C /PDBERT/data/datasets/extrinsic/vul_detect/realvul && \
    rm -rf all_source_code.tar.xz && \
    curl -L "https://github.com/seokjeon/VP-Bench/releases/download/RealVul_Dataset/dataset_without_src.7z" -o dataset_without_src.7z && \
    7z x dataset_without_src.7z -o/PDBERT/data/datasets/extrinsic/vul_detect/realvul -y && \
    rm -f dataset_without_src.7z

# Config 파일생성: pdbert_realvul.jsonnet (경로 수정 포함)
RUN cp /PDBERT/downstream/configs/vul_detect/pdbert_reveal.jsonnet \
   /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet && \
   sed -i "s|../data/datasets/extrinsic/vul_detect/reveal/|/PDBERT/data/datasets/extrinsic/vul_detect/realvul/|g" \
   /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet

# RealVul 데이터셋 변환 스크립트 생성
RUN cat > /PDBERT/data/datasets/extrinsic/vul_detect/realvul/make_dataset_for_pdbert.py << 'EOF'
#!/usr/bin/env python3
import csv
import json
from pathlib import Path
import random

BASE_DIR = Path("/PDBERT/data/datasets/extrinsic/vul_detect/realvul")
CSV_PATH = BASE_DIR / "Real_Vul_data.csv"
SOURCE_DIR = BASE_DIR / "all_source_code"
OUTPUT_DIR = BASE_DIR

random.seed(42)
train_val_data = []
test_data = []

with open(CSV_PATH, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        source_file = SOURCE_DIR / f"{row['file_name']}.c"
        if not source_file.exists():
            continue
        with open(source_file, 'r', errors='ignore') as sf:
            code = sf.read()
        item = {"code": code, "vul": int(row['target'])}
        if row['dataset_type'] == "train_val":
            train_val_data.append(item)
        else:
            test_data.append(item)

random.shuffle(train_val_data)
split_idx = int(len(train_val_data) * 0.8)

with open(OUTPUT_DIR / "train.json", 'w') as f:
    json.dump(train_val_data[:split_idx], f, indent=4)
with open(OUTPUT_DIR / "validate.json", 'w') as f:
    json.dump(train_val_data[split_idx:], f, indent=4)
with open(OUTPUT_DIR / "test.json", 'w') as f:
    json.dump(test_data, f, indent=4)

print(f"Train: {split_idx}, Validate: {len(train_val_data)-split_idx}, Test: {len(test_data)}")
EOF

# 데이터셋 변환 스크립트 실행
RUN python /PDBERT/data/datasets/extrinsic/vul_detect/realvul/make_dataset_for_pdbert.py

# CodeBERT 모델 다운로드 (네트워크 문제 방지)
RUN git lfs install && \
    git clone https://huggingface.co/microsoft/codebert-base pretrain/microsoft/codebert-base && \
    git clone https://huggingface.co/microsoft/codebert-base downstream/microsoft/codebert-base

# global_vars.json 동적 생성을 위한 엔트리포인트 설정
RUN echo '#!/bin/bash\n\
HOSTNAME=$(hostname)\n\
echo "{\n  \"$HOSTNAME\": {\n    \"python_bin\": \"/usr/bin/python\"\n  }\n}" > /PDBERT/downstream/global_vars.json\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]