#!/usr/bin/env python3
from __future__ import annotations

"""
PDBERT 모델 정밀 분석 스크립트
- Confusion Matrix (TP, TN, FP, FN) 계산
- FN/FP 샘플 추출 및 저장
- 다운스트림 분류기가 실제로 사용하는 CLS feature export 및 t-SNE 시각화
"""
import argparse
import json
import sys
from pathlib import Path
from pprint import pprint

import matplotlib
import numpy as np
import torch
from allennlp.data.data_loaders import MultiProcessDataLoader
from allennlp.models.model import Model
from sklearn import manifold
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    matthews_corrcoef,
    precision_score,
    recall_score,
)
from tqdm import tqdm

sys.path.extend(['/PDBERT/downstream', '/PDBERT/downstream/..'])

from downstream import *
from utils.allennlp_utils.build_utils import build_dataset_reader_from_config

matplotlib.use('Agg')
import matplotlib.pyplot as plt

try:
    import seaborn as sns
except ModuleNotFoundError:
    sns = None

if sns is not None:
    sns.set(rc={'figure.figsize': (11.7, 8.27)})
else:
    plt.rcParams['figure.figsize'] = (11.7, 8.27)

FEATURE_BASENAME = 'test_last_hidden_state_vectors'


def parse_args():
    parser = argparse.ArgumentParser(description='PDBERT 모델 정밀 분석')
    parser.add_argument('--data-path', required=True, help='테스트 데이터 경로')
    parser.add_argument('--model-dir', required=True, help='모델 디렉토리 경로')
    parser.add_argument('--batch-size', type=int, default=32, help='배치 크기')
    parser.add_argument('--cuda', type=int, default=0, help='CUDA 장치 (-1은 CPU)')
    parser.add_argument('--output', default=None, help='분석 결과 저장 경로')
    return parser.parse_args()


def build_feature_artifact_paths(model_dir: str) -> tuple[Path, Path, Path]:
    base_path = Path(model_dir) / FEATURE_BASENAME
    return (
        base_path.with_suffix('.npz'),
        Path(f'{base_path}.jpeg'),
        Path(f'{base_path}-tsne-features.json'),
    )


def _tensor_to_list(value) -> list:
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().reshape(-1).tolist()
    if isinstance(value, list):
        return value
    return [value]


def plot_embedding(X_org, y, title=None, new=True):
    X_org = np.asarray(X_org)
    Y = np.asarray(y)

    if X_org.shape[0] < 2:
        print(f'Skipping TSNE for {title}: need at least 2 samples, got {X_org.shape[0]}')
        return False

    cache_path = str(title) + '-tsne-features.json'
    if not new and Path(cache_path).exists():
        with open(cache_path, 'r', encoding='utf-8') as file:
            _x, _y = json.load(file)
        X = np.array(_x)
        Y = np.array(_y)
    else:
        perplexity = min(30, X_org.shape[0] - 1)
        tsne = manifold.TSNE(n_components=2, init='pca', random_state=0, perplexity=perplexity)
        print('Fitting TSNE!')
        X = tsne.fit_transform(X_org)
        x_min, x_max = np.min(X, 0), np.max(X, 0)
        denom = np.where((x_max - x_min) == 0, 1, (x_max - x_min))
        X = (X - x_min) / denom

        with open(cache_path, 'w', encoding='utf-8') as file_:
            json.dump([X.tolist(), Y.tolist()], file_)

    if sns is not None:
        sns.set(style='white')
    plt.figure(figsize=(10, 10), edgecolor='black')
    plt.scatter(
        X[Y == 0][:, 0],
        X[Y == 0][:, 1],
        marker='.',
        c='tab:blue',
        s=12,
        linewidth=3.5,
        label='Non-Vuln',
    )
    plt.scatter(
        X[Y == 1][:, 0],
        X[Y == 1][:, 1],
        marker='^',
        c='tab:orange',
        s=12,
        linewidth=3.5,
        label='Vuln',
    )
    plt.xticks([]), plt.yticks([])
    if title is not None:
        plt.title('')
    plt.tight_layout()
    plt.savefig(str(title) + '.jpeg', dpi=1000)
    plt.close()
    return True


