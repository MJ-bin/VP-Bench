import pandas as pd
import hashlib
from collections import defaultdict
from tqdm import tqdm
from os.path import join
import os
import pickle
import shutil
def getMD5(s):
    hl = hashlib.md5()
    hl.update(s.encode("utf-8"))
    return hl.hexdigest()

projects=["FFmpeg","ImageMagick","krb5","openssl","php-src","qemu","tcpdump","jasper","Chrome","linux"]
combined_functions = []
for project_name in tqdm(projects,total=len(projects)):
    project_folder= f"/data/dataset"
    functions_folder = join(project_folder,"all_functions")
    SLURM_source_code_path =  join(os.environ["SLURM_TMPDIR"],project_name,"source_code")

    source_code_path=join(project_folder,f"{project_name}_source_code.tar.gz")
    os.system(f'tar -xf {source_code_path} -C $SLURM_TMPDIR/{project_name}')
    csv_data= pd.read_csv(join(project_folder,f"{project_name}_dataset.csv"))
    csv_data["vulnerable_line_numbers"] = csv_data["vulnerable_line_numbers"].fillna("")
    with open(join(functions_folder,f"{project_name}_new_all_functions.pickle"),"rb") as output_file:
                all_functions=pickle.load(output_file)
    vul_functions_hash=defaultdict(list)


    for _ , row in csv_data[csv_data["vulnerable_line_numbers"].str.len()>0].iterrows():
        vul_file = row["file_name"]
        with open(join(SLURM_source_code_path,vul_file),"r",encoding = "ISO-8859-1") as f:
            source_code = "".join(f.readlines())
                        combined_functions.append({"processed_func":source_code,"target":1,"vulnerable_line_numbers":row["vulnerable_line_numbers"],"project":project_name,"commit_hash":row["commit_hash"],"dataset_type":row["dataset_type"]})
        vul_hash=getMD5("".join(source_code.split()))
        vul_functions_hash[vul_hash].append([vul_file,project_name])
    for _, row in csv_data[csv_data["vulnerable_line_numbers"].str.len()==0].iterrows():
        file = row["file_name"]
        if file in all_functions:
            with open(join(SLURM_source_code_path,file),"r",encoding = "ISO-8859-1") as f:
                source_code = f.readlines()
            for function in all_functions[file]:
                non_vul_hash=getMD5("".join("".join(source_code[function["start"]-1:function["end"]]).split()))
                if non_vul_hash not in vul_functions_hash:
                        combined_functions.append({"processed_func":"".join(source_code[function["start"]-1:function["end"]]),"target":0,"vulnerable_line_numbers":"","project":project_name,"commit_hash":row["commit_hash"],"dataset_type":row["dataset_type"]})
functions_dataset = pd.DataFrame(combined_functions)
functions_dataset.to_csv("/data/dataset/real_vul_functions_dataset.csv",index=False)