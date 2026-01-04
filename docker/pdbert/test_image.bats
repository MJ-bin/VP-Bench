#!/usr/bin/env bats

setup_file() {
    echo "# Using existing compose container: pdbert" >&3
}

# -------------------------------------------------------------------

@test "0. jasper 데이터셋 생성 for pdbert" {
    # RealVul 데이터셋 변환 스크립트 생성
    run docker exec pdbert cat > /PDBERT/data/datasets/extrinsic/vul_detect/realvul/make_jasperdataset_for_pdbert.py << 'EOF'
    #!/usr/bin/env python3
    import csv
    import json
    from pathlib import Path
    import random

    BASE_DIR = Path("/PDBERT/data/datasets/extrinsic/vul_detect/realvul")
    CSV_PATH = BASE_DIR / "jasper_dataset.csv"
    SOURCE_DIR = BASE_DIR / "jasper_source_code" / "source_code"
    OUTPUT_DIR = BASE_DIR

    random.seed(42)
    train_val_data = []
    test_data = []

    with open(CSV_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            source_file = SOURCE_DIR / f"{row['file_name']}"
            if not source_file.exists():
                continue
            with open(source_file, 'r', errors='ignore') as sf:
                code = sf.read()
            
            # vul 값 설정
            vul_value = 1 if row['vulnerable_line_numbers'].strip() else 0
            
            item = {
                "code": code,
                "vul": vul_value
            }
            
            if row['dataset_type'] == "train_val":
                train_val_data.append(item)
            else:
                test_data.append(item)

    random.shuffle(train_val_data)
    split_idx = int(len(train_val_data) * 0.8)

    with open(OUTPUT_DIR / "train.json", 'w') as f:
        json.dump(train_val_data[:split_idx], f, indent=4)
    with open(OUTPUT_DIR / "validate.json", 'w') as f:
        json.dump(train_val_data[split_idx:], f, indent=4)
    with open(OUTPUT_DIR / "test.json", 'w') as f:
        json.dump(test_data, f, indent=4)

    print(f"Train: {split_idx}, Validate: {len(train_val_data)-split_idx}, Test: {len(test_data)}")
    EOF
    
    run docker exec pdbert python /PDBERT/data/datasets/extrinsic/vul_detect/realvul/make_jasperdataset_for_pdbert.py
    
    # 실행 결과 출력 (디버깅용)
    echo "$output"
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
}


@test "1. PDBERT Jasper 데이터셋용 설정 파일 생성 (pdbert_realvul.jsonnet)" {
    # pdbert_realvul.jsonnet 설정 파일 생성
    run docker exec pdbert bash -c 'cat > /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet << '\''JSONEOF'\''
local data_base_path = "../data/datasets/extrinsic/vul_detect/realvul/";
local pretrained_model = "../data/models/pdbert-base";
local code_embed_dim = 768;
local code_encode_dim = 768;
local code_out_dim = 768;

local code_max_tokens = 512;
local code_namespace = "code_tokens";
local tokenizer_type = "codebert";

local mlm_mask_token = "<MLM>";
local additional_special_tokens = [mlm_mask_token];
local cuda_device = 0;

local debug = false;

{
    dataset_reader: {
        type: "func_vul_detect_base",
        code_tokenizer: {
            type: "pretrained_transformer",
            model_name: pretrained_model,
            max_length: code_max_tokens,
            tokenizer_kwargs: {
              additional_special_tokens: additional_special_tokens
            }
        },
        code_indexer: {
            type: "pretrained_transformer",
            model_name: pretrained_model,
            namespace: code_namespace,
            tokenizer_kwargs: {
              additional_special_tokens: additional_special_tokens
            }
        },
        func_code_field_key: "code",
        vul_label_field_key: "vul",
        code_max_tokens: code_max_tokens,
        code_namespace: code_namespace,
        code_cleaner: { type: "space_sub"},
        tokenizer_type: tokenizer_type,

        debug: debug
    },

    train_data_path: data_base_path + "train.json",
    validation_data_path: data_base_path + "validate.json",

    model: {
        type: "vul_func_predictor",
        code_embedder: {
          token_embedders: {
            code_tokens: {
              type: "pretrained_transformer",
              model_name: pretrained_model,
              train_parameters: true,
              tokenizer_kwargs: {
                additional_special_tokens: additional_special_tokens
             }
            }
          }
        },
        code_encoder: {
            type: "pass_through",
            input_dim: code_embed_dim,
        },
        code_feature_squeezer: {
            type: "cls_pooler",
            embedding_dim: code_embed_dim,
        },
        loss_func: {
            type: "bce"
        },
        classifier: {
            type: "linear_sigmoid",
            in_feature_dim: code_out_dim,
            hidden_dims: [256, 128],
            activations: ["relu", "relu"],
            dropouts: [0.3, 0.3],
            ahead_feature_dropout: 0.3,
        },
        metric: {
            type: "f1",
            positive_label: 1,
        },
    },

  data_loader: {
    batch_size: 16,
    shuffle: true,
  },
  validation_data_loader: {
    batch_size: 64,
    shuffle: true,
  },

  trainer: {
    num_epochs: 10,
    patience: null,
    cuda_device: cuda_device,
    validation_metric: "+f1",
    optimizer: {
      type: "adam",
      lr: 1e-5
    },
    num_gradient_accumulation_steps: 4,
    callbacks: [
      { type: "epoch_print" },
    ],
    checkpointer: null,
  },
}
JSONEOF
'
    
    # 실행 결과 출력 (디버깅용)
    echo "$output"
    
    # 종료 코드 0 (성공) 확인
    [ "$status" -eq 0 ]
}


@test "2. PDBERT 학습 및 평가 (Jasper 데이터셋)" {
    run docker exec pdbert python /PDBERT/downstream/train_eval_from_config.py \
        -config /PDBERT/downstream/configs/vul_detect/pdbert_realvul.jsonnet \
        -task_name vul_detect/realvul \
        -average binary

    echo "$output"
    [ "$status" -eq 0 ]
}