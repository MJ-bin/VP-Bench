import numpy as np
import pandas as pd
import os
#coding=utf8
import sys
from urllib.error import HTTPError
import ssl
import time
import traceback
import json
import subprocess
import shlex
from dataclasses import dataclass
ssl._create_default_https_context = ssl._create_unverified_context
import cloudscraper
from dotenv import load_dotenv
import argparse
from pathlib import Path

# .env 파일에서 환경 변수 로드
load_dotenv()

# 환경 변수에서 토큰 읽기
github_token = os.getenv('GITHUB_TOKEN')

# Constants
BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_BASE = BASE_DIR / "output" / "jasper"
# Store patch/split artifacts under the project output directory
PATCH_ROOT = OUTPUT_BASE / "patches"
SPLIT_ROOT = OUTPUT_BASE / "extracted_functions"
DEFAULT_CWE_ID = "others"

@dataclass
class HunkInfo:
    old_start: int
    old_len: int
    new_start: int
    new_len: int
    removed_count: int
    added_count: int
    removed_offsets: list
    added_offsets: list
    hunk_lines: list
    insert_after: int
    diff_value: int
    prev_new_end: int

ssl._create_default_https_context = ssl._create_unverified_context
scraper = cloudscraper.create_scraper()

def fetch_source_text(url):
    try:
        file = scraper.get(url,headers={'User-Agent':'Mozilla/5.0',
               'Authorization': f'token {github_token}',
               'Content-Type':'application/json',
               'Accept':'application/json'}).text
        return file
    except HTTPError as e:
        if e.code == 429:
            time.sleep(10)
            return fetch_source_text(url)
        if e.code == 404:
            print("\n not found:" + url+ "！")
            return ""
        if e.code == 403:
            print("403 please wait")
            print(url)
            return ""
        raise
    except Exception as e:
        traceback.print_exc(file=sys.stdout)
        print("reason", e)
        print("\n skip get_response:"+url+ "！")
        return ""
    
# find all the line numbers that the functions begins
def list_function_starts(filename, lang_type):
    # Normalize path for ctags
    filename_str = str(filename)
    cmd = f"ctags -x --{lang_type}-kinds=f {shlex.quote(filename_str)}"
    output = subprocess.getoutput(cmd)
    lines = output.splitlines()
    line_nums = []
    for line in lines:
        line = line.split(" ")
        char = list(filter(None, line))
        line_num = char[2]
        line_nums.append(int(line_num))
    return line_nums

    # if found == False:
    #     #print("Function not found")
    #     return 0

# given the file name and  line number(start), return the code of the line number and the endline num
def read_function_block(filename, line_num):
    filename_str = str(filename)
    print("opening " + filename_str + " on line " + str(line_num))

    code = ""
    bracket_depth = 0
    in_body = False

    with open(filename_str, "r") as f:
        for i, line in enumerate(f):
            if(i >= (line_num - 1)):
                code += line

                if (not line.startswith("//")) and line.count("{") > 0:
                    in_body = True
                    bracket_depth += line.count("{")

                if (not line.startswith("//")) and line.count("}") > 0:
                    bracket_depth -= line.count("}")

                if bracket_depth == 0 and in_body == True:
                    return code, i+1

def list_hunk_starts(filename):
    diff_start_lines = []
    with open(filename, "r") as patch:
        for i, line in enumerate(patch):
            if line.startswith("@@ "):
                if not i == 0:
                    diff_start_lines.append(i)
        diff_start_lines.append(i+1)
    return diff_start_lines

def iter_patch_lines(filename):
    patch = open(filename, "r")
    return enumerate(patch)

#return anchor： @@ -61,7 +61,7 @@; how many -;  how many +; - positinons; + positions
'''
@@ -6835,12 +6835,16 @@ static void buffer_pipe_buf_release(struct pipe_inode_info *pipe,
 	buf->private = 0;
 }

-static void buffer_pipe_buf_get(struct pipe_inode_info *pipe,
+static bool buffer_pipe_buf_get(struct pipe_inode_info *pipe,
 				struct pipe_buffer *buf)
 {
 	struct buffer_ref *ref = (struct buffer_ref *)buf->private;

+	if (ref->ref > INT_MAX/2)
+		return false;
+
 	ref->ref++;
+	return true;
 }

 /* Pipe buffer operations for a buffer. */
 
 -------------------------------------------
 return:
 [[['6835', '12'], ['6835', '16'], 1, 5, [4], [5, 10, 11, 12, 14]]]
'''
def parse_range(raw_range):
    raw = raw_range[1:]
    if "," in raw:
        start_str, len_str = raw.split(",", 1)
        return int(start_str), int(len_str)
    return int(raw), 1


