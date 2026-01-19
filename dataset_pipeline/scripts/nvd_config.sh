#!/bin/bash
# config.sh - 설정 파일

START_YEAR=2020
END_YEAR=2025

# NVD API 기본 URL (변경 가능)
NVD_API_BASE_URL="https://nvd.nist.gov/feeds/json/cve/2.0"
BASE_URL="${NVD_API_BASE_URL}"  # 하위 호환성 유지

# 정의된 프로젝트 전체 리스트
ALL_PROJECTS=("FFmpeg" "ImageMagick" "jasper" "krb5" "openssl" "php-src" "qemu" "tcpdump" "linux" "chrome") # Chrome: chromium