def predict_on_dataloader(model, data_loader):
    """모델 예측 수행"""
    all_pred = []
    all_ref = []
    all_score = []
    feature_batches = []

    with torch.no_grad():
        model.eval()
        for batch in tqdm(data_loader, desc='예측 수행'):
            outputs = model(**batch)
            # 현재 PDBERT 설정에서는 code_feature_squeezer=cls_pooler 이므로
            # classifier 입력 feature는 code_encoder 출력의 첫 토큰 벡터다.
            encoded_code_outputs = model.embed_encode_code(batch['code'])
            code_features = encoded_code_outputs['outputs']

            all_pred.extend(_tensor_to_list(outputs['pred']))
            all_score.extend(_tensor_to_list(outputs['logits']))
            all_ref.extend(_tensor_to_list(batch['label']))
            feature_batches.append(code_features.detach().cpu().numpy())

    feature_dim = getattr(model.classifier, 'get_exp_input_dim', lambda: 0)()
    all_features = (
        np.concatenate(feature_batches, axis=0)
        if feature_batches
        else np.empty((0, feature_dim), dtype=np.float32)
    )
    return all_ref, all_pred, all_score, all_features


def analyze_predictions(all_ref, all_pred, all_score, original_data):
    """예측 결과 분석"""
    cm = confusion_matrix(all_ref, all_pred)
    tn, fp, fn, tp = cm.ravel()

    result_dict = {
        'Accuracy': accuracy_score(all_ref, all_pred),
        'Precision': precision_score(all_ref, all_pred, average='binary'),
        'Recall': recall_score(all_ref, all_pred, average='binary'),
        'F1-Score': f1_score(all_ref, all_pred, average='binary'),
        'MCC': matthews_corrcoef(all_ref, all_pred),
        'TP (True Positive)': int(tp),
        'TN (True Negative)': int(tn),
        'FP (False Positive)': int(fp),
        'FN (False Negative)': int(fn),
        'Total Samples': len(all_ref),
    }

    fn_samples = []
    fp_samples = []

    for i, (ref, pred) in enumerate(zip(all_ref, all_pred)):
        sample = original_data[i].copy()
        sample['index'] = i
        sample['predicted'] = pred
        sample['actual'] = ref
        sample['score'] = all_score[i]

        if ref == 1 and pred == 0:
            fn_samples.append(sample)
        elif ref == 0 and pred == 1:
            fp_samples.append(sample)

    return result_dict, fn_samples, fp_samples


