#!/usr/bin/env python3
"""
PDBERT 모델 정밀 분석 스크립트
- Confusion Matrix (TP, TN, FP, FN) 계산
- FN/FP 샘플 추출 및 저장
"""
import sys
import json
import argparse
from pprint import pprint
from tqdm import tqdm

import torch
from allennlp.data.data_loaders import MultiProcessDataLoader
from allennlp.models.model import Model
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, 
    f1_score, matthews_corrcoef, confusion_matrix
)

sys.path.extend(['/PDBERT/downstream', '/PDBERT/downstream/..'])

from downstream import *
from utils.allennlp_utils.build_utils import build_dataset_reader_from_config


def parse_args():
    parser = argparse.ArgumentParser(description='PDBERT 모델 정밀 분석')
    parser.add_argument('--data-path', required=True, help='테스트 데이터 경로')
    parser.add_argument('--model-dir', required=True, help='모델 디렉토리 경로')
    parser.add_argument('--batch-size', type=int, default=32, help='배치 크기')
    parser.add_argument('--cuda', type=int, default=0, help='CUDA 장치 (-1은 CPU)')
    parser.add_argument('--output', default=None, help='분석 결과 저장 경로')
    return parser.parse_args()


def predict_on_dataloader(model, data_loader):
    """모델 예측 수행"""
    all_pred = []
    all_ref = []
    all_score = []
    
    with torch.no_grad():
        model.eval()
        for batch in tqdm(data_loader, desc="예측 수행"):
            outputs = model(**batch)
            all_pred.extend(outputs['pred'].cpu().detach().tolist())
            all_score.extend(outputs['logits'].cpu().detach().tolist())
            all_ref.extend(batch['label'].cpu().detach().squeeze().tolist())
    
    return all_ref, all_pred, all_score


def analyze_predictions(all_ref, all_pred, all_score, original_data):
    """예측 결과 분석"""
    # Confusion Matrix 계산
    cm = confusion_matrix(all_ref, all_pred)
    tn, fp, fn, tp = cm.ravel()
    
    # 메트릭 계산
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
    
    # FN, FP 인덱스 찾기
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
    
    print("=" * 80)
    print("PDBERT 정밀 분석 시작")
    print("=" * 80)
    print(f"데이터: {data_file_path}")
    print(f"모델: {model_path}")
    print(f"출력: {output_path}")
    print("=" * 80)
    
    # 모델 및 데이터 로더 설정
    print("\n모델 로딩 중...")
    dataset_reader = build_dataset_reader_from_config(
        config_path=args.model_dir + '/config.json',
        serialization_dir=args.model_dir + '/'
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
        cuda_device=args.cuda
    )
    data_loader.index_with(model.vocab)
    
    # 원본 데이터 로드
    with open(data_file_path, 'r') as f:
        original_data = json.load(f)
    
    # 예측 수행
    print()
    all_ref, all_pred, all_score = predict_on_dataloader(model, data_loader)
    
    # 분석 수행
    result_dict, fn_samples, fp_samples = analyze_predictions(
        all_ref, all_pred, all_score, original_data
    )
    
    # 결과 출력
    print("\n" + "=" * 80)
    print("평가 결과:")
    print("=" * 80)
    pprint(result_dict)
    
    # eval_result.csv 생성 (스트리밍 방식 - 메모리 효율적)
    # 원본 CSV의 모든 컬럼 + model_predict, confusion_matrix
    csv_file_path = args.data_path + '/Real_Vul_data.csv'
    eval_result_path = args.model_dir + '/eval_result.csv'
    unique_ids = []  # FN/FP 샘플용 unique_id 저장 (숫자만 저장하므로 작은 크기)
    
    try:
        import csv
        # CSV 필드 크기 제한 증가 (긴 코드 필드 처리)
        csv.field_size_limit(sys.maxsize)
        
        with open(csv_file_path, 'r', encoding='utf-8') as f_in, \
             open(eval_result_path, 'w', encoding='utf-8', newline='') as f_out:
            
            reader = csv.DictReader(f_in)
            # 원본 헤더 + 새 컬럼
            fieldnames = reader.fieldnames + ['model_predict', 'confusion_matrix']
            writer = csv.DictWriter(f_out, fieldnames=fieldnames)
            writer.writeheader()
            
            for i, row in enumerate(reader):
                # unique_id 저장 (FN/FP 샘플용)
                uid = row.get('unique_id', '')
                unique_ids.append(uid)
                
                # 예측 결과 가져오기
                if i < len(all_pred):
                    ref = all_ref[i]
                    pred = all_pred[i]
                    
                    # confusion matrix 분류
                    if ref == 1 and pred == 1:
                        cm_label = 'TP'
                    elif ref == 0 and pred == 0:
                        cm_label = 'TN'
                    elif ref == 0 and pred == 1:
                        cm_label = 'FP'
                    else:  # ref == 1 and pred == 0
                        cm_label = 'FN'
                    
                    # 원본 row에 새 컬럼 추가
                    row['model_predict'] = pred
                    row['confusion_matrix'] = cm_label
                    
                    # 바로 파일에 쓰기 (메모리에 저장 안함)
                    writer.writerow(row)
        
        print(f"\neval_result.csv 저장 완료: {eval_result_path}")
        print(f"총 {len(unique_ids)}개 샘플 처리")
        
    except Exception as e:
        print(f"\nWarning: eval_result.csv 생성 실패 - {e}")
        unique_ids = ['unknown'] * len(original_data)
    
    # FN/FP 샘플에 unique_id 추가
    for sample in fn_samples:
        idx = sample['index']
        sample['unique_id'] = unique_ids[idx] if idx < len(unique_ids) else 'unknown'
    for sample in fp_samples:
        idx = sample['index']
        sample['unique_id'] = unique_ids[idx] if idx < len(unique_ids) else 'unknown'
    
    # 결과 저장
    analysis_result = {
        'summary': result_dict,
        'csv_file': csv_file_path,
        'fn_count': len(fn_samples),
        'fp_count': len(fp_samples),
        'fn_samples': fn_samples,
        'fp_samples': fp_samples,
    }
    
    with open(output_path, 'w') as f:
        json.dump(analysis_result, f, indent=2, ensure_ascii=False)
    
    print(f"\n{'=' * 80}")
    print(f"분석 결과 저장: {output_path}")
    print(f"FN (놓친 취약점): {len(fn_samples)}개")
    print(f"FP (오탐): {len(fp_samples)}개")
    
    # FN 샘플 출력
    if fn_samples:
        print(f"\n{'=' * 80}")
        print("FN (False Negative) 샘플 목록:")
        print("=" * 80)
        for i, sample in enumerate(fn_samples):
            print(f"  #{i+1}: unique_id={sample['unique_id']}")
            print(f"       index={sample['index']}, score={sample['score']:.4f}")
        
        print(f"\n{'=' * 80}")
        print("CSV에서 상세 정보 조회 명령어:")
        print("=" * 80)
        for i, sample in enumerate(fn_samples):
            uid = sample['unique_id']
            print(f"# FN #{i+1}:")
            print(f"grep '{uid}' {csv_file_path}")
            print()
    
    # FP 샘플 출력
    if fp_samples:
        print(f"\n{'=' * 80}")
        print("FP (False Positive) 샘플 목록:")
        print("=" * 80)
        for i, sample in enumerate(fp_samples):
            print(f"  #{i+1}: unique_id={sample['unique_id']}")
            print(f"       index={sample['index']}, score={sample['score']:.4f}")
    
    print(f"\n{'=' * 80}")
    print("분석 완료!")
    print("=" * 80)


if __name__ == '__main__':
    main()
