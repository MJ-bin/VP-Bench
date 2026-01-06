# VP-Bench
## 개요
1. 비교 도구 준비
2. 비교할 데이터 셋 준비

## 1. 비교 도구 준비
### 현재 실행 가능한 프로젝트 목록
- vuddy
- deepwukong
- linevul
- pdbert

### 실행 환경 구축 방법
`docker compose up -d --build {프로젝트 명}`

### 셸 접속
`docker compose exec {프로젝트 명} bash`

## 빌드 성공여부 검증
* linevul : 
`sudo apt update && sudo apt install -y bats && bats ./docker/linevul/test_image.bats`
* pdbert : 
`sudo apt update && sudo apt install -y bats && bats ./docker/pdbert/test_image.bats`

## 2. 비교할 데이터 셋 준비
### 사전 준비 사항
1. .venv 활성화
2. `pip install -r requirements.txt && sudo apt install universal-ctags`
3. .env 파일 생성 및 설정 `GITHUB_TOKEN = {본인 깃헙 토큰 키 값}`
4. `bash ./dataset_pipeline/run.sh`
