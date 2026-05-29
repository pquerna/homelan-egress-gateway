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
  'egress-v1-static-allowlist',
  'Home sandbox egress policy. Default DENY. Allow low-risk reads: package metadata/downloads, source fetch/clone, release files, and official technical docs. Allow GitHub git-upload-pack/read API only when it does not send secrets or local/private data. DENY data exfiltration: secrets, tokens, keys, cookies, env, SSH material, personal files, archives, logs, prompts, home/LAN data, or large/opaque payloads. DENY data deletion/modification: delete, overwrite, push, publish, upload, email/message/post, webhook, issue/PR/comment creation, repo/package changes, cloud-storage writes. DENY private/link-local/metadata destinations. If unsure, DENY.',
  '',
  '',
  '[
    {"methods":["GET","HEAD"],"url_pattern":"http://deb.debian.org/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://deb.debian.org/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"http://security.debian.org/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://security.debian.org/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://github.com/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://api.github.com/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://registry.npmjs.org/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://pypi.org/","match_type":"prefix","action":"allow"},
    {"methods":["GET","HEAD"],"url_pattern":"https://files.pythonhosted.org/","match_type":"prefix","action":"allow"}
  ]'::jsonb,
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
