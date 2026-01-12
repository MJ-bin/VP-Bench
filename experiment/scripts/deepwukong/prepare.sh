#!/bin/bash

set -euo pipefail

DOWNLOADS_DIR="downloads"
LOCK_FILE="datasets.lock.json"

echo "=== DeepWukong 데이터 준비 스크립트 ==="

# 디렉토리 구조 생성
echo "[1/5] 디렉토리 구조 생성..."
mkdir -p "$DOWNLOADS_DIR/DeepWukong/data"
mkdir -p "$DOWNLOADS_DIR/RealVul/datasets"

# DeepWukong 모델 데이터 다운로드
echo "[2/5] DeepWukong Data.7z 다운로드..."
cd "$DOWNLOADS_DIR/DeepWukong/data"

if [ ! -f "Data.7z" ]; then
    echo "  - Data.7z 다운로드 중..."
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/Data.7z
else
    echo "  - Data.7z 이미 존재 (스킵)"
fi

# Data.7z 압축 해제
echo "[3/5] Data.7z 압축 해제..."
if [ ! -d "CWE119" ]; then
    7z x Data.7z -y
    echo "  - 압축 해제 완료"
else
    echo "  - CWE119 디렉토리 이미 존재 (스킵)"
fi

# DeepWukong 모델 파일 다운로드
echo "[4/5] DeepWukong 모델 파일 다운로드..."
if [ ! -f "DeepWukong" ]; then
    wget -nc https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/DeepWukong
    echo "  - 모델 파일 다운로드 완료"
else
    echo "  - DeepWukong 모델 파일 이미 존재 (스킵)"
fi

# 검증
echo "[5/5] 파일 검증..."
test -d "CWE119" || { echo "Error: CWE119 디렉토리를 찾을 수 없습니다"; exit 1; }
test -f "DeepWukong" || { echo "Error: DeepWukong 모델 파일을 찾을 수 없습니다"; exit 1; }

echo "✅ DeepWukong 데이터 준비 완료!"
echo "   - 데이터 위치: $(pwd)"
echo "   - CWE119: $(du -sh CWE119 2>/dev/null | cut -f1)"
echo "   - DeepWukong: $(ls -lh DeepWukong | awk '{print $5}')"

# datasets.lock.json 생성/업데이트
cd /home/sojeon/Desktop/VP-Bench

if [ -f "$LOCK_FILE" ]; then
    echo "  - $LOCK_FILE 업데이트 (기존 파일 백업 중...)"
    cp "$LOCK_FILE" "${LOCK_FILE}.bak"
fi

cat > "$LOCK_FILE" <<EOF
{
  "version": "1.0.0",
  "generated": "$(date -Iseconds)",
  "datasets": {
    "DeepWukong": {
      "Data.7z": {
        "url": "https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/Data.7z",
        "sha256": "$(sha256sum $DOWNLOADS_DIR/DeepWukong/data/Data.7z | cut -d' ' -f1)",
        "extracted": ["CWE119"]
      },
      "DeepWukong": {
        "url": "https://github.com/seokjeon/VP-Bench/releases/download/v0.1.0/DeepWukong",
        "sha256": "$(sha256sum $DOWNLOADS_DIR/DeepWukong/data/DeepWukong | cut -d' ' -f1)",
        "type": "model"
      }
    }
  }
}
EOF

echo "✅ datasets.lock.json 생성 완료!"
echo ""
echo "다음 단계:"
echo "  1. docker compose down deepwukong"
echo "  2. docker compose up -d deepwukong"
echo "  3. bats ./docker/deepwukong/test_container.bats"
