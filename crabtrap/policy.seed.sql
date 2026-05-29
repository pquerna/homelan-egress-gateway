INSERT INTO llm_policies (
  id,
  name,
  prompt,
  provider,
  model,
  static_rules,
  status
) VALUES (
  'llmpol_egress_v1',
  'egress-v1-home-sandbox',
  'Default DENY. GET is not automatically safe; inspect URL/query/headers/body. Allow only clear public package installs, public source/docs fetches, and read-only API calls. DENY exfiltration: secrets, tokens, keys, cookies, env, prompts, logs, personal files, home/LAN paths, archives, large or encoded/opaque blobs. DENY C2/backdoors: beacons, polling for commands, webhooks, paste/file-sharing, tunnels, remote shell, persistence installers. DENY writes: upload, publish, push, delete, modify, message/comment/issue/PR/email. DENY private/link-local/metadata destinations. If unsure, DENY.',
  '',
  '',
  '[]'::jsonb,
  'published'
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  prompt = EXCLUDED.prompt,
  provider = EXCLUDED.provider,
  model = EXCLUDED.model,
  static_rules = EXCLUDED.static_rules,
  status = EXCLUDED.status,
  deleted_at = NULL;

INSERT INTO users (
  id,
  is_admin,
  role,
  llm_policy_id
) VALUES (
  :'gateway_user',
  false,
  'user',
  'llmpol_egress_v1'
) ON CONFLICT (id) DO UPDATE SET
  llm_policy_id = EXCLUDED.llm_policy_id,
  updated_at = NOW();

INSERT INTO user_channels (
  id,
  user_id,
  channel_type,
  payload
) VALUES (
  'chan_egress_gateway_auth',
  :'gateway_user',
  'gateway_auth',
  jsonb_build_object('gateway_auth_token', :'gateway_token')
) ON CONFLICT (user_id, channel_type) DO UPDATE SET
  payload = EXCLUDED.payload,
  updated_at = NOW();
