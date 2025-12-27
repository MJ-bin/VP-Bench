import numpy as np
import pandas as pd
import json
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import time
import traceback
import sys
import cloudscraper
import ssl
import os
from dotenv import load_dotenv

github_token = os.getenv('GITHUB_TOKEN')

# .env 파일에서 환경 변수 로드
load_dotenv()

# 환경 변수에서 토큰 읽기
github_token = os.getenv('GITHUB_TOKEN')

if not github_token:
    print("[ERROR] .env 파일 또는 GITHUB_TOKEN 환경변수가 없습니다. GitHub API를 사용할 수 없습니다.")
    sys.exit(1)

ssl._create_default_https_context = ssl._create_unverified_context
scraper = cloudscraper.create_scraper()

def get_response(url):
    try:
        return json.loads(scraper.get(url, headers={
            'User-Agent': 'Mozilla/5.0',
            'Authorization': f'token {github_token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }).text)
    except HTTPError as e:
        if e.code == 429:
            time.sleep(10)
            return get_response(url)
        elif e.code == 404:
            print(f"\n not found: {url}")
            return ""
        elif e.code == 403:
            time.sleep(600)
            return get_response(url)
        else:
            traceback.print_exc(file=sys.stdout)
            return ""
    except Exception as e:
        traceback.print_exc(file=sys.stdout)
        print(f"\n skip get_response: {url}")
        return ""


# VP-Bench_Dataset/output/jasper/ 기준 경로 지정
input_path = "output/jasper/VP-Bench_jasper_(codeLink,CVE ID).csv"
output_path = "output/jasper/VP-Bench_jasper_files_changed.csv"
df = pd.read_csv(input_path)
df["files_changed"] = None
df["lang"] = None

# commit_id 기준 그룹화 및 CVE ID join
if "commit_id" in df.columns:
    grouped = df.groupby("commit_id")
    new_rows = []
    for commit_id, group in grouped:
        cve_ids = ", ".join(group["CVE ID"].astype(str).unique())
        first_row = group.iloc[0].copy()
        first_row["CVE ID"] = cve_ids
        new_rows.append(first_row)
    df = pd.DataFrame(new_rows)

# 각 행 처리
for index, row in df.iterrows():
    codeLink = row["codeLink"]
    cveID = row["CVE ID"]
    
    # commit_id 추출
    pos = codeLink.rfind("/")
    commit_id = codeLink[pos+1:]
    
    # GitHub API URL 구성
    start = codeLink.find("github.com") + len("github.com")
    end = codeLink.rfind("/commit")
    repo_path = codeLink[start:end]
    
    commit_url = f"https://api.github.com/repos{repo_path}/commits/{commit_id}"
    repo_url = f"https://api.github.com/repos{repo_path}"
    
    print(f"Processing: {cveID}")
    
    # 리포지토리 정보에서 언어 추출
    repo_response = get_response(repo_url)
    if repo_response and "language" in repo_response:
        df.loc[index, "lang"] = repo_response["language"]
    
    response = get_response(commit_url)
    
    try:
        if response and response != "" and isinstance(response, dict) and "files" in response:
            # files_changed 처리
            files_changed = ""
            j = 0
            for i in response["files"]:
                if j < len(response["files"]) - 1:
                    files_changed = files_changed + json.dumps(i) + "<_**next**_>"
                else:
                    files_changed = files_changed + json.dumps(i)
                j += 1
            df.loc[index, "files_changed"] = files_changed
            print(f"Done: {index}")
    except Exception as e:
        traceback.print_exc(file=sys.stdout)
        print(f"reason: {e}")
        print(f"skip: {commit_url}")
        continue

# 결과 저장
df.to_csv(output_path, index=False)
print("완료")