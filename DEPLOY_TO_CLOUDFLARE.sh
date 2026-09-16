#!/bin/bash
set -e
# CodFlow - Deploy to Cloudflare (Overwrite old deployment)
# Run this on YOUR local PC/Mac, NOT in Arena sandbox
# The sandbox blocks api.cloudflare.com, so deployment must happen locally

echo "=== CodFlow Deploy to Cloudflare (Overwrite) ==="
echo ""

# 1. Check auth
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "Checking wrangler login..."
  npx wrangler whoami || (echo "Run: npx wrangler login  OR  export CLOUDFLARE_API_TOKEN=..." && exit 1)
else
  echo "Using CLOUDFLARE_API_TOKEN"
  npx wrangler whoami
fi

# 2. Show existing resources
echo ""
echo "=== Existing Resources ==="
echo "D1 Databases:"
npx wrangler d1 list || true
echo ""
echo "R2 Buckets:"
npx wrangler r2 bucket list || true
echo ""
echo "KV Namespaces:"
npx wrangler kv namespace list || true

# 3. Ask for project prefix
PROJECT=${1:-codflow}
echo ""
echo "Using project prefix: $PROJECT"
echo "If you want to overwrite OLD deployment, use SAME names as before."
echo "If old names were codflow-server, codflow-dashboard, keep PROJECT=codflow"
read -p "Continue with PROJECT=$PROJECT? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

# 4. Create or reuse resources
echo ""
echo "Creating D1 ${PROJECT}-db (if exists, will error - then use existing ID)"
npx wrangler d1 create ${PROJECT}-db || echo "D1 already exists, please copy its ID from list above"

echo "Creating R2 ${PROJECT}-images"
npx wrangler r2 bucket create ${PROJECT}-images || echo "R2 already exists"

echo "Creating KV RATE_LIMIT"
npx wrangler kv namespace create RATE_LIMIT || true

echo "Creating KV OAUTH_KV"
npx wrangler kv namespace create OAUTH_KV || true

echo ""
echo "=== IMPORTANT ==="
echo "Copy the database_id (UUID) and KV ids (32-hex) from output above"
echo "Then edit these files:"
echo "  - cod-server/wrangler.toml (database_id + kv ids in both [ ] and [env.production])"
echo "  - cod-client-astro/wrangler.toml (database_id + kv id)"
echo "  - .env (COD_DB_NAME=${PROJECT}-db, COD_R2_BUCKET_NAME=${PROJECT}-images)"
echo ""
read -p "Press Enter after you edited wrangler.toml files..."

# 5. Verify no placeholders
echo "Checking for placeholders..."
if grep -r "00000000-0000\|00000000000000000000000000000000" cod-server/wrangler.toml cod-client-astro/wrangler.toml; then
  echo "ERROR: Placeholders still found! Fix before deploy."
  exit 1
else
  echo "No placeholders - OK"
fi

# 6. Generate secrets if needed
echo ""
echo "Generating secrets (if you don't have old ones, use these new ones):"
BETTER_AUTH_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")
STORE_API_KEY=$(node -e "console.log(require('crypto').randomBytes(24).toString('base64url'))")
MCP_LOGIN_TICKET_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo "BETTER_AUTH_SECRET=$BETTER_AUTH_SECRET"
echo "STORE_API_KEY=$STORE_API_KEY"
echo "MCP_LOGIN_TICKET_SECRET=$MCP_LOGIN_TICKET_SECRET"
echo ""
echo "Save these in a safe place!"

# 7. Migrate & Seed Remote
echo ""
echo "=== Migrating Remote D1 ==="
cd cod-server
npx wrangler d1 migrations apply ${PROJECT}-db --remote || npm run db:migrate:remote

echo "Seeding remote (store + products)..."
STORE_API_KEY=$STORE_API_KEY npm run db:seed:remote || npx wrangler d1 execute ${PROJECT}-db --remote --file=../.wrangler-shared/seed.sql || true

cd ../cod-client-astro
echo "Seeding admin remote..."
ADMIN_EMAIL=admin@example.com ADMIN_NAME=Admin npm run seed:admin:remote || true

# 8. Deploy
echo ""
echo "=== Deploying Workers (will OVERWRITE old ones) ==="
cd ../cod-server
npx wrangler deploy
echo "cod-server deployed"

# Set secrets on cod-server
echo "Setting secrets on cod-server..."
printf "$BETTER_AUTH_SECRET" | npx wrangler secret put BETTER_AUTH_SECRET
printf "$MCP_LOGIN_TICKET_SECRET" | npx wrangler secret put MCP_LOGIN_TICKET_SECRET
printf "$STORE_API_KEY" | npx wrangler secret put STORE_API_KEY || true

cd ../cod-client-astro
npx wrangler deploy
echo "cod-client-astro deployed"
printf "$BETTER_AUTH_SECRET" | npx wrangler secret put BETTER_AUTH_SECRET
printf "$MCP_LOGIN_TICKET_SECRET" | npx wrangler secret put MCP_LOGIN_TICKET_SECRET

cd ../cod-astro/theme01
# Need COD_SERVER_URL in root .env
if grep -q "localhost" ../../.env; then
  echo "WARNING: .env still has localhost for COD_SERVER_URL - update it to https://<api-domain>"
  echo "Example: COD_SERVER_URL=https://codflow-server.<subdomain>.workers.dev"
  read -p "Enter your API URL (e.g. https://codflow-server.xxx.workers.dev): " API_URL
  echo "COD_SERVER_URL=$API_URL" >> ../../.env
fi
npx wrangler deploy || npm run deploy
echo "theme01 deployed"

echo ""
echo "=== Smoke Tests ==="
echo "Get your worker URLs from deploy output above, then test:"
echo "curl https://<api-url>/api/docs -> should be 200"
echo "Open dashboard URL in browser and login with admin@example.com"

echo ""
echo "=== Done! Old deployment overwritten ==="
