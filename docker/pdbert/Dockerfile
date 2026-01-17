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

# 소스 코드는 런타임에 볼륨으로 마운트됨 (docker-compose.yml 참조)
WORKDIR /PDBERT

# global_vars.json 동적 생성을 위한 엔트리포인트 설정
RUN echo '#!/bin/bash\n\
HOSTNAME=$(hostname)\n\
echo "{\n  \"$HOSTNAME\": {\n    \"python_bin\": \"/usr/bin/python\"\n  }\n}" > /PDBERT/downstream/global_vars.json\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]