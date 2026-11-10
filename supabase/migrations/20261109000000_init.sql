-- ============================================================================
-- Reshima (רשימה) Initial Database Schema, RLS, Realtime & Storage
-- Managed declaratively via GitHub Actions (supabase-deploy.yml)
-- ============================================================================

create extension if not exists "pgcrypto";

-- 1. HOUSEHOLDS
create table if not exists public.households (
    id uuid primary key default gen_random_uuid(),
    name text not null default 'הבית שלנו / Our Home',
    invite_code text not null unique,
    created_at timestamptz not null default now()
);

-- 2. HOUSEHOLD MEMBERS
create table if not exists public.household_members (
    household_id uuid not null references public.households(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    display_name text not null default '',
    joined_at timestamptz not null default now(),
    primary key (household_id, user_id)
);

-- 3. SUPERMARKET AISLE CATEGORIES (Bilingual Hebrew & English)
create table if not exists public.categories (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    name_he text not null,
    name_en text not null,
    icon text not null default '🛒',
    color_hex text not null default '#10B981',
    sort_order int not null default 0,
    created_at timestamptz not null default now()
);

create index if not exists idx_categories_household_sort
    on public.categories(household_id, sort_order);

-- 4. CATALOG ITEMS (Autocomplete History & Staples)
create table if not exists public.catalog_items (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    name text not null,
    normalized_name text not null,
    default_category_id uuid references public.categories(id) on delete set null,
    default_unit text not null default 'pcs',
    usage_count int not null default 1,
    is_staple boolean not null default false,
    last_used_at timestamptz not null default now(),
    unique (household_id, normalized_name)
);

create index if not exists idx_catalog_items_lookup
    on public.catalog_items(household_id, usage_count desc);

-- 5. SHOPPING LISTS
create table if not exists public.shopping_lists (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households(id) on delete cascade,
    title text not null default 'רשימת קניות / Shopping List',
    is_archived boolean not null default false,
    created_at timestamptz not null default now()
);

-- 6. LIST ITEMS (Real-time Synced Items)
create table if not exists public.list_items (
    id uuid primary key default gen_random_uuid(),
    list_id uuid not null references public.shopping_lists(id) on delete cascade,
    household_id uuid not null references public.households(id) on delete cascade,
    category_id uuid references public.categories(id) on delete set null,
    name text not null,
    quantity numeric(10, 2) not null default 1,
    unit text not null default 'pcs',
    notes text not null default '',
    photo_path text,
    is_checked boolean not null default false,
    checked_at timestamptz,
    updated_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_list_items_list_checked
    on public.list_items(list_id, is_checked, created_at);

-- Auto-update updated_at timestamp
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    if new.is_checked = true and (old.is_checked is distinct from true) then
        new.checked_at = now();
    elsif new.is_checked = false then
        new.checked_at = null;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_list_items_updated_at on public.list_items;
create trigger trg_list_items_updated_at
before update on public.list_items
for each row execute function public.set_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) HELPERS & POLICIES
-- ============================================================================

create or replace function public.is_household_member(p_household_id uuid)
returns boolean
language sql
security definer
stable
as $$
    select exists (
        select 1
        from public.household_members hm
        where hm.household_id = p_household_id
          and hm.user_id = auth.uid()
    );
$$;

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.categories enable row level security;
alter table public.catalog_items enable row level security;
alter table public.shopping_lists enable row level security;
alter table public.list_items enable row level security;

-- Households policies
create policy "Members can view their households"
    on public.households for select
    using (public.is_household_member(id));

-- Household members policies
create policy "Members can view fellow household members"
    on public.household_members for select
    using (public.is_household_member(household_id));

-- Categories policies
create policy "Members can manage household categories"
    on public.categories for all
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));

-- Catalog items policies
create policy "Members can manage household catalog items"
    on public.catalog_items for all
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));

-- Shopping lists policies
create policy "Members can manage household shopping lists"
    on public.shopping_lists for all
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));

-- List items policies
create policy "Members can manage household list items"
    on public.list_items for all
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));

-- ============================================================================
-- HOUSEHOLD ONBOARDING & SEEDING RPC
-- ============================================================================

create or replace function public.seed_default_household_data(p_household_id uuid)
returns uuid
language plpgsql
security definer
as $$
declare
    v_produce_id uuid;
    v_dairy_id uuid;
    v_bakery_id uuid;
    v_meat_id uuid;
    v_pantry_id uuid;
    v_frozen_id uuid;
    v_cleaning_id uuid;
    v_other_id uuid;
    v_list_id uuid;