def collect_hunks(patch_path):
    """단순하고 일관된 hunk 파싱: header부터 다음 header 전까지 수집"""
    hunks = []
    cumulative_removed = 0
    prev_new_end = 0

    with open(patch_path, "r") as patch_file:
        lines = patch_file.readlines()

    idx = 0
    total = len(lines)
    while idx < total:
        line = lines[idx]
        if not line.startswith("@@ "):
            idx += 1
            continue

        header = line
        section = header[header.find("@@ ") + 3: header.rfind(" @@")].strip()
        old_raw, new_raw = section.split(" ")
        old_start, old_len = parse_range(old_raw)
        new_start, new_len = parse_range(new_raw)

        hunk_lines = [header]
        removed_offsets, added_offsets = [], []
        removed_count = 0
        added_count = 0

        inner_idx = idx + 1
        while inner_idx < total and not lines[inner_idx].startswith("@@ "):
            hline = lines[inner_idx]
            hunk_lines.append(hline)
            if hline.startswith("-"):
                removed_count += 1
                removed_offsets.append(inner_idx - idx)
            elif hline.startswith("+"):
                added_count += 1
                added_offsets.append(inner_idx - idx)
            inner_idx += 1

        diff_value = cumulative_removed + removed_count
        last_end = new_start + new_len - 1

        hunks.append(HunkInfo(
            old_start=old_start,
            old_len=old_len,
            new_start=new_start,
            new_len=new_len,
            removed_count=removed_count,
            added_count=added_count,
            removed_offsets=removed_offsets,
            added_offsets=added_offsets,
            hunk_lines=hunk_lines,
            insert_after=new_start + cumulative_removed,
            diff_value=diff_value,
            prev_new_end=prev_new_end
        ))

        cumulative_removed = diff_value
        prev_new_end = last_end
        idx = inner_idx

    return hunks

def parse_changed_files(row):
    code_link = row["codeLink"]
    commit_hash = code_link[code_link.rfind("/")+1:]
    files_changed_raw = row["files_changed"]
    files_changed = []
    for i in files_changed_raw.split("<_**next**_>"):
        files_changed.append(json.loads(i))
    return files_changed, commit_hash

def get_file_info(changed_file, commit_hash):
    path_in_repo = changed_file["filename"]
    path_obj = Path(path_in_repo)
    
    filename = path_obj.name
    dir_path = str(Path(commit_hash) / path_obj.parent) if path_obj.parent else commit_hash
    
    raw_url = changed_file["raw_url"]
    patch = changed_file.get("patch", "")
    
    basename = Path(filename).stem
    ext = Path(filename).suffix[1:] if Path(filename).suffix else "not know"
    
    return filename, dir_path, raw_url, patch, basename, ext

def download_src_and_patches(raw_url, patch, ext, project, CWE_ID, dir_path, filename, basename):
    source_text = fetch_source_text(raw_url)
    base_dir = PATCH_ROOT / ext / project / CWE_ID / dir_path
    base_dir.mkdir(parents=True, exist_ok=True)
    source_file_path = base_dir / filename
    patch_file_path = base_dir / f"{basename}_patch.txt"
    with open(source_file_path, "w+") as source_file, open(patch_file_path, "w+") as patch_file:
        source_file.write(source_text)
        patch_file.write(patch)
    return str(source_file_path), str(patch_file_path)

def determine_language(ext):
    if ext == "c":
        return "c"
    elif ext in ["C", "cc", "cxx", "cpp", "c++", "Cpp"]:
        return "cpp"
    else:
        return None

def apply_patches(lang_type, sourcefile_dir, patchfile_dir, filename, file_dir, project, CWE_ID):
    # 패치 파일 분석: diff 블록 파싱
    hunks = collect_hunks(patchfile_dir)

    # 원본과 출력 준비
    with open(sourcefile_dir, "r") as before:
        src_lines = before.readlines()

    patched_file_path = PATCH_ROOT / lang_type / project / CWE_ID / file_dir / f"add_patch_{filename}"
    patched_file_path.parent.mkdir(parents=True, exist_ok=True)

    patched_lines = []
    cursor = 0  # 0-indexed 현재 소스 포인터

    for hunk in hunks:
        start_idx = max(hunk.new_start - 1, 0)
        end_idx = max(start_idx + hunk.new_len, start_idx)

        # 패치 앞부분 복사
        patched_lines.extend(src_lines[cursor:start_idx])

        # hunk 라인 적용 (+/-만 주석화, @@/컨텍스트는 스킵)
        for hline in hunk.hunk_lines[1:]:
            if hline.startswith("@@"):
                continue
            if hline.startswith("+"):
                out = hline.replace("+", "//fix_flaw_line_below:\n//", 1)
            elif hline.startswith("-"):
                out = hline.replace("-", "//flaw_line_below:\n", 1)
            else:
                continue
            if not out.endswith("\n"):
                out += "\n"
            patched_lines.append(out)

        # 소스 커서를 패치 범위 끝으로 이동 (new_len 기준)
        cursor = min(end_idx, len(src_lines))

    # 마지막 테일 복사
    patched_lines.extend(src_lines[cursor:])

    # 파일 덮어쓰기
    with open(patched_file_path, "w") as after:
        after.writelines(patched_lines)

    return patched_file_path

