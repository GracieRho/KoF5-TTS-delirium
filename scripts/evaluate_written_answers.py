"""가상 문장만 실제 보호자 인증·무료 모델 API로 평가한다. 계정·DB를 만들거나 수정하지 않는다."""
import argparse
import getpass
import os
from pathlib import Path

import _bootstrap
from kof5_tts.research.interpretation_evaluation import evaluate
from kof5_tts.research.openrouter import FREE_MODEL, FREE_MODELS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:8767')
    parser.add_argument('--email', required=True)
    parser.add_argument('--model', choices=FREE_MODELS, default=FREE_MODEL)
    parser.add_argument('--cases', type=Path, default=_bootstrap.REPOSITORY_ROOT / 'configs/research/written-answer-evaluation.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--consent-free-provider', action='store_true', help='가상 문장의 무료 공급자 전송·보관/학습 가능성에 동의')
    args = parser.parse_args()
    password = os.environ.get('KOF5_EVAL_PASSWORD') or getpass.getpass('보호자 비밀번호: ')
    try:
        report = evaluate(args.base_url, args.email, password, args.cases, args.output, args.model, args.consent_free_provider)
    except Exception as error:
        # Do not print HTTP requests, credentials, or provider response bodies.
        parser.exit(1, f'평가 중단: {str(error) if isinstance(error, ValueError) else type(error).__name__}\n')
    print(report['summary'])


if __name__ == '__main__':
    main()
