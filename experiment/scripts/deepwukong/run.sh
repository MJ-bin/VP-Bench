#!/bin/bash 

# Function
configure_and_prepare() {
    local argument=$1
    local ds_name=$(dirname "$argument")
    local project_name=$(basename "$argument")
    shift 3  # Remove the first 3 args to pass the rest to deepwukong_pipeline.sh

    # Configure environment
    docker exec deepwukong bash -lc "sed -i 's|\"/data/dataset/.*\.csv\"|\"/data/dataset/${ds_name}/Real_Vul_data.csv\"|g' config/config.yaml"
    docker exec deepwukong bash -lc "sed -i 's|project_name: \".*\"|project_name: \"${argument}\"|g' config/config.yaml"

    # Prepare DS
    docker exec deepwukong bash -lc "mkdir -p /data/dataset && ./deepwukong_pipeline.sh \"${argument}\" --enable-archive"
}

# Arguments
PROJECT=$1 # argument for run.sh
TRAIN_DATASET="VP-Bench_Train_Dataset/$PROJECT"
TEST_DATASET="VP-Bench_Test_Dataset/$PROJECT"

# prepare train dataset
configure_and_prepare $TRAIN_DATASET

# make train.json split train/val (inside container)
# 1) Ensure source file exists
docker exec deepwukong bash -lc "[ -f ./data/$TRAIN_DATASET/train.json ] || { echo 'Missing ./data/$TRAIN_DATASET/train.json'; exit 1; }"

# 2) Pipe Python code via stdin to avoid nested heredoc quoting issues
cat <<PYEOF | docker exec -i deepwukong bash -lc "python3 -"
import json
train_path = "./data/$TRAIN_DATASET/train.json"
valid_path = "./data/$TRAIN_DATASET/valid.json"
with open(train_path) as f:
    data = json.load(f)
split_idx = int(len(data) * 0.8)
with open(train_path, "w") as f:
    json.dump(data[:split_idx], f)
with open(valid_path, "w") as f:
    json.dump(data[split_idx:], f)
PYEOF

# train model
docker exec deepwukong bash -lc "SLURM_TMPDIR=. python run.py -c ./config/config.yaml"

# prepare test dataset
configure_and_prepare $TEST_DATASET

# make test.json train.json
docker exec deepwukong bash -lc "mv ./data/$TEST_DATASET/train.json ./data/$TEST_DATASET/valid.json"

# evaluate
echo "Finding latest model version..."
LATEST_VERSION=$(docker exec deepwukong bash -lc "ls -d ./ts_logger/lightning_logs/version_* 2>/dev/null | sort -V | tail -n 1")
if [ -z "$LATEST_VERSION" ]; then
    echo "Error: No version folder found in lightning_logs"
    exit 1
fi
echo "Using model from: $LATEST_VERSION"
docker exec -w /code/models/DeepWukong -e PYTORCH_JIT=0 -e SLURM_TMPDIR=. deepwukong bash -lc "python evaluate.py ${LATEST_VERSION}/checkpoints/final_model.ckpt --root_folder_path ./data --split_folder_name $TEST_DATASET"