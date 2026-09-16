# CodFlow Setup Summary

## Status
- Local setup: ✅ COMPLETE
- Remote Cloudflare setup: ❌ BLOCKED by sandbox egress filtering (api.cloudflare.com not reachable)

## Local Setup Done
- npm ci --ignore-scripts (953 packages)
- Generated local wrangler.toml with random UUIDs (gitignored)
- Created .env, .dev.vars for all workspaces
- Migrations local: 25 applied
- Seed local: 4 products, 2 categories, store-local-dev
- Admin local: admin@example.com / 3a7m2_3KseBviuEE

## To Complete Remote (Run on YOUR machine)

### 1. Authenticate
```bash
npx wrangler login
# OR
export CLOUDFLARE_API_TOKEN=your_token
npx wrangler whoami
```

### 2. Create Resources (use unique prefix!)
```bash
PROJECT=mystore  # choose unique name
npx wrangler d1 create ${PROJECT}-db
npx wrangler r2 bucket create ${PROJECT}-images
npx wrangler kv namespace create RATE_LIMIT
npx wrangler kv namespace create OAUTH_KV
```

Capture database_id (UUID) and KV ids (32-hex).

### 3. Bind IDs
Edit:
- cod-server/wrangler.toml
- cod-client-astro/wrangler.toml
Replace database_id and kv id placeholders.

Also edit root .env:
```
COD_DB_NAME=mystore-db
COD_R2_BUCKET_NAME=mystore-images
COD_SERVER_URL=https://api.yourdomain.com
```

And:
- cod-client-astro/.env -> PUBLIC_API_URL=https://api.yourdomain.com
- cod-client-astro/wrangler.toml [vars] -> PUBLIC_APP_URL, PUBLIC_API_URL, PUBLIC_TRUSTED_ORIGINS

### 4. Secrets
Generate:
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))" # BETTER_AUTH_SECRET
node -e "console.log(require('crypto').randomBytes(24).toString('base64url'))" # STORE_API_KEY
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))" # MCP_LOGIN_TICKET_SECRET
```

Deploy first, then set secrets:
```bash
cd cod-server && npx wrangler deploy
printf '<BETTER_AUTH_SECRET>' | npx wrangler secret put BETTER_AUTH_SECRET
printf '<MCP_LOGIN_TICKET_SECRET>' | npx wrangler secret put MCP_LOGIN_TICKET_SECRET

cd ../cod-client-astro && npx wrangler deploy
printf '<same BETTER_AUTH_SECRET>' | npx wrangler secret put BETTER_AUTH_SECRET
printf '<same MCP_LOGIN_TICKET_SECRET>' | npx wrangler secret put MCP_LOGIN_TICKET_SECRET
```

For theme01:
```bash
printf '<STORE_API_KEY>' | npx wrangler secret put STORE_API_KEY --name <theme01-worker-name>
```

### 5. Migrate & Seed Remote
```bash
cd cod-server
npx wrangler d1 migrations apply ${PROJECT}-db --remote
STORE_API_KEY=<key> npm run db:seed:remote

cd ../cod-client-astro
ADMIN_EMAIL=admin@example.com ADMIN_NAME=Admin npm run seed:admin:remote
```

### 6. Deploy All
```bash
cd cod-server && npx wrangler deploy
cd ../cod-client-astro && npx wrangler deploy
cd ../cod-astro/theme01 && npx wrangler deploy
```

### 7. Smoke Test
```bash
curl https://<api>/api/docs -> 200
curl -X POST https://<dashboard>/api/auth/sign-in/email -H "Origin: https://<dashboard>" -H "Content-Type: application/json" -d '{"email":"admin@example.com","password":"..."}' -> 200
```

### 8. R2 Media Domain (Optional but recommended)
- Cloudflare Dashboard -> R2 -> bucket -> Settings -> Custom Domains -> Connect media.yourdomain.com
- Create R2 API Token (Object Read & Write for that bucket)
- Set MEDIA_DOMAIN in cod-server/wrangler.toml
- Set secrets:
```
printf '<CF_ACCOUNT_ID>' | npx wrangler secret put CF_ACCOUNT_ID
printf '<R2_ACCESS_KEY_ID>' | npx wrangler secret put R2_ACCESS_KEY_ID
printf '<R2_SECRET_ACCESS_KEY>' | npx wrangler secret put R2_SECRET_ACCESS_KEY
```
- Redeploy cod-server

See .agents/skills/codflow-setup/SKILL.md for full details.

