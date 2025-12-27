import pandas as pd
from tqdm import tqdm
import os
from os.path import join,exists
import pydriller
from pydriller import Repository, Git
from datetime import datetime, timedelta
from collections import Counter
import shutil
from omegaconf import OmegaConf, DictConfig
from argparse import ArgumentParser
from typing import cast
import pandas as pd




import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--input-csv', default="./dataset_pipeline/VP-Bench_Dataset/output/jasper/VP-Bench_jasper_files_changed_with_targets.csv")
parser.add_argument('--output-csv', default="./dataset_pipeline/VP-Bench_Dataset/output/jasper/jasper_dataset.csv")
args = parser.parse_args()

projects=["jasper"] # ["FFmpeg","ImageMagick","jasper","krb5","openssl","php-src","qemu","tcpdump","linux","Chrome"]
bigvul_data=pd.read_csv(args.input_csv)

# 프로젝트별 git 저장소 URL 매핑 (예시, 실제 URL로 수정 필요)
project_git_urls = {
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

l=os.environ["SLURM_TMPDIR"]
for project in projects:
    print(f"{project} started!")
    #os.system(f"tar -xf /data/project_files/{project}.tar.gz -C {l}")
    df1=bigvul_data[(bigvul_data["flaw_line_index"].notnull())&(bigvul_data["project"]==project)][["commit_id","unique_id","flaw_line_index"]]
    commits=set()
    if project=="Chrome":
        project_folder=join(os.environ["SLURM_TMPDIR"],"chromium")
    else:
        project_folder=join(os.environ["SLURM_TMPDIR"],project)
    if not exists(project_folder):
        os.system(f"git clone {project_git_urls[project]} {project_folder}")
    gr = Git(project_folder)
    for i in gr.get_list_commits():
        commits.add(i.hash)
    commit_dates=[]
    for _,row in df1.iterrows():
        if row["commit_id"] in commits:
            commit_dates.append(gr.get_commit(row["commit_id"]).committer_date.strftime('%Y-%m-%d'))
    
    df1["commit_date"]=commit_dates
    # data_folder=f"/data/{project}" useless
    # if not exists(data_folder):
    #     os.makedirs(data_folder)

    df1['commit_date']=pd.to_datetime(df1['commit_date'])
    df1['commit_date']=df1['commit_date'].dt.strftime('%Y-%m-%d')
    df1.sort_values(by=["commit_date"], inplace=True)
    splits=["train_val"]*int(df1.shape[0]*0.8)+["test"]*(df1.shape[0]-int(df1.shape[0]*0.8))
    df1["dataset_type"]=splits
    
    # os.system(f"tar -xf /data/project_files/{project}.tar.gz -C {l}")
    output_folder= join(os.environ["SLURM_TMPDIR"],f"{project}_source_code","source_code")
    if project=="Chrome":
        project_folder=join(os.environ["SLURM_TMPDIR"],"chromium")
    else:
        project_folder=join(os.environ["SLURM_TMPDIR"],project)
    bigvul_data_partial=bigvul_data[bigvul_data["unique_id"].isin(df1["unique_id"])][["unique_id","processed_func"]]
    dict1=bigvul_data_partial.set_index('unique_id').to_dict("dict")["processed_func"]

    df1['processed_func'] = df1['unique_id'].map(dict1)

    if not exists(output_folder):
            os.makedirs(output_folder)
    TOTAL_FILE_COUNT=0
    for i,row in tqdm(df1.iterrows(),total=len(df1)):
                 new_file_name_path=str(TOTAL_FILE_COUNT)
                 with open(os.path.join(output_folder,new_file_name_path),"w") as f:
                    f.write(row["processed_func"])
                 TOTAL_FILE_COUNT+=1

    df1=df1.drop(["processed_func"],axis=1)
    df1.rename(columns={'flaw_line_index': 'vulnerable_line_numbers'}, inplace=True)
    
    
    def generate_neg_files(files,dataset_type,commit_hash):
        global TOTAL_FILE_COUNT
        data=[]
        for old_file_path in tqdm(files,total=len(files)):
                    _, file_extension = os.path.splitext(old_file_path)
                    new_file_name_path=str(TOTAL_FILE_COUNT)
                    if file_extension in file_extensions:
                         dict1={}
                         dict1["commit_hash"]=commit_hash
                         dict1["unique_id"]="/".join(old_file_path.split("/")[4:])
                         dict1["vulnerable_line_numbers"]=""
                         dict1["dataset_type"]=dataset_type
                         shutil.copyfile(old_file_path,os.path.join(output_folder,new_file_name_path))
                         TOTAL_FILE_COUNT+=1
                         data.append(dict1)
        return data


    file_extensions={".c",".cpp",".cxx",".cc",".h"}


    gr = Git(project_folder)
    main_branch=list(gr.get_head().branches)[0]
    print("Current Branch:",gr.get_head().branches,main_branch)

    train_last_Date=datetime.strptime(df1[df1["dataset_type"]=="train_val"].iloc[-1]["commit_date"],"%Y-%m-%d")+timedelta(days=2)
    train_last_commit=list(Repository(project_folder, to=train_last_Date).traverse_commits())[-1]
    train_last_commit_hash=train_last_commit.hash
    train_last_commit_hash_date= train_last_commit.committer_date.strftime('%Y-%m-%d')
    gr.checkout(train_last_commit_hash)
    print("Current Branch:",gr.get_head().branches)
    train_negative_files=gr.files()
    train_neg_data=generate_neg_files(train_negative_files,"train_val",train_last_commit_hash)
    print("Train Last Date",train_last_commit_hash_date)


    gr.checkout(main_branch)
    print("Current Branch:",gr.get_head().branches)

    test_last_Date=datetime.strptime(df1[df1["dataset_type"]=="test"].iloc[-1]["commit_date"],"%Y-%m-%d")+timedelta(days=2)
    test_last_commit=list(Repository(project_folder, to=test_last_Date).traverse_commits())[-1]
    test_last_commit_hash=test_last_commit.hash
    test_last_commit_hash_date= test_last_commit.committer_date.strftime('%Y-%m-%d')
    print("Test Last Date",test_last_commit_hash_date)

    gr.checkout(test_last_commit_hash)
    print("Current Branch:",gr.get_head().branches)
    test_negative_files=gr.files()
    test_neg_data=generate_neg_files(test_negative_files,"test",test_last_commit_hash)
    gr.checkout(main_branch)

    df1["unique_id"]=df1["unique_id"].astype(str)
    df1=df1.drop(["commit_date"],axis=1)
    final_dataframe=pd.concat([df1,pd.DataFrame(train_neg_data+test_neg_data)])
    final_dataframe["file_name"]=[f"{i}" for i in range(0,final_dataframe.shape[0])]
    final_dataframe.to_csv(args.output_csv,index=False)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    tar_path = os.path.join(script_dir, "VP-Bench_Dataset/output/jasper", f"{project}_source_code.tar.gz")
    os.chdir(join(os.environ["SLURM_TMPDIR"],f"{project}_source_code/"))
    os.system(f"tar -cf {tar_path} source_code/")
    print(f"{project} ended")