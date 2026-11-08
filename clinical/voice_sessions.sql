-- 전용 Supabase 프로젝트의 SQL Editor에서 실행한다.
-- 참가자 이름, 녹음, 합성 문장, 오디오는 저장하지 않는다.
begin;

create table if not exists public.favilium_voice_sessions (
    session_id text primary key,
    reference text not null unique,
    state text not null check (state in ('creating', 'ready', 'verification', 'deleting')),
    voice_id text,
    updated_at timestamptz not null default now()
);

alter table public.favilium_voice_sessions enable row level security;
revoke all on table public.favilium_voice_sessions from public, anon, authenticated;
grant select, insert, update, delete on table public.favilium_voice_sessions to service_role;

commit;