def main():
    args = parse_args()

    data_file_path = args.data_path + '/test.json'
    model_path = args.model_dir + '/model.tar.gz'
    output_path = args.output or (args.model_dir + '/prediction_analysis.json')
    feature_npz_path, tsne_image_path, tsne_cache_path = build_feature_artifact_paths(args.model_dir)

    print('=' * 80)
    print('PDBERT 정밀 분석 시작')
    print('=' * 80)
    print(f'데이터: {data_file_path}')
    print(f'모델: {model_path}')
    print(f'출력: {output_path}')
    print(f'Feature export: {feature_npz_path}')
    print('=' * 80)

    print('\n모델 로딩 중...')
    dataset_reader = build_dataset_reader_from_config(
        config_path=args.model_dir + '/config.json',
        serialization_dir=args.model_dir + '/',
    )
    model = Model.from_archive(model_path)

    if args.cuda != -1:
        model = model.cuda(args.cuda)
        torch.cuda.set_device(args.cuda)

    data_loader = MultiProcessDataLoader(
        dataset_reader,
        data_file_path,
        shuffle=False,
        batch_size=args.batch_size,
        cuda_device=args.cuda,
    )
    data_loader.index_with(model.vocab)

    with open(data_file_path, 'r', encoding='utf-8') as f:
        original_data = json.load(f)

    print()
    all_ref, all_pred, all_score, all_features = predict_on_dataloader(model, data_loader)

    if all_features.shape[0] != len(all_ref):
        raise RuntimeError(
            'Feature export sample count mismatch: '
            f'features={all_features.shape[0]}, labels={len(all_ref)}'
        )

    np.savez_compressed(feature_npz_path, features=all_features, labels=np.asarray(all_ref))
    print(f'\nFeature vectors 저장 완료: {feature_npz_path}')
    tsne_generated = plot_embedding(
        all_features,
        np.asarray(all_ref),
        title=str(feature_npz_path.with_suffix('')),
        new=True,
    )
    if tsne_generated:
        print(f't-SNE 이미지 저장 완료: {tsne_image_path}')
        print(f't-SNE 캐시 저장 완료: {tsne_cache_path}')

    result_dict, fn_samples, fp_samples = analyze_predictions(
        all_ref, all_pred, all_score, original_data
    )

    print('\n' + '=' * 80)
    print('평가 결과:')
    print('=' * 80)
    pprint(result_dict)

    csv_file_path = args.data_path + '/Real_Vul_data.csv'
    eval_result_path = args.model_dir + '/eval_result.csv'
    unique_ids = []

    try:
        import csv

        csv.field_size_limit(sys.maxsize)

        with open(csv_file_path, 'r', encoding='utf-8') as f_in, open(
            eval_result_path, 'w', encoding='utf-8', newline=''
        ) as f_out:
            reader = csv.DictReader(f_in)
            fieldnames = reader.fieldnames + ['model_predict', 'confusion_matrix']
            writer = csv.DictWriter(f_out, fieldnames=fieldnames)
            writer.writeheader()

            for i, row in enumerate(reader):
                uid = row.get('unique_id', '')
                unique_ids.append(uid)

                if i < len(all_pred):
                    ref = all_ref[i]
                    pred = all_pred[i]

                    if ref == 1 and pred == 1:
                        cm_label = 'TP'
                    elif ref == 0 and pred == 0:
                        cm_label = 'TN'
                    elif ref == 0 and pred == 1:
                        cm_label = 'FP'
                    else:
                        cm_label = 'FN'

                    row['model_predict'] = pred
                    row['confusion_matrix'] = cm_label
                    writer.writerow(row)

        print(f'\neval_result.csv 저장 완료: {eval_result_path}')
        print(f'총 {len(unique_ids)}개 샘플 처리')

    except Exception as e:
        print(f'\nWarning: eval_result.csv 생성 실패 - {e}')
        unique_ids = ['unknown'] * len(original_data)

    for sample in fn_samples:
        idx = sample['index']
        sample['unique_id'] = unique_ids[idx] if idx < len(unique_ids) else 'unknown'
    for sample in fp_samples:
        idx = sample['index']
        sample['unique_id'] = unique_ids[idx] if idx < len(unique_ids) else 'unknown'

    analysis_result = {
        'summary': result_dict,
        'csv_file': csv_file_path,
        'feature_npz': str(feature_npz_path),
        'tsne_image': str(tsne_image_path) if tsne_generated else None,
        'tsne_cache': str(tsne_cache_path) if tsne_generated else None,
        'fn_count': len(fn_samples),
        'fp_count': len(fp_samples),
        'fn_samples': fn_samples,
        'fp_samples': fp_samples,
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(analysis_result, f, indent=2, ensure_ascii=False)

    print(f"\n{'=' * 80}")
    print(f'분석 결과 저장: {output_path}')
    print(f'FN (놓친 취약점): {len(fn_samples)}개')
    print(f'FP (오탐): {len(fp_samples)}개')

    if fn_samples:
        print(f"\n{'=' * 80}")
        print('FN (False Negative) 샘플 목록:')
        print('=' * 80)
        for i, sample in enumerate(fn_samples):
            print(f"  #{i+1}: unique_id={sample['unique_id']}")
            print(f"       index={sample['index']}, score={sample['score']:.4f}")

        print(f"\n{'=' * 80}")
        print('CSV에서 상세 정보 조회 명령어:')
        print('=' * 80)
        for i, sample in enumerate(fn_samples):
            uid = sample['unique_id']
            print(f'# FN #{i+1}:')
            print(f"grep '{uid}' {csv_file_path}")
            print()

    if fp_samples:
        print(f"\n{'=' * 80}")
        print('FP (False Positive) 샘플 목록:')
        print('=' * 80)
        for i, sample in enumerate(fp_samples):
            print(f"  #{i+1}: unique_id={sample['unique_id']}")
            print(f"       index={sample['index']}, score={sample['score']:.4f}")

    print(f"\n{'=' * 80}")
    print('분석 완료!')
    print('=' * 80)


if __name__ == '__main__':
    main()
