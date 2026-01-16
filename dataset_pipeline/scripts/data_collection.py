#!/usr/bin/env python3

import pandas as pd
from tqdm import tqdm
import os
from os.path import join,exists
import pydriller
from pydriller import Repository, Git
from datetime import datetime, timedelta
from collections import Counter
import shutil
import argparse
from pathlib import Path

# Constants
PROJECT_GIT_URLS = {
    "FFmpeg": "https://github.com/FFmpeg/FFmpeg.git",
    "ImageMagick": "https://github.com/ImageMagick/ImageMagick.git",
    "jasper": "https://github.com/jasper-software/jasper.git",
    "krb5": "https://github.com/krb5/krb5.git",
    "openssl": "https://github.com/openssl/openssl.git",
    "php-src": "https://github.com/php/php-src.git",
    "qemu": "https://github.com/qemu/qemu.git",
    "tcpdump": "https://github.com/the-tcpdump-group/tcpdump.git",
    "linux": "https://github.com/torvalds/linux.git",
    "Chrome": "https://github.com/chromium/chromium.git"
}
FILE_EXTENSIONS = {".c", ".cpp", ".cxx", ".cc", ".h"}
BASE_DIR = Path(__file__).resolve().parent.parent
LABELS_DEFAULT = ['train_val', 'test']

def generate_neg_files(files, dataset_type, commit_hash, output_folder):
    global TOTAL_FILE_COUNT
    data = []
    for old_file_path in tqdm(files, total=len(files)):
        _, file_extension = os.path.splitext(old_file_path)
        new_file_name_path = str(TOTAL_FILE_COUNT)
        if file_extension in FILE_EXTENSIONS:
            file_dict = {}
            file_dict["commit_hash"] = commit_hash
            # file_dict["unique_id"] = "/".join(old_file_path.split("/")[4:])
            file_dict["vulnerable_line_numbers"] = ""
            file_dict["dataset_type"] = dataset_type
            shutil.copyfile(old_file_path, os.path.join(output_folder, new_file_name_path))
            TOTAL_FILE_COUNT += 1
            data.append(file_dict)
    return data

def process_project(project, bigvul_data, args):
    """프로젝트별 데이터 처리"""
    print(f"{project} started!")
    PROJECT_DIR = Path(args.output_dir) / project
    # Keep git repos and source snapshots inside the project output
    REPOSITORIES_DIR = str(PROJECT_DIR / "repository")
    
    if args.mode == "vpbench":
        df1 = bigvul_data[(bigvul_data["flaw_line_index"].notnull()) & (bigvul_data["project"] == project)][["commit_hash", "unique_id", "flaw_line_index"]]
        # processed_func 매핑으로 양성 코드 복원
        processed_funcs = bigvul_data[bigvul_data["unique_id"].isin(df1["unique_id"])]
        func_map = processed_funcs.set_index("unique_id")["processed_func"].to_dict()
        df1["processed_func"] = df1["unique_id"].map(func_map)
    elif args.mode == "realvul":
        df1 = bigvul_data[(bigvul_data["vulnerable_line_numbers"].notnull())][["commit_hash", "file_name", "vulnerable_line_numbers"]]
    commits = set()
    hashes = list()
    project_folder = os.path.join(REPOSITORIES_DIR, "chromium" if project == "Chrome" else project) # get_project_folder(project)
    # Check if folder exists and is a valid git repository
    git_folder = os.path.join(project_folder, ".git")
    if not exists(git_folder):
        os.makedirs(project_folder, exist_ok=True)
        os.system(f"git clone {PROJECT_GIT_URLS[project]} {project_folder}")
    gr = Git(project_folder)
    # for i in gr.get_list_commits():
    #     commits.add(i.hash)
    commit_dates = []
    for _, row in df1.iterrows():
        try:
            commit_dates.append(gr.get_commit(row["commit_hash"]).committer_date)
        except Exception:
            commit_dates.append(None)
    df1["commit_date"] = commit_dates
    df1 = df1.dropna(subset=["commit_date"])
    if df1.empty:
        df1.to_csv(args.output, index=False)
        print(f"{project} ended with no valid commits.")
        return
    df1["commit_date"] = pd.to_datetime(df1["commit_date"], utc=True)
    df1 = df1.sort_values(by="commit_date").reset_index(drop=True)

    if args.labels == LABELS_DEFAULT:
        # 커밋 시간 기준 정렬 후 80/20 스플릿
        split_idx = int(df1.shape[0] * 0.8)
        df1.loc[: split_idx - 1, "dataset_type"] = "train_val"
        df1.loc[split_idx:, "dataset_type"] = "test"
        # 구간별 마지막 커밋 해시 선택
        hashes.append(df1.loc[split_idx - 1, "commit_hash"] if split_idx > 0 else df1.loc[df1.index[-1], "commit_hash"])
        hashes.append(df1.loc[df1.index[-1], "commit_hash"])
    else:
        df1["dataset_type"] = args.labels[0]
        # 전체 마지막 커밋 해시만 선택
        hashes.append(df1.loc[df1.index[-1], "commit_hash"])
    main_branch = list(gr.get_head().branches)[0]
    
    # Prepare output folder (프로젝트별 분리)
    output_folder = str(PROJECT_DIR / "source_code")
    if not exists(output_folder):
        os.makedirs(output_folder)
    global TOTAL_FILE_COUNT
    TOTAL_FILE_COUNT = 0

    if args.mode == "vpbench":
        # 양성 코드 스냅샷 먼저 기록 (컬럼 일관성: vulnerable_line_numbers 사용)
        df1["unique_id"] = df1["unique_id"].astype(str)
        df1.rename(columns={"flaw_line_index": "vulnerable_line_numbers"}, inplace=True)
        for _, row in tqdm(df1.iterrows(), total=len(df1)):
            if pd.isna(row.get("processed_func", None)):
                continue
            new_file_name_path = str(TOTAL_FILE_COUNT)
            with open(os.path.join(output_folder, new_file_name_path), "w") as f:
                f.write(str(row["processed_func"]))
            TOTAL_FILE_COUNT += 1

    neg_data = []
    for label, h in zip(args.labels, hashes):
        gr.checkout(h)
        print("Current Branch:", gr.get_head().branches)
        negative_files = gr.files()
        neg_data.append(generate_neg_files(negative_files, label, h, output_folder))
    
    gr.checkout(main_branch)
    df1 = df1.drop(["commit_date"], axis=1)
    if "processed_func" in df1.columns:
        df1 = df1.drop(["processed_func"], axis=1)
    final_dataframe = pd.concat([df1, pd.DataFrame([x for sub in neg_data for x in sub])], ignore_index=True)
    final_dataframe["file_name"] = [f"{i}" for i in range(0, final_dataframe.shape[0])]
    final_dataframe.to_csv(args.output, index=False)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    tar_path = PROJECT_DIR / f"{project}_source_code.tar.gz"
    os.chdir(PROJECT_DIR)
    os.system(f"tar -cf {tar_path} ./source_code")
    print(f"{project} ended")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input')
    parser.add_argument('--output')
    parser.add_argument('--mode', choices=['vpbench', 'realvul'])
    parser.add_argument('--project')
    parser.add_argument('--labels', help='Path to labels file', nargs='+', required=True)
    parser.add_argument('--output-dir', help='Output directory for project processing')
    args = parser.parse_args()
    bigvul_data = pd.read_csv(args.input)
    process_project(args.project, bigvul_data, args)


if __name__ == "__main__":
    main()