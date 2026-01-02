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
OUTPUT_BASE = "./VP-Bench_Dataset/output/jasper/"
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
def list_function_starts(filename,lang_type):
    # found = False
    #cmd = "ctags -x --c-kinds=fp " + filename + " | grep " + funcname
    cmd = "ctags -x --"+lang_type+"-kinds=f " + filename

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
    print("opening " + filename + " on line " + str(line_num))

    code = ""
    bracket_depth = 0
    in_body = False

    with open(filename, "r") as f:
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
def parse_hunk(filename, diff_start_line, count, len_diff_start_lines, hunks):
    """
    diff 블록을 파싱하여 anchor 정보를 추출합니다.
    
    이 함수는 주어진 diff 파일에서 특정 diff 블록을 분석하여,
    before/after 라인 정보, minus/plus 라인 수, 위치 등을 계산하고
    hunks 리스트에 추가합니다.
    
    Args:
        filename (str): diff 파일 경로
        diff_start_line (int): diff 블록 시작 라인
        count (int): 현재 블록 인덱스
        len_diff_start_lines (int): 총 diff 블록 수
        hunks (list): anchor 정보를 저장할 리스트
    
    Returns:
        list: 업데이트된 hunks 리스트
    """
    removed_count = 0  # 삭제된 라인 수
    added_count = 0   # 추가된 라인 수
    old_range = None    # @@ 라인의 before 정보 (시작 라인, 라인 수)
    new_range = None     # @@ 라인의 after 정보 (시작 라인, 라인 수)
    hunk_header_line = None  # @@ 라인의 라인 번호
    removed_offsets = []   # 삭제된 라인의 상대 위치 리스트
    added_offsets = []    # 추가된 라인의 상대 위치 리스트
    hunk_lines = []       # 패치 라인들
    current_block = 0    # 현재 블록 번호
    
    # 파일을 라인별로 순회하며 diff 블록 파싱
    for j, l in iter_patch_lines(filename):
        # 마지막 diff 블록인 경우
        if count == len_diff_start_lines:
            # diff 블록의 끝에 도달한 경우
            if j == diff_start_line - 1:
                hunk_lines.append(l)
                # 삭제/추가 라인 카운트 및 위치 기록
                if l.startswith("-"):
                    removed_count += 1
                    removed_offsets.append(j - hunk_header_line)
                if l.startswith("+"):
                    added_count += 1
                    added_offsets.append(j - hunk_header_line)
                current_block = j
                # before/after 정보를 정수 리스트로 변환
                old_range = list(map(int, old_range))
                new_range = list(map(int, new_range))
                # hunks 리스트에 정보 추가
                if len(hunks) == 0:
                    hunks.append(HunkInfo(
                        old_start=old_range[0], old_len=old_range[1], new_start=new_range[0], new_len=new_range[1],
                        removed_count=removed_count, added_count=added_count, removed_offsets=removed_offsets, added_offsets=added_offsets,
                        hunk_lines=hunk_lines, insert_after=new_range[0], diff_value=removed_count, prev_new_end=0
                    ))
                else:
                    diff_value = hunks[-1].diff_value + removed_count
                    insert_after = new_range[0] + hunks[-1].diff_value
                    last_end = hunks[-1].new_start + hunks[-1].new_len - 1
                    hunks.append(HunkInfo(
                        old_start=old_range[0], old_len=old_range[1], new_start=new_range[0], new_len=new_range[1],
                        removed_count=removed_count, added_count=added_count, removed_offsets=removed_offsets, added_offsets=added_offsets,
                        hunk_lines=hunk_lines, insert_after=insert_after, diff_value=diff_value, prev_new_end=last_end
                    ))
                break

            # diff 블록 내의 라인을 처리
            if current_block <= j < diff_start_line - 1:
                hunk_lines.append(l)
                # @@ 라인 파싱: before/after 정보 추출
                if l.startswith("@@ "):
                    hunk_header_line = j
                    pos = l.find("@@ ")
                    end = l.find(" @@ ")
                    modified = l[pos + 3:end]
                    modified = modified.split(" ")
                    old_range = modified[0].replace("-", "").split(",")
                    new_range = modified[1].replace("+", "").split(",")

                # 삭제/추가 라인 카운트 및 위치 기록
                if l.startswith("-"):
                    removed_count += 1
                    removed_offsets.append(j - hunk_header_line)
                if l.startswith("+"):
                    added_count += 1
                    added_offsets.append(j - hunk_header_line)
        # 마지막 블록이 아닌 경우
        elif j < current_block:
            continue
        else:
            current_block = j
            # before/after 정보가 있는 경우 hunks에 추가
            if old_range is not None and new_range is not None:
                old_range = list(map(int, old_range))
                new_range = list(map(int, new_range))
                if len(hunks) == 0:
                    hunks.append(HunkInfo(
                        old_start=old_range[0], old_len=old_range[1], new_start=new_range[0], new_len=new_range[1],
                        removed_count=removed_count, added_count=added_count, removed_offsets=removed_offsets, added_offsets=added_offsets,
                        hunk_lines=hunk_lines, insert_after=new_range[0], diff_value=removed_count, prev_new_end=0
                    ))
                else:
                    diff_value = hunks[-1].diff_value + removed_count
                    insert_after = new_range[0] + hunks[-1].diff_value
                    last_end = hunks[-1].new_start + hunks[-1].new_len - 1
                    hunks.append(HunkInfo(
                        old_start=old_range[0], old_len=old_range[1], new_start=new_range[0], new_len=new_range[1],
                        removed_count=removed_count, added_count=added_count, removed_offsets=removed_offsets, added_offsets=added_offsets,
                        hunk_lines=hunk_lines, insert_after=insert_after, diff_value=diff_value, prev_new_end=last_end
                    ))
            break
    return hunks

