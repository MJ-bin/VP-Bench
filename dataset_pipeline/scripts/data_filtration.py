#!/usr/bin/env python3

import pandas as pd
import hashlib
from collections import defaultdict
from tqdm import tqdm
from os.path import join
import os
import pickle
import csv
from pathlib import Path
import argparse
import tarfile
import shutil

def getMD5(s):
    hl = hashlib.md5()
    hl.update(s.encode("utf-8"))
    return hl.hexdigest()

parser = argparse.ArgumentParser()
parser.add_argument('--projects', nargs='+', help='List of projects')
parser.add_argument('--output-dir', help='Output directory')
args = parser.parse_args()
projects = args.projects

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = Path(args.output_dir)

# all_source_code 폴더 생성
all_source_code_dir = OUTPUT_DIR / "all_source_code"
if all_source_code_dir.exists():
    shutil.rmtree(all_source_code_dir)
all_source_code_dir.mkdir(parents=True, exist_ok=True)
TOTAL_FILE_COUNT = 0

with open(OUTPUT_DIR / "real_vul_functions_dataset.csv", "w", encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=["file_name", "unique_id", "target", "vulnerable_line_numbers", "project", "commit_hash", "dataset_type", "processed_func"])
    writer.writeheader()
    for project_name in tqdm(projects, total=len(projects)):
        combined_functions = []  # Reset per project
        project_folder = OUTPUT_DIR / project_name
        functions_folder = project_folder / "all_functions"
        slurm_tmp = Path(os.environ.get("SLURM_TMPDIR", OUTPUT_DIR / project_name / "source_code"))
        SLURM_source_code_path = slurm_tmp / project_name
        SLURM_source_code_path.mkdir(parents=True, exist_ok=True)

        source_code_path = project_folder / f"{project_name}_source_code.tar.gz"
        if not source_code_path.is_file():
            print(f"Source code tarball not found for project {project_name}, skipping.")
            continue
        with tarfile.open(source_code_path, "r:*") as tar:
            tar.extractall(path=SLURM_source_code_path)
        
        # Read from Step 4 output to preserve vulnerable_line_numbers
        csv_data = pd.read_csv(project_folder / f"{project_name}_dataset.csv")
        csv_data["vulnerable_line_numbers"] = csv_data["vulnerable_line_numbers"].fillna("").astype(str)
        csv_data["file_name"] = csv_data["file_name"].astype(str)  # file_name = unique_id
        
        with open(functions_folder / f"{project_name}_new_all_functions.pkl", "rb") as output_file:
            all_functions = pickle.load(output_file)
        vul_functions_hash = defaultdict(list)

        for _, row in csv_data[csv_data["vulnerable_line_numbers"].str.len() > 0].iterrows():
            vul_file = row["file_name"]
            original_file_path = join(SLURM_source_code_path, 'source_code', vul_file)
            with open(original_file_path, "r", encoding="ISO-8859-1") as f:
                source_code = "".join(f.readlines())
                writer.writerow({
                    "unique_id": TOTAL_FILE_COUNT,
                    "file_name": row["file_name"], 
                    "vulnerable_line_numbers": row["vulnerable_line_numbers"], 
                    "dataset_type": row["dataset_type"], 
                    "commit_hash": row["commit_hash"], 
                    "project": project_name, 
                    "target": 1,
                    "processed_func":source_code
                })
                new_filename = TOTAL_FILE_COUNT
                # all_source_code 폴더로 복사
                dest_path = all_source_code_dir / str(new_filename)
                try:
                    shutil.copy2(original_file_path, dest_path)
                except Exception as e:
                    print(f"Error copying {original_file_path}: {e}")
                TOTAL_FILE_COUNT += 1
            vul_hash = getMD5("".join(source_code.split()))
            vul_functions_hash[vul_hash].append([vul_file, project_name])
        for _, row in csv_data[csv_data["vulnerable_line_numbers"].str.len() == 0].iterrows():
            file = row["file_name"]
            original_file_path = join(SLURM_source_code_path, 'source_code', file)
            if file in all_functions:
                with open(original_file_path, "r", encoding="ISO-8859-1") as f:
                    source_code = f.readlines()
                for function in all_functions[file]:
                    non_vul_hash = getMD5("".join("".join(source_code[function["start"] - 1:function["end"]]).split()))
                    if non_vul_hash not in vul_functions_hash:
                        writer.writerow({
                            "file_name": file, 
                            "unique_id": TOTAL_FILE_COUNT,
                            "target": 0, 
                            "vulnerable_line_numbers": "", 
                            "project": project_name, 
                            "commit_hash": row["commit_hash"], 
                            "dataset_type": row["dataset_type"],
                            "processed_func":"".join(source_code[function["start"]-1:function["end"]])
                        })
                        new_filename = TOTAL_FILE_COUNT
                        # all_source_code 폴더로 복사
                        dest_path = all_source_code_dir / str(new_filename)
                        try:
                            shutil.copy2(original_file_path, dest_path.with_suffix(".c"))
                        except Exception as e:
                            print(f"Error copying {original_file_path}: {e}")
                        TOTAL_FILE_COUNT += 1
all_source_code_dirtar_path = OUTPUT_DIR / "all_source_code.tar.gz"
with tarfile.open(all_source_code_dirtar_path, "w:gz") as tar:
    tar.add(all_source_code_dir, arcname="all_source_code")
            