def extract_functions(patched_file_path, lang_type, filename, project, CWE_ID, vulnerable_functions, vulnerable_count, file_counter):
    # 함수 라인 번호 추출 및 취약 함수 판별
    func_starts = list_function_starts(patched_file_path, "c" if lang_type == "c" else "c++")
    if len(func_starts) > 0:
        for start_line in func_starts:
            block_result = read_function_block(patched_file_path, start_line)
            if block_result is None:
                continue
            func_body, end_line = block_result
            if "//flaw_line_below:" in func_body or "//fix_flaw_line_below:\n//" in func_body:
                # 취약 함수 발견: 카운트 증가 및 파일 저장
                vulnerable_count += 1
                vulnerable_functions.append((func_body, start_line, lang_type, filename))
                
                # 취약 함수 저장 (vul 디렉토리)
                vul_dir = SPLIT_ROOT / "vul" / project / CWE_ID
                vul_dir.mkdir(parents=True, exist_ok=True)
                vul_file_path = vul_dir / f"{CWE_ID}_add_patch_{end_line}_{filename}"
                with open(vul_file_path, "w+") as vul_file:
                    vul_file.write(func_body)
                
                # 취약 함수 저장 (vul0 디렉토리)
                vul0_dir = SPLIT_ROOT / "vul0" / project
                vul0_dir.mkdir(parents=True, exist_ok=True)
                file_name = str(file_counter)
                vul0_file_path = vul0_dir / f"{file_name}.{lang_type}"
                with open(vul0_file_path, "w+") as vul0_file:
                    vul0_file.write(func_body)
                file_counter += 1
            else:
                # 비취약 함수 저장 (nonevul 디렉토리)
                nonevul_dir = SPLIT_ROOT / "nonevul" / project
                nonevul_dir.mkdir(parents=True, exist_ok=True)
                nonevul_file_path = nonevul_dir / f"add_patch_{end_line}_{filename}"
                with open(nonevul_file_path, "w+") as nonevul_file:
                    nonevul_file.write(func_body)
        print("一共有 %d 个" % vulnerable_count)
    
    return vulnerable_functions, vulnerable_count, file_counter

