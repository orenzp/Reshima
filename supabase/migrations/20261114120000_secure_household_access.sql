-- ============================================================================
-- Lock the database down to household members.
--
--   * Removes the open `using (true)` policies; access now requires a signed-in
--     (anonymous) user who joined the household with its invite code.
--   * Rotates short/guessable invite codes to long random ones.
--   * Hardens SECURITY DEFINER functions and scopes Storage to the household.
--   * Adds a stable `kind` to aisles and an atomic catalog upsert RPC.
--
-- Written to be safe to re-run.
-- ============================================================================

-- 1. REMOVE OPEN ACCESS -------------------------------------------------------

drop policy if exists "Shared household access on households" on public.households;
drop policy if exists "Shared household access on categories" on public.categories;
drop policy if exists "Shared household access on catalog_items" on public.catalog_items;
drop policy if exists "Shared household access on shopping_lists" on public.shopping_lists;
drop policy if exists "Shared household access on list_items" on public.list_items;

-- Legacy migration tracker (the deploy workflow now uses supabase_migrations.schema_migrations).
do $$
begin
    if to_regclass('public.schema_migrations') is not null then
        alter table public.schema_migrations enable row level security;
        revoke all on table public.schema_migrations from anon, authenticated;
    end if;
end $$;

-- 2. STRONG INVITE CODES ------------------------------------------------------
-- The new code is NOT stored in this (public) repository. Read it once with:
--   select name, invite_code from public.households;
-- in the Supabase SQL editor, then type it into Settings on each phone.

update public.households
set invite_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20))
where length(invite_code) < 16;

alter table public.households drop constraint if exists households_invite_code_strong;
alter table public.households
    add constraint households_invite_code_strong check (length(invite_code) >= 16);

-- 3. STABLE AISLE KIND --------------------------------------------------------

alter table public.categories add column if not exists kind text;

update public.categories
set kind = case name_en
    when 'Produce' then 'produce'
    when 'Dairy & Eggs' then 'dairy'
    when 'Bakery & Bread' then 'bakery'
    when 'Meat & Fish' then 'meat'
    when 'Pantry & Dry Goods' then 'pantry'
    when 'Frozen' then 'frozen'
    when 'Home & Pharmacy' then 'household'
    when 'Other' then 'other'
end
where kind is null;

create unique index if not exists idx_categories_household_kind
    on public.categories(household_id, kind)
    where kind is not null;

-- 4. HARDENED FUNCTIONS -------------------------------------------------------

