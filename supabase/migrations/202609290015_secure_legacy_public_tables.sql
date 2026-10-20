do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'Account',
    'AdCampaign',
    'AutomationRule',
    'CampaignAnalytics',
    'ChannelAnalytics',
    'PlatformConfig',
    'Post',
    'PostAnalytics',
    'PostChannel',
    'Session',
    'SocialChannel',
    'User',
    'VerificationToken',
    'Workspace',
    'WorkspaceAnalytics',
    'WorkspaceMember'
  ]
  loop
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = table_name
        and c.relkind in ('r', 'p')
    ) then
      execute format(
        'alter table %I.%I enable row level security',
        'public',
        table_name
      );
      execute format(
        'revoke all privileges on table %I.%I from public, anon, authenticated',
        'public',
        table_name
      );
    end if;
  end loop;
end
$$;

comment on schema public is
  'API-exposed application schema. Every table must use RLS and explicit least-privilege grants.';