def mark_patch_and_extract_funcs(lang_type, sourcefile_dir, patchfile_dir, filename, file_dir, project, CWE_ID, vulnerable_functions, vulnerable_count, file_counter, expanded_rows):
    # 패치 파일 분석: diff 블록 파싱
    hunks = collect_hunks(patchfile_dir)

    # 원본과 출력 준비
    with open(sourcefile_dir, "r") as before:
        src_lines = before.readlines()

    patched_file_path = PATCH_ROOT / lang_type / project / CWE_ID / file_dir / f"add_patch_{filename}"
    patched_file_path.parent.mkdir(parents=True, exist_ok=True)

    patched_lines = []
    cursor = 0

    for hunk in hunks:
        start_idx = max(hunk.new_start - 1, 0)
        end_idx = max(start_idx + hunk.new_len, start_idx)

        patched_lines.extend(src_lines[cursor:start_idx])

        for hline in hunk.hunk_lines[1:]:
            if hline.startswith("@@"):
                continue
            if hline.startswith("+"):
                out = hline.replace("+", "//fix_flaw_line_below:\n//", 1)
            elif hline.startswith("-"):
                out = hline.replace("-", "//flaw_line_below:\n", 1)
            else:
                continue
            if not out.endswith("\n"):
                out += "\n"
            patched_lines.append(out)

        cursor = min(end_idx, len(src_lines))

    patched_lines.extend(src_lines[cursor:])

    with open(patched_file_path, "w") as after:
        after.writelines(patched_lines)

    # 함수 라인 번호 추출 및 취약 함수 판별
    func_starts = list_function_starts(patched_file_path, "c" if lang_type == "c" else "c++")
    if len(func_starts) > 0:
        for start_line in func_starts:
            block_result = read_function_block(patched_file_path, start_line)
            if block_result is None:
                continue
            func_body, end_line = block_result
            if "//flaw_line_below:" in func_body or "//fix_flaw_line_below:\n//" in func_body:
                # 취약 함수 발견: 카운트 증가 및 파일 저장
                vulnerable_count += 1
                vulnerable_functions.append((func_body, start_line, lang_type, filename))
                
                # 취약 함수 저장 (vul 디렉토리)
                vul_dir = SPLIT_ROOT / "vul" / project / CWE_ID
                vul_dir.mkdir(parents=True, exist_ok=True)
                vul_file_path = vul_dir / f"{CWE_ID}_add_patch_{end_line}_{filename}"
                with open(vul_file_path, "w+") as vul_file:
                    vul_file.write(func_body)
                
                # 취약 함수 저장 (vul0 디렉토리)
                vul0_dir = SPLIT_ROOT / "vul0" / project
                vul0_dir.mkdir(parents=True, exist_ok=True)
                file_name = str(file_counter)
                vul0_file_path = vul0_dir / f"{file_name}.{lang_type}"
                with open(vul0_file_path, "w+") as vul0_file:
                    vul0_file.write(func_body)
                file_counter += 1
            else:
                # 비취약 함수 저장 (nonevul 디렉토리)
                nonevul_dir = SPLIT_ROOT / "nonevul" / project
                nonevul_dir.mkdir(parents=True, exist_ok=True)
                nonevul_file_path = nonevul_dir / f"add_patch_{end_line}_{filename}"
                with open(nonevul_file_path, "w+") as nonevul_file:
                    nonevul_file.write(func_body)
        print("一共有 %d 个" % vulnerable_count)
    
    return vulnerable_functions, vulnerable_count, file_counter

def append_funcs(row, vulnerable_functions, file_counter, expanded_rows):
    # 결과 행 생성: 취약 함수별로 행 확장
    is_vulnerable = len(vulnerable_functions) > 0
    if not is_vulnerable:
        record_copy = row.to_dict()
        record_copy["vul"] = 0
        record_copy["vul_func_with_fix"] = ""
        expanded_rows.append(record_copy)
    else:
        for func_body, start_line, lang, file_name in vulnerable_functions:
            record_copy = row.to_dict()
            record_copy["vul"] = 1
            record_copy["vul_func_with_fix"] = func_body
            expanded_rows.append(record_copy)
    return expanded_rows

def main():
    parser = argparse.ArgumentParser(description='Process VP-Bench dataset to extract vulnerable functions.')
    parser.add_argument('--input_csv', required=True, help='Input CSV file path')
    parser.add_argument('--output_csv', required=True, help='Output CSV file path')
    args = parser.parse_args()
    
    dataset_df = pd.read_csv(args.input_csv)
    
    expanded_records = []
    vul_count = 0
    file_id = 1
    # ensure columns
    if "vul" not in dataset_df.columns:
        dataset_df["vul"] = 0
    if "vul_func_with_fix" not in dataset_df.columns:
        dataset_df["vul_func_with_fix"] = ""

    for row_index, record in dataset_df.iterrows():
        try:
            cwe_id = DEFAULT_CWE_ID
            repo_name = record["project"]
            vulnerable_functions = []
            commit_hash = record["commit_id"]
            changed_files = [json.loads(i) for i in record["files_changed"].split("<_**next**_>")]
            
            for changed_file in changed_files:
                filename, dir_path, raw_url, patch, basename, ext = get_file_info(changed_file, commit_hash)
                source_file_path, patch_file_path = download_src_and_patches(raw_url, patch, ext, repo_name, cwe_id, dir_path, filename, basename)
                language = determine_language(ext)
                if language is None:
                    continue
                patched_file_path = apply_patches(language, source_file_path, patch_file_path, filename, dir_path, repo_name, cwe_id)
                vulnerable_functions, vul_count, file_id = extract_functions(patched_file_path, language, filename, repo_name, cwe_id, vulnerable_functions, vul_count, file_id)
            expanded_records = append_funcs(record, vulnerable_functions, file_id, expanded_records)
        except Exception as e:
            traceback.print_exc(file=sys.stdout)
            print("reason", e)
            print("\n index:"+str(row_index)+ "！")
            continue

    # expand rows: one record per vulnerable function (or single non-vul record)
    dataset_df = pd.DataFrame(expanded_records)

    dataset_df.to_csv(args.output_csv, index=False)

if __name__ == "__main__":
    main()