create or replace function public.is_household_member(p_household_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
    select exists (
        select 1
        from public.household_members hm
        where hm.household_id = p_household_id
          and hm.user_id = auth.uid()
    );
$$;

-- Stamps server time and the acting user on every write (clients cannot spoof either).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    new.updated_by = coalesce(auth.uid(), new.updated_by);
    if tg_op = 'INSERT' then
        if new.is_checked then
            new.checked_at = coalesce(new.checked_at, now());
        else
            new.checked_at = null;
        end if;
    elsif new.is_checked = true and (old.is_checked is distinct from true) then
        new.checked_at = now();
    elsif new.is_checked = false then
        new.checked_at = null;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_list_items_updated_at on public.list_items;
create trigger trg_list_items_updated_at
before insert or update on public.list_items
for each row execute function public.set_updated_at();

create or replace function public.seed_default_household_data(p_household_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_list_id uuid;
begin
    if not exists (select 1 from public.categories where household_id = p_household_id) then
        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order, kind)
        values
            (p_household_id, 'פירות וירקות', 'Produce', '🥦', '#10B981', 10, 'produce'),
            (p_household_id, 'מוצרי חלב וביצים', 'Dairy & Eggs', '🧀', '#3B82F6', 20, 'dairy'),
            (p_household_id, 'מאפים ולחם', 'Bakery & Bread', '🥖', '#F59E0B', 30, 'bakery'),
            (p_household_id, 'בשר, עוף ודגים', 'Meat & Fish', '🥩', '#EF4444', 40, 'meat'),
            (p_household_id, 'מזווה ובישול', 'Pantry & Dry Goods', '🍝', '#8B5CF6', 50, 'pantry'),
            (p_household_id, 'קפואים', 'Frozen', '🧊', '#06B6D4', 60, 'frozen'),
            (p_household_id, 'ניקיון ופארם', 'Home & Pharmacy', '🧼', '#EC4899', 70, 'household'),
            (p_household_id, 'כללי', 'Other', '🛒', '#6B7280', 80, 'other');

        insert into public.catalog_items (household_id, name, normalized_name, default_category_id, default_unit, usage_count, is_staple)
        select p_household_id, s.name, lower(s.name), c.id, s.unit, s.usage_count, s.is_staple
        from (values
            ('חלב 3%', 'dairy', 'pcs', 25, true),
            ('ביצים L', 'dairy', 'pack', 20, true),
            ('קוטג׳ 5%', 'dairy', 'pcs', 18, true),
            ('לחם מחמצת', 'bakery', 'pcs', 18, true),
            ('עגבניות', 'produce', 'kg', 16, true),
            ('מלפפונים', 'produce', 'kg', 16, true),
            ('בננות', 'produce', 'kg', 12, true),
            ('אבוקדו', 'produce', 'kg', 11, true),
            ('חזה עוף', 'meat', 'kg', 10, true),
            ('שמן זית', 'pantry', 'pcs', 8, true),
            ('נייר טואלט', 'household', 'pack', 7, true),
            ('Milk 3%', 'dairy', 'pcs', 10, false),
            ('Eggs (Large)', 'dairy', 'pack', 9, false),
            ('Tomatoes', 'produce', 'kg', 8, false)
        ) as s(name, kind, unit, usage_count, is_staple)
        left join public.categories c
            on c.household_id = p_household_id and c.kind = s.kind
        where true -- keeps the parser from reading ON CONFLICT as part of the join
        on conflict (household_id, normalized_name) do nothing;
    end if;

    select id into v_list_id
    from public.shopping_lists
    where household_id = p_household_id and is_archived = false
    order by created_at asc
    limit 1;

    if v_list_id is null then
        insert into public.shopping_lists (household_id, title)
        values (p_household_id, 'רשימת קניות / Shopping List')
        returning id into v_list_id;
    end if;

    return v_list_id;
end;
$$;

-- Internal helper only: it takes any household id, so it must not be callable through the API.
revoke execute on function public.seed_default_household_data(uuid) from public, anon, authenticated;

-- Joining replaces join_or_create_household: strangers can no longer create households,
-- and the only way in is knowing an existing household's long random code.
drop function if exists public.join_or_create_household(text, text, text);

create or replace function public.join_household(
    p_invite_code text,
    p_display_name text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_clean_code text;
    v_household_id uuid;
    v_list_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    v_clean_code := upper(trim(coalesce(p_invite_code, '')));

    select id into v_household_id
    from public.households
    where invite_code = v_clean_code;

    if v_household_id is null then
        -- RS001 is recognised by the app as "wrong code" (as opposed to "offline").
        raise exception 'Invalid invite code' using errcode = 'RS001';
    end if;

    insert into public.household_members (household_id, user_id, display_name)
    values (v_household_id, auth.uid(), coalesce(p_display_name, ''))
    on conflict (household_id, user_id)
    do update set display_name = excluded.display_name;

    v_list_id := public.seed_default_household_data(v_household_id);

    return jsonb_build_object(
        'household_id', v_household_id,
        'list_id', v_list_id
    );
end;
$$;

revoke execute on function public.join_household(text, text) from public, anon;
grant execute on function public.join_household(text, text) to authenticated;

-- Atomic "remember this product" upsert. Runs with the caller's rights, so RLS still applies.
-- usage_count is incremented on the server, so two phones never overwrite each other's counts.
create or replace function public.record_catalog_item(
    p_household_id uuid,
    p_name text,
    p_normalized_name text,
    p_default_category_id uuid,
    p_default_unit text,
    p_is_staple boolean,
    p_usage_delta int default 0
)
returns void
language sql
security invoker
set search_path = ''
as $$
    insert into public.catalog_items as ci
        (household_id, name, normalized_name, default_category_id, default_unit, usage_count, is_staple, last_used_at)
    values
        (p_household_id, p_name, p_normalized_name, p_default_category_id, p_default_unit,
         greatest(least(p_usage_delta, 100), 1), p_is_staple, now())
    on conflict (household_id, normalized_name) do update
    set default_category_id = excluded.default_category_id,
        default_unit = excluded.default_unit,
        is_staple = excluded.is_staple,
        usage_count = ci.usage_count + greatest(least(p_usage_delta, 100), 0),
        last_used_at = case when p_usage_delta > 0 then now() else ci.last_used_at end;
$$;

revoke execute on function public.record_catalog_item(uuid, text, text, uuid, text, boolean, int) from public, anon;
grant execute on function public.record_catalog_item(uuid, text, text, uuid, text, boolean, int) to authenticated;

-- 5. STORAGE: PHOTOS ARE PRIVATE TO THE HOUSEHOLD -----------------------------
-- Object names are "<household_id>/<file>.jpg"; the first path segment decides who may touch it.

create or replace function public.can_access_item_photo(p_object_name text)
returns boolean
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
    return public.is_household_member(split_part(p_object_name, '/', 1)::uuid);
exception
    when others then
        return false; -- first segment is not a household id
end;
$$;

update storage.buckets
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg']
where id = 'item-photos';

drop policy if exists "Authenticated users can upload item photos" on storage.objects;
drop policy if exists "Authenticated users can view item photos" on storage.objects;
drop policy if exists "Authenticated users can delete item photos" on storage.objects;
drop policy if exists "Household members can view item photos" on storage.objects;
drop policy if exists "Household members can upload item photos" on storage.objects;
drop policy if exists "Household members can replace item photos" on storage.objects;
drop policy if exists "Household members can delete item photos" on storage.objects;

create policy "Household members can view item photos"
    on storage.objects for select
    to authenticated
    using (bucket_id = 'item-photos' and public.can_access_item_photo(name));

create policy "Household members can upload item photos"
    on storage.objects for insert
    to authenticated
    with check (bucket_id = 'item-photos' and public.can_access_item_photo(name));

create policy "Household members can replace item photos"
    on storage.objects for update
    to authenticated
    using (bucket_id = 'item-photos' and public.can_access_item_photo(name))
    with check (bucket_id = 'item-photos' and public.can_access_item_photo(name));

create policy "Household members can delete item photos"
    on storage.objects for delete
    to authenticated
    using (bucket_id = 'item-photos' and public.can_access_item_photo(name));

-- 6. REALTIME -----------------------------------------------------------------
-- Add each table on its own so one "already added" does not skip the rest.

do $$
declare
    v_table text;
begin
    if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        return;
    end if;
    foreach v_table in array array['list_items', 'categories', 'catalog_items'] loop
        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
        ) then
            execute format('alter publication supabase_realtime add table public.%I', v_table);
        end if;
    end loop;
end $$;
