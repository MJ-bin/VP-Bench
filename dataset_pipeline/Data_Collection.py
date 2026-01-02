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
TEMP_DIR = os.environ["SLURM_TMPDIR"]

def get_project_folder(project):
    """프로젝트 폴더 경로 반환 (Chrome 예외 처리)"""
    return join(TEMP_DIR, "chromium" if project == "Chrome" else project)

def process_project(project, bigvul_data, args):
    """프로젝트별 데이터 처리"""
    print(f"{project} started!")
    
    def generate_neg_files(files, dataset_type, commit_hash):
        global TOTAL_FILE_COUNT
        data = []
        for old_file_path in tqdm(files, total=len(files)):
            _, file_extension = os.path.splitext(old_file_path)
            new_file_name_path = str(TOTAL_FILE_COUNT)
            if file_extension in FILE_EXTENSIONS:
                file_dict = {}
                file_dict["commit_hash"] = commit_hash
                file_dict["unique_id"] = "/".join(old_file_path.split("/")[4:])
                file_dict["vulnerable_line_numbers"] = ""
                file_dict["dataset_type"] = dataset_type
                shutil.copyfile(old_file_path, os.path.join(output_folder, new_file_name_path))
                TOTAL_FILE_COUNT += 1
                data.append(file_dict)
        return data
    
    df1 = bigvul_data[(bigvul_data["flaw_line_index"].notnull()) & (bigvul_data["project"] == project)][["commit_id", "unique_id", "flaw_line_index"]]
    commits = set()
    project_folder = get_project_folder(project)
    if not exists(project_folder):
        os.system(f"git clone {PROJECT_GIT_URLS[project]} {project_folder}")
    gr = Git(project_folder)
    for i in gr.get_list_commits():
        commits.add(i.hash)
    commit_dates = []
    for _, row in df1.iterrows():
        if row["commit_id"] in commits:
            commit_dates.append(gr.get_commit(row["commit_id"]).committer_date)
        else:
            commit_dates.append(None)
    df1["commit_date"] = commit_dates
    df1 = df1.dropna(subset=["commit_date"])
    df1["commit_date"] = pd.to_datetime(df1["commit_date"], utc=True)
    train_last_date = df1["commit_date"].max() - timedelta(days=30)
    test_last_date = df1["commit_date"].max() - timedelta(days=2)
    train_commits = df1[df1["commit_date"] <= train_last_date]["commit_id"].unique()
    test_commits = df1[(df1["commit_date"] > train_last_date) & (df1["commit_date"] <= test_last_date)]["commit_id"].unique()
    train_last_commit_hash = df1[df1["commit_id"].isin(train_commits)]["commit_date"].idxmax()
    test_last_commit_hash = df1[df1["commit_id"].isin(test_commits)]["commit_date"].idxmax()
    if pd.isna(train_last_commit_hash):
        train_last_commit_hash = df1["commit_date"].idxmax()
    if pd.isna(test_last_commit_hash):
        test_last_commit_hash = df1["commit_date"].idxmax()
    train_last_commit_hash = df1.loc[train_last_commit_hash, "commit_id"]
    test_last_commit_hash = df1.loc[test_last_commit_hash, "commit_id"]
    main_branch = list(gr.get_head().branches)[0]
    
    # Prepare output folder
    output_folder = join(TEMP_DIR, f"{project}_source_code", "source_code")
    if not exists(output_folder):
        os.makedirs(output_folder)
    global TOTAL_FILE_COUNT
    TOTAL_FILE_COUNT = 0
    
    gr.checkout(train_last_commit_hash)
    print("Current Branch:", gr.get_head().branches)
    train_negative_files = gr.files()
    train_neg_data = generate_neg_files(train_negative_files, "train", train_last_commit_hash)
    gr.checkout(test_last_commit_hash)
    print("Current Branch:", gr.get_head().branches)
    test_negative_files = gr.files()
    test_neg_data = generate_neg_files(test_negative_files, "test", test_last_commit_hash)
    gr.checkout(main_branch)
    df1["unique_id"] = df1["unique_id"].astype(str)
    df1 = df1.drop(["commit_date"], axis=1)
    final_dataframe = pd.concat([df1, pd.DataFrame(train_neg_data + test_neg_data)])
    final_dataframe["file_name"] = [f"{i}" for i in range(0, final_dataframe.shape[0])]
    final_dataframe.to_csv(args.output_csv, index=False)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    tar_path = os.path.join(script_dir, "VP-Bench_Dataset/output/jasper", f"{project}_source_code.tar.gz")
    os.chdir(join(TEMP_DIR, f"{project}_source_code/"))
    os.system(f"tar -cf {tar_path} source_code/")
    print(f"{project} ended")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input-csv', default="./dataset_pipeline/VP-Bench_Dataset/output/jasper/VP-Bench_jasper_files_changed_with_targets.csv")
    parser.add_argument('--output-csv', default="./dataset_pipeline/VP-Bench_Dataset/output/jasper/jasper_dataset.csv")
    args = parser.parse_args()

    projects = ["jasper"]  # ["FFmpeg","ImageMagick","jasper","krb5","openssl","php-src","qemu","tcpdump","linux","Chrome"]
    bigvul_data = pd.read_csv(args.input_csv)

    for project in projects:
        process_project(project, bigvul_data, args)


if __name__ == "__main__":
    main()