begin
    -- Seed default supermarket aisles if none exist yet
    if not exists (select 1 from public.categories where household_id = p_household_id) then
        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'פירות וירקות', 'Produce', '🥦', '#10B981', 10)
        returning id into v_produce_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'מוצרי חלב וביצים', 'Dairy & Eggs', '🧀', '#3B82F6', 20)
        returning id into v_dairy_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'מאפים ולחם', 'Bakery & Bread', '🥖', '#F59E0B', 30)
        returning id into v_bakery_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'בשר, עוף ודגים', 'Meat & Fish', '🥩', '#EF4444', 40)
        returning id into v_meat_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'מזווה ובישול', 'Pantry & Dry Goods', '🍝', '#8B5CF6', 50)
        returning id into v_pantry_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'קפואים', 'Frozen', '🧊', '#06B6D4', 60)
        returning id into v_frozen_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'ניקיון ופארם', 'Home & Pharmacy', '🧼', '#EC4899', 70)
        returning id into v_cleaning_id;

        insert into public.categories (household_id, name_he, name_en, icon, color_hex, sort_order)
        values (p_household_id, 'כללי', 'Other', '🛒', '#6B7280', 80)
        returning id into v_other_id;

        -- Seed common household staples for smart autocomplete
        insert into public.catalog_items (household_id, name, normalized_name, default_category_id, default_unit, usage_count, is_staple)
        values
            (p_household_id, 'חלב 3%', 'חלב 3%', v_dairy_id, 'pcs', 25, true),
            (p_household_id, 'ביצים L', 'ביצים l', v_dairy_id, 'pack', 20, true),
            (p_household_id, 'קוטג׳ 5%', 'קוטג׳ 5%', v_dairy_id, 'pcs', 18, true),
            (p_household_id, 'לחם מחמצת / פרוס', 'לחם מחמצת / פרוס', v_bakery_id, 'pcs', 18, true),
            (p_household_id, 'עגבניות', 'עגבניות', v_produce_id, 'kg', 16, true),
            (p_household_id, 'מלפפונים', 'מלפפונים', v_produce_id, 'kg', 16, true),
            (p_household_id, 'בננות', 'בננות', v_produce_id, 'kg', 12, true),
            (p_household_id, 'אבוקדו', 'אבוקדו', v_produce_id, 'kg', 11, true),
            (p_household_id, 'חזה עוף', 'חזה עוף', v_meat_id, 'kg', 10, true),
            (p_household_id, 'שמן זית', 'שמן זית', v_pantry_id, 'pcs', 8, true),
            (p_household_id, 'נייר טואלט', 'נייר טואלט', v_cleaning_id, 'pack', 7, true),
            (p_household_id, 'Milk 3%', 'milk 3%', v_dairy_id, 'pcs', 10, false),
            (p_household_id, 'Eggs (Large)', 'eggs (large)', v_dairy_id, 'pack', 9, false),
            (p_household_id, 'Tomatoes', 'tomatoes', v_produce_id, 'kg', 8, false)
        on conflict (household_id, normalized_name) do nothing;
    end if;

    -- Ensure at least one active shopping list exists
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

create or replace function public.join_or_create_household(
    p_invite_code text,
    p_household_name text default 'הבית שלנו',
    p_display_name text default ''
)
returns jsonb
language plpgsql
security definer
as $$
declare
    v_clean_code text;
    v_household_id uuid;
    v_list_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    v_clean_code := upper(trim(p_invite_code));
    if length(v_clean_code) < 3 then
        raise exception 'Invite code must be at least 3 characters';
    end if;

    select id into v_household_id
    from public.households
    where invite_code = v_clean_code;

    if v_household_id is null then
        insert into public.households (name, invite_code)
        values (coalesce(nullif(trim(p_household_name), ''), 'הבית שלנו'), v_clean_code)
        returning id into v_household_id;
    end if;

    insert into public.household_members (household_id, user_id, display_name)
    values (v_household_id, auth.uid(), coalesce(p_display_name, ''))
    on conflict (household_id, user_id)
    do update set display_name = excluded.display_name;

    v_list_id := public.seed_default_household_data(v_household_id);

    return jsonb_build_object(
        'household_id', v_household_id,
        'list_id', v_list_id,
        'invite_code', v_clean_code
    );
end;
$$;

-- ============================================================================
-- SUPABASE REALTIME & STORAGE BUCKET
-- ============================================================================

do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        alter publication supabase_realtime add table public.list_items;
        alter publication supabase_realtime add table public.categories;
        alter publication supabase_realtime add table public.catalog_items;
    end if;
exception
    when duplicate_object then null;
end $$;

insert into storage.buckets (id, name, public)
values ('item-photos', 'item-photos', false)
on conflict (id) do nothing;

create policy "Authenticated users can upload item photos"
    on storage.objects for insert
    to authenticated
    with check (bucket_id = 'item-photos');

create policy "Authenticated users can view item photos"
    on storage.objects for select
    to authenticated
    using (bucket_id = 'item-photos');

create policy "Authenticated users can delete item photos"
    on storage.objects for delete
    to authenticated
    using (bucket_id = 'item-photos');
