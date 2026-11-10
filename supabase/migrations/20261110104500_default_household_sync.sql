-- ============================================================================
-- Seed Default Shared Household & Enable Frictionless Sync for Both iPhones
-- ============================================================================

do $$
declare
    v_household_id uuid := '00000000-0000-0000-0000-000000000001';
    v_list_id uuid := '00000000-0000-0000-0000-000000000002';
    v_seeded_list_id uuid;
    v_dairy_id uuid;
    v_produce_id uuid;
    v_bakery_id uuid;
begin
    insert into public.households (id, name, invite_code)
    values (v_household_id, 'משפחת ציפורי / Zipori Home', 'ZIPORI')
    on conflict (id) do nothing;

    insert into public.shopping_lists (id, household_id, title, is_archived)
    values (v_list_id, v_household_id, 'רשימת קניות / Shopping List', false)
    on conflict (id) do nothing;

    v_seeded_list_id := public.seed_default_household_data(v_household_id);

    -- Seed 3 initial items if list is empty
    if not exists (select 1 from public.list_items where list_id = v_list_id) then
        select id into v_produce_id from public.categories where household_id = v_household_id and sort_order = 10 limit 1;
        select id into v_dairy_id from public.categories where household_id = v_household_id and sort_order = 20 limit 1;
        select id into v_bakery_id from public.categories where household_id = v_household_id and sort_order = 30 limit 1;

        insert into public.list_items (list_id, household_id, category_id, name, quantity, unit, notes)
        values
            (v_list_id, v_household_id, v_dairy_id, 'חלב 3%', 2, 'pcs', 'תנובה קרטון'),
            (v_list_id, v_household_id, v_produce_id, 'עגבניות שרי', 1, 'pack', ''),
            (v_list_id, v_household_id, v_bakery_id, 'לחם מחמצת', 1, 'pcs', '');
    end if;
end $$;

-- Allow shared household access via anon/authenticated API key for the household app
drop policy if exists "Shared household access on households" on public.households;
create policy "Shared household access on households"
    on public.households for all
    to anon, authenticated
    using (true)
    with check (true);

drop policy if exists "Shared household access on categories" on public.categories;
create policy "Shared household access on categories"
    on public.categories for all
    to anon, authenticated
    using (true)
    with check (true);

drop policy if exists "Shared household access on catalog_items" on public.catalog_items;
create policy "Shared household access on catalog_items"
    on public.catalog_items for all
    to anon, authenticated
    using (true)
    with check (true);

drop policy if exists "Shared household access on shopping_lists" on public.shopping_lists;
create policy "Shared household access on shopping_lists"
    on public.shopping_lists for all
    to anon, authenticated
    using (true)
    with check (true);

drop policy if exists "Shared household access on list_items" on public.list_items;
create policy "Shared household access on list_items"
    on public.list_items for all
    to anon, authenticated
    using (true)
    with check (true);
