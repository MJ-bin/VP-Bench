# VP-Bench
## 개요
1. 비교 도구 준비
2. 비교할 데이터 셋 준비

## 1. 비교 도구 준비
### 현재 실행 가능한 프로젝트 목록
- vuddy
- deepwukong
- linevul

### 실행 환경 구축 방법
`docker compose up -d --build {프로젝트 명}`

### 셸 접속
`docker compose exec {프로젝트 명} bash`

## 빌드 성공여부 검증
* linevul : 
`bats ./docker/linevul/test_image.bats`

## 2. 비교할 데이터 셋 준비
### 사전 준비 사항
1. .venv 활성화
2. `pip install -r requirements.txt && sudo apt install universal-ctags`
3. .env 파일 생성 및 설정 `GITHUB_TOKEN = {본인 깃헙 토큰 키 값}`
4. `bash ./dataset_pipeline/run.sh`

* (옵션) pdbert 모델을 위해 데이터셋 전처리(RealVul -> pdbert)가 필요하다면 컨테이너 진입후 다음 `cmd` 실행
```bash
python prepare_dataset.py {PROJECT_NAME}
# PROJECT_NAME: RealVul 데이터셋(.csv) 파일의 프로젝트 명(jasper, Chrome, qemu 등)
# 이때, Real_Vul 을 인자로 입력할경우 모든 데이터셋을 대상으로 pdbert 데이터셋을 생성합니다.
```
