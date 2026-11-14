-- UniTails marketplace foundation for Supabase PostgreSQL.
-- Run only in a dedicated Supabase project. No production changes are made by this file.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','carer')),
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  area text not null default '',
  bio text not null default '',
  services text[] not null default '{}',
  is_visible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.pets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  species text not null,
  notes text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.interest_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  message text not null default '' check (char_length(message) <= 1000),
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_self_interest check (sender_id <> recipient_id),
  constraint unique_direction unique(sender_id,recipient_id)
);
create table if not exists public.connections (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.interest_requests(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  carer_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint different_members check(owner_id <> carer_id),
  constraint unique_connection unique(owner_id,carer_id)
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.connections(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id,blocked_id),
  check(blocker_id <> blocked_id)
);
create index if not exists requests_recipient_idx on public.interest_requests(recipient_id,status);
create index if not exists messages_connection_idx on public.messages(connection_id,created_at);

create or replace function public.is_blocked(a uuid,b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.blocks where
 (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a));
$$;
revoke all on function public.is_blocked(uuid,uuid) from public;
grant execute on function public.is_blocked(uuid,uuid) to authenticated;

create or replace function public.accept_interest(request_uuid uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare req public.interest_requests%rowtype; owner_uuid uuid; carer_uuid uuid; connection_uuid uuid;
begin
 select * into req from public.interest_requests where id=request_uuid for update;
 if not found or req.recipient_id <> auth.uid() or req.status <> 'pending' then
   raise exception 'Request not available';
 end if;
 if public.is_blocked(req.sender_id,req.recipient_id) then raise exception 'Connection unavailable'; end if;
 select id into owner_uuid from public.profiles where id in (req.sender_id,req.recipient_id) and role='owner';
 select id into carer_uuid from public.profiles where id in (req.sender_id,req.recipient_id) and role='carer';
 if owner_uuid is null or carer_uuid is null then raise exception 'Incompatible roles'; end if;
 update public.interest_requests set status='accepted',updated_at=now() where id=req.id;
 insert into public.connections(request_id,owner_id,carer_id) values(req.id,owner_uuid,carer_uuid)
 on conflict(owner_id,carer_id) do update set owner_id=excluded.owner_id returning id into connection_uuid;
 return connection_uuid;
end $$;
revoke all on function public.accept_interest(uuid) from public;
grant execute on function public.accept_interest(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.pets enable row level security;
alter table public.interest_requests enable row level security;
alter table public.connections enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;

create policy "profiles read visible or self" on public.profiles for select to authenticated
using ((is_visible or id=auth.uid()) and (id=auth.uid() or not public.is_blocked(id,auth.uid())));
create policy "profiles insert self" on public.profiles for insert to authenticated with check(id=auth.uid());
create policy "profiles update self" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "pets read owner" on public.pets for select to authenticated using(owner_id=auth.uid());
create policy "pets insert owner" on public.pets for insert to authenticated with check(owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='owner'));
create policy "pets update owner" on public.pets for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy "pets delete owner" on public.pets for delete to authenticated using(owner_id=auth.uid());

create policy "requests participant read" on public.interest_requests for select to authenticated
using(auth.uid() in (sender_id,recipient_id));
create policy "requests sender create" on public.interest_requests for insert to authenticated
with check(sender_id=auth.uid() and status='pending'
and not public.is_blocked(sender_id,recipient_id)
and exists(select 1 from public.profiles p where p.id=sender_id)
and exists(select 1 from public.profiles p where p.id=recipient_id and p.is_visible=true)
and (select role from public.profiles where id=sender_id) <> (select role from public.profiles where id=recipient_id));
-- Status changes are performed by restricted RPCs, not unrestricted table updates.
create or replace function public.resolve_interest(request_uuid uuid, decision text)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if decision not in ('declined','cancelled') then raise exception 'Invalid decision'; end if;
 update public.interest_requests set status=decision,updated_at=now()
 where id=request_uuid and status='pending' and
 ((decision='declined' and recipient_id=auth.uid()) or (decision='cancelled' and sender_id=auth.uid()));
 if not found then raise exception 'Request not available'; end if;
end $$;
revoke all on function public.resolve_interest(uuid,text) from public;
grant execute on function public.resolve_interest(uuid,text) to authenticated;

create policy "connections participant read" on public.connections for select to authenticated
using(auth.uid() in (owner_id,carer_id) and not public.is_blocked(owner_id,carer_id));
create policy "messages participant read" on public.messages for select to authenticated
using(exists(select 1 from public.connections c where c.id=connection_id and auth.uid() in (c.owner_id,c.carer_id) and not public.is_blocked(c.owner_id,c.carer_id)));
create policy "messages participant send" on public.messages for insert to authenticated
with check(sender_id=auth.uid() and exists(select 1 from public.connections c where c.id=connection_id and auth.uid() in (c.owner_id,c.carer_id) and not public.is_blocked(c.owner_id,c.carer_id)));
create policy "blocks read self" on public.blocks for select to authenticated using(blocker_id=auth.uid());
create policy "blocks insert self" on public.blocks for insert to authenticated with check(blocker_id=auth.uid());
create policy "blocks delete self" on public.blocks for delete to authenticated using(blocker_id=auth.uid());
