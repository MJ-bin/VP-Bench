#!/bin/bash

set -e

# argument for selecting models
MODELS=("deepwukong" "linevul" "pdbert" "vuddy")
SELECTED_MODELS=()
SUCCESSFUL_MODELS=()
NO_CACHE=false
SKIP_TESTS=false

# 로그 디렉토리 및 파일 설정
LOG_DIR="logs/experiment"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +"%Y%m%d_%H%M%S")_experiment.log"

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--models)
            if [ "$2" = "all" ]; then
                SELECTED_MODELS=("${MODELS[@]}")
                mkdir -p "$LOG_DIR/all"
                LOG_FILE="$LOG_DIR/all/$(date +"%Y%m%d_%H%M%S")_experiment.log"
            else
                IFS=',' read -ra SELECTED_MODELS <<< "$2"
                if [ ${#SELECTED_MODELS[@]} -eq 1 ]; then
                    mkdir -p "$LOG_DIR/${SELECTED_MODELS[*]}"
                    LOG_FILE="$LOG_DIR/${SELECTED_MODELS[*]}/$(date +"%Y%m%d_%H%M%S")_experiment.log"
                fi
            fi
            shift 2
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --skip-tests|--no-bats)
            SKIP_TESTS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ ${#SELECTED_MODELS[@]} -eq 0 ]; then
    echo "No models specified. Please use -m or --models to specify models."
    exit 1
fi

# 모든 출력을 로그 파일과 화면에 동시에 출력
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date)] Command: $0 $@"

echo "Selected models: ${SELECTED_MODELS[*]}"
echo "No-cache build: $NO_CACHE"
echo "Skip tests: $SKIP_TESTS"

for model in "${SELECTED_MODELS[@]}"; do
    
    echo "Prepare data for $model..."
    bash "./experiment/scripts/${model}/prepare.sh" || { echo "Data preparation failed for $model"; continue; }

    echo "Building Docker image for $model..."
    docker compose down "$model" || true
    
    # Build with --no-cache flag if enabled
    if [ "$NO_CACHE" = true ]; then
        docker compose build --no-cache "$model" || { echo "Build failed for $model"; exit 1; }
    fi
    
    docker compose up -d "$model" || { echo "Container failed to start for $model"; exit 1; }

    echo "Testing Docker container for $model..."
    # Skip tests if --skip-tests flag is enabled
    if [ "$SKIP_TESTS" = false ]; then
        bats -t "./docker/$model/test_container.bats" || { echo "Test failed for $model"; continue; }
    else
        echo "Skipping tests for $model..."
    fi

    echo "$model setup and test completed."
    SUCCESSFUL_MODELS+=("$model")
done

echo ""
echo "Successful models: ${SUCCESSFUL_MODELS[*]}"

for model in "${SUCCESSFUL_MODELS[@]}"; do
    echo "Running experiment for $model..."
    bash "./experiment/scripts/${model}/run.sh" "all"
done