def collect_hunks(filename,diff_start_lines):
    hunks = []
    for count, diff_start_line in enumerate(diff_start_lines, 1):
        hunks = parse_hunk(filename, diff_start_line, count, len(diff_start_lines), hunks)
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
    if not os.path.exists("patchAll0206/" + ext + '/' + project + '/' + CWE_ID + '/' + dir_path):
        os.makedirs("patchAll0206/" + ext + '/' + project + '/' + CWE_ID + '/' + dir_path)
    source_file_path = "patchAll0206/" + ext + '/' + project + '/' + CWE_ID + '/' + dir_path + '/' + filename 
    patch_file_path = "patchAll0206/" + ext + '/' + project + '/' + CWE_ID + '/' + dir_path + '/' + basename + '_' + 'patch.txt'
    with open(source_file_path, "w+") as source_file, open(patch_file_path, "w+") as patch_file:
        source_file.write(source_text)
        patch_file.write(patch)
    return source_file_path, patch_file_path

def determine_language(ext):
    if ext == "c":
        return "c"
    elif ext in ["C", "cc", "cxx", "cpp", "c++", "Cpp"]:
        return "cpp"
    else:
        return None

def apply_patches(lang_type, sourcefile_dir, patchfile_dir, filename, file_dir, project, CWE_ID):
    # 패치 파일 분석: diff 블록 파싱
    num = list_hunk_starts(patchfile_dir)
    hunks = collect_hunks(patchfile_dir, num)
    hunk_index = 0
    total_hunks = len(hunks)
    for hunk in hunks:
        hunk_index += 1
        new_start = hunk.new_start
        new_len = hunk.old_len + hunk.added_count
        new_end = new_start + hunk.new_len - 1
        prev_new_end = hunk.prev_new_end
        patch_written = False
        
        # 패치 적용된 파일 생성
        patched_file_path = "patchAll0206/" + lang_type + '/' + project + '/' + CWE_ID + '/' + file_dir + '/' + "add_patch_" + filename
        # ensure add_patch directory exists
        patched_dir = os.path.dirname(patched_file_path)
        if not os.path.exists(patched_dir):
            os.makedirs(patched_dir)
        with open(sourcefile_dir, "r") as before, open(patched_file_path, "a") as after:
            lines = before.readlines()
            total_lines = len(lines)
            for i in range(total_lines):
                if prev_new_end - 1 < i <= new_end - 1:
                    if i == 0:
                        after.write(lines[i])
                        continue
                    if (new_start - 1 <= i <= new_end - 1):
                        if patch_written == False:
                            for hunk_line in hunk.hunk_lines[1:]:
                                if hunk_line.startswith("+"):
                                    hunk_line = hunk_line.replace("+", "//fix_flaw_line_below:\n//", 1)
                                if hunk_line.startswith("-"):
                                    hunk_line = hunk_line.replace("-", "//flaw_line_below:\n", 1)
                                if not hunk_line.endswith("\n"):
                                    hunk_line = hunk_line + "\n"
                                after.write(hunk_line)
                            patch_written = True
                    else:
                        after.write(lines[i])
                if hunk_index == total_hunks and new_end < total_lines and i > new_end - 1:
                    after.write(lines[i])
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
                vul_dir = "./split0206/vul" + '/' + project + '/' + CWE_ID
                if not os.path.exists(vul_dir):
                    os.makedirs(vul_dir)
                vul_file_path = vul_dir + '/' + CWE_ID + "_" + "add_patch_" + str(end_line) + "_" + filename
                vul_file_dir = os.path.dirname(vul_file_path)
                if not os.path.exists(vul_file_dir):
                    os.makedirs(vul_file_dir)
                with open(vul_file_path, "w+") as vul_file:
                    vul_file.write(func_body)
                
                # 취약 함수 저장 (vul0 디렉토리)
                vul0_dir = "./split0206/vul0" + '/' + project
                if not os.path.exists(vul0_dir):
                    os.makedirs(vul0_dir)
                file_name = str(file_counter)
                vul0_file_path = vul0_dir + '/' + file_name + '.' + lang_type
                with open(vul0_file_path, "w+") as vul0_file:
                    vul0_file.write(func_body)
                file_counter += 1
            else:
                # 비취약 함수 저장 (nonevul 디렉토리)
                nonevul_dir = "./split0206/nonevul" + '/' + project
                if not os.path.exists(nonevul_dir):
                    os.makedirs(nonevul_dir)
                nonevul_file_path = nonevul_dir + '/' + "add_patch_" + str(end_line) + "_" + filename
                nonevul_file_dir = os.path.dirname(nonevul_file_path)
                if not os.path.exists(nonevul_file_dir):
                    os.makedirs(nonevul_file_dir)
                with open(nonevul_file_path, "w+") as nonevul_file:
                    nonevul_file.write(func_body)
        print("一共有 %d 个" % vulnerable_count)
    
    return vulnerable_functions, vulnerable_count, file_counter

def mark_patch_and_extract_funcs(lang_type, sourcefile_dir, patchfile_dir, filename, file_dir, project, CWE_ID, vulnerable_functions, vulnerable_count, file_counter, expanded_rows):
    # 패치 파일 분석: diff 블록 파싱
    num = list_hunk_starts(patchfile_dir)
    hunks = collect_hunks(patchfile_dir, num)
    hunk_index = 0
    total_hunks = len(hunks)
    for hunk in hunks:
        hunk_index += 1
        new_start = hunk.new_start
        new_len = hunk.old_len + hunk.added_count
        new_end = new_start + hunk.new_len - 1
        prev_new_end = hunk.prev_new_end
        patch_written = False
        
        # 패치 적용된 파일 생성
        patched_file_path = "patchAll0206/" + lang_type + '/' + project + '/' + CWE_ID + '/' + file_dir + '/' + "add_patch_" + filename
        # ensure add_patch directory exists
        patched_dir = os.path.dirname(patched_file_path)
        if not os.path.exists(patched_dir):
            os.makedirs(patched_dir)
        with open(sourcefile_dir, "r") as before, open(patched_file_path, "a") as after:
            lines = before.readlines()
            total_lines = len(lines)
            for i in range(total_lines):
                if prev_new_end - 1 < i <= new_end - 1:
                    if i == 0:
                        after.write(lines[i])
                        continue
                    if (new_start - 1 <= i <= new_end - 1):
                        if patch_written == False:
                            for hunk_line in hunk.hunk_lines[1:]:
                                if hunk_line.startswith("+"):
                                    hunk_line = hunk_line.replace("+", "//fix_flaw_line_below:\n//", 1)
                                if hunk_line.startswith("-"):
                                    hunk_line = hunk_line.replace("-", "//flaw_line_below:\n", 1)
                                if not hunk_line.endswith("\n"):
                                    hunk_line = hunk_line + "\n"
                                after.write(hunk_line)
                            patch_written = True
                    else:
                        after.write(lines[i])
                if hunk_index == total_hunks and new_end < total_lines and i > new_end - 1:
                    after.write(lines[i])
    
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
                vul_dir = "./split0206/vul" + '/' + project + '/' + CWE_ID
                if not os.path.exists(vul_dir):
                    os.makedirs(vul_dir)
                vul_file_path = vul_dir + '/' + CWE_ID + "_" + "add_patch_" + str(end_line) + "_" + filename
                vul_file_dir = os.path.dirname(vul_file_path)
                if not os.path.exists(vul_file_dir):
                    os.makedirs(vul_file_dir)
                with open(vul_file_path, "w+") as vul_file:
                    vul_file.write(func_body)
                
                # 취약 함수 저장 (vul0 디렉토리)
                vul0_dir = "./split0206/vul0" + '/' + project
                if not os.path.exists(vul0_dir):
                    os.makedirs(vul0_dir)
                file_name = str(file_counter)
                vul0_file_path = vul0_dir + '/' + file_name + '.' + lang_type
                with open(vul0_file_path, "w+") as vul0_file:
                    vul0_file.write(func_body)
                file_counter += 1
            else:
                # 비취약 함수 저장 (nonevul 디렉토리)
                nonevul_dir = "./split0206/nonevul" + '/' + project
                if not os.path.exists(nonevul_dir):
                    os.makedirs(nonevul_dir)
                nonevul_file_path = nonevul_dir + '/' + "add_patch_" + str(end_line) + "_" + filename
                nonevul_file_dir = os.path.dirname(nonevul_file_path)
                if not os.path.exists(nonevul_file_dir):
                    os.makedirs(nonevul_file_dir)
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
