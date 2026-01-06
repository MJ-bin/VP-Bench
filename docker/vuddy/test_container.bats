#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: vuddy" >&3
}

# -------------------------------------------------------------------

@test "1. vuddy 실행 가능성 점검" {
    run docker exec -w /app/vuddy/hmark vuddy python3 hmark.py -c ../vulnerable_code_ex on -n
    run docker exec -w /app/vuddy/hmark vuddy python3 hmark.py -c ../target_code_ex on -n
    run docker exec -w /app/vuddy/hmark vuddy mv hidx/hashmark_4_target_code_ex.hidx ../
    run docker exec -w /app/vuddy vuddy python3 ./checker/check_clones.py --target ./hashmark_4_target_code_ex.hidx --database hmark/hidx
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
    
    # 출력에서 필수 패턴 매칭
    [[ "$output" == *"[+] 1-th function in dir.cis a clone of vulnerability at dir.c"* ]]
    
    echo "# VUDDY executed successfully" >&3
}