"""가상 계정 자료 준비 후 루프백에서 가족·병원 웹을 실행한다."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    path = ROOT / 'runs/local-studio/portal.env'
    if not path.is_file():
        raise SystemExit('먼저 .venv/bin/python supabase/tests/seed_portal.py 를 실행해주세요.')
    env = dict(os.environ)
    allowed = {'KOF5_LOCAL_STUDIO', 'KOF5_STUDIO_DB', 'KOF5_SUPABASE_URL',
               'KOF5_SUPABASE_PUBLISHABLE_KEY', 'KOF5_STUDIO_GUARDIAN_USER_ID'}
    for line in path.read_text().splitlines():
        name, separator, value = line.partition('=')
        if separator and name in allowed:
            env[name] = value
    if env.get('KOF5_SUPABASE_URL') != 'http://127.0.0.1:54341' or env.get('VERCEL'):
        raise SystemExit('프로젝트 전용 로컬 Supabase에서만 실행할 수 있습니다.')
    env['PYTHONPATH'] = str(ROOT / 'src')
    raise SystemExit(subprocess.call([sys.executable, '-m', 'uvicorn', 'kof5_tts.api:app',
                                     '--host', '127.0.0.1', '--port', '8766'], cwd=ROOT, env=env))


if __name__ == '__main__':
    main()
