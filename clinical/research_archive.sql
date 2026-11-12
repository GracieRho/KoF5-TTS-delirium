-- clinical/voice_sessions.sql을 적용한 연구 전용 프로젝트에서 한 번 실행한다.
begin;

create table if not exists public.favilium_research_consents (
    reference text primary key references public.favilium_voice_sessions(reference) on delete cascade,
    consented_at timestamptz not null default now(),
    original bytea check (octet_length(original) between 1 and 4194304)
);
create table if not exists public.favilium_research_speech (
    id uuid primary key,
    reference text not null references public.favilium_research_consents(reference) on delete cascade,
    created_at timestamptz not null default now(),
    text_content text not null check (char_length(text_content) between 1 and 1000),
    audio bytea not null check (octet_length(audio) between 1 and 4194304)
);
create index if not exists favilium_research_speech_voice_date
    on public.favilium_research_speech (reference, created_at desc, id);
create index if not exists favilium_voice_sessions_date
    on public.favilium_voice_sessions (updated_at desc, reference);

alter table public.favilium_research_consents enable row level security;
alter table public.favilium_research_speech enable row level security;
create or replace view public.favilium_research_voice_index with (security_invoker = true) as
select v.reference, v.state, v.updated_at, c.consented_at, c.original is not null as has_sample,
       (select count(*) from public.favilium_research_speech s where s.reference = v.reference) as speech_count
from public.favilium_voice_sessions v left join public.favilium_research_consents c using (reference);

revoke all on public.favilium_research_consents, public.favilium_research_speech,
    public.favilium_research_voice_index from public, anon, authenticated;
grant select, insert on public.favilium_research_consents, public.favilium_research_speech to service_role;
grant select on public.favilium_research_voice_index to service_role;
commit;
