-- ================= Panel Board Store — schema =================
-- Run in Supabase: Project -> SQL Editor -> New query -> paste all -> Run
-- Safe to re-run.

create table if not exists items (
  id text primary key,
  code text not null,
  name text not null,
  category text,
  unit text,
  unit_price numeric default 0
);
alter table items add column if not exists unit_price numeric default 0;

create table if not exists transactions (
  id text primary key,
  item_id text references items(id) on delete restrict,
  type text not null check (type in ('in','out')),
  qty numeric not null,
  date date not null,
  ref text,
  remarks text,
  ts bigint not null,
  created_by uuid
);
alter table transactions add column if not exists created_by uuid;

-- One row per login user, holds their access level
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'staff' check (role in ('admin','staff'))
);

-- Auto-create a profile row whenever someone signs up (defaults to staff)
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, email, role)
  values (new.id, new.email, 'staff')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- Helper function (avoids recursive RLS checks)
create or replace function is_admin(uid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((select role from profiles where id = uid) = 'admin', false);
$$;

alter table items enable row level security;
alter table transactions enable row level security;
alter table profiles enable row level security;

drop policy if exists "public read items" on items;
drop policy if exists "public write items" on items;
drop policy if exists "public delete items" on items;
drop policy if exists "public read transactions" on transactions;
drop policy if exists "public write transactions" on transactions;
drop policy if exists "public delete transactions" on transactions;
drop policy if exists "items read" on items;
drop policy if exists "items insert admin" on items;
drop policy if exists "items update admin" on items;
drop policy if exists "items delete admin" on items;
drop policy if exists "tx read" on transactions;
drop policy if exists "tx insert authenticated" on transactions;
drop policy if exists "tx delete admin" on transactions;
drop policy if exists "profiles read" on profiles;
drop policy if exists "profiles update admin" on profiles;

-- Items: any signed-in user can read; only admins can add / edit / delete
create policy "items read" on items for select using (auth.role() = 'authenticated');
create policy "items insert admin" on items for insert with check (is_admin(auth.uid()));
create policy "items update admin" on items for update using (is_admin(auth.uid()));
create policy "items delete admin" on items for delete using (is_admin(auth.uid()));

-- Transactions: any signed-in user can read and record entries; only admins can delete
create policy "tx read" on transactions for select using (auth.role() = 'authenticated');
create policy "tx insert authenticated" on transactions for insert with check (auth.role() = 'authenticated');
create policy "tx delete admin" on transactions for delete using (is_admin(auth.uid()));

-- Profiles: everyone signed in can see the user list; only admins can change roles
create policy "profiles read" on profiles for select using (auth.role() = 'authenticated');
create policy "profiles update admin" on profiles for update using (is_admin(auth.uid()));

-- ---- After you sign up for the first time in the app, run this once ----
-- (replace with your own email) to make yourself an admin:
-- update profiles set role = 'admin' where email = 'you@example.com';
