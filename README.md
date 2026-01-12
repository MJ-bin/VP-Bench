# VP-Bench
## 개요
1. 비교 도구 준비
2. 비교할 데이터 셋 준비
3. 실험 재현

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
`bats ./docker/{프로젝트 명}/test_container.bats`
* bats 설치 명령어: `sudo apt update && sudo apt install -y bats`

## 2. 비교할 데이터 셋 준비
### 사전 준비 사항
1. .venv 활성화
2. `pip install -r requirements.txt && sudo apt install universal-ctags`
3. .env 파일 생성 및 설정 `GITHUB_TOKEN = {본인 깃헙 토큰 키 값}`
4. `bash ./dataset_pipeline/run.sh`

## 3. 실험 재현
Docker 빌드, 빌드 검증, 실험을 순차적으로 실행
모든 로그는 logs/run.log에 기록


`bash ./experiment/run.sh -m {실험할 모델}`

### 현재 실험 가능한 모델 목록
- vuddy
- deepwukong
- linevul
- pdbert
- all * 전체 모델 실행 시

