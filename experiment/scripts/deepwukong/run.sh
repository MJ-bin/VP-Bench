#!/bin/bash

# Function
configure_and_prepare() {
    local argument=$1
    local ds_name=$(dirname "$argument")
    local project_name=$(basename "$argument")
    shift 3  # Remove the first 3 args to pass the rest to deepwukong_pipeline.sh

    # Configure environment
    if [ "$argument" = "all" ]; then
        docker exec deepwukong bash -lc "sed -i 's|/data/dataset/.*_dataset\.csv|/data/dataset/Real_Vul_data.csv|g' config/config.yaml"
        docker exec deepwukong bash -lc "sed -i 's|project_name: ".*"|project_name: "all"|g' config/config.yaml"
    else
        docker exec deepwukong bash -lc "sed -i 's|\"/data/dataset/.*\.csv\"|\"/data/dataset/${ds_name}-${project_name}_dataset.csv\"|g' config/config.yaml"
        docker exec deepwukong bash -lc "sed -i 's|project_name: \".*\"|project_name: \"${argument}\"|g' config/config.yaml"
    fi

    # Prepare DS
    docker exec deepwukong bash -lc "mkdir -p /data/dataset && ./deepwukong_pipeline.sh \"${argument}\""
}

# Arguments
FIRST_ARGUMENT="RealVul_Dataset/jasper"
SECOND_ARGUMENT="VP-Bench_Test_Dataset/jasper"

# prepare train dataset
configure_and_prepare $FIRST_ARGUMENT
# train model
docker exec deepwukong bash -lc "SLURM_TMPDIR=. python run.py -c ./config/config.yaml"

# prepare test dataset
configure_and_prepare $SECOND_ARGUMENT

# evaluate
echo "Warning: final model path is hardcoded. Please modify if necessary."
docker exec -w /code/models/DeepWukong -e PYTORCH_JIT=0 -e SLURM_TMPDIR=. deepwukong bash -lc "python evaluate.py ./ts_logger/lightning_logs/version_0/checkpoints/final_model.ckpt --root_folder_path ./data --split_folder_name $SECOND_ARGUMENT"