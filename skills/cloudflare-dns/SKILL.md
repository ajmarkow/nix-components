---
name: cloudflare-dns
description: Use when creating, updating, deleting, or auditing DNS records for a project's domain/zone via Cloudflare -- e.g. "add a DNS record for this project", "point this subdomain at...", "what DNS records does this zone have". Drives Cloudflare's MCP server instead of the dashboard.
argument-hint: <zone> <record request, in plain language>
allowed-tools: [Bash]
user-invocable: true
---

Manage DNS records through Cloudflare's MCP server (`cloudflare` in the `mcpm` aggregate) instead of the Cloudflare dashboard.

## How the server works

Cloudflare's MCP server (`https://mcp.cloudflare.com/mcp`) exposes the entire Cloudflare API through exactly two tools:

- **search(query)** -- finds the relevant API operations (e.g. "list DNS records", "create DNS record") and returns their typed schema.
- **execute(code)** -- runs generated JavaScript against the Cloudflare API client for the operations you looked up.

Look up the exact tool names available in this session with `ToolSearch("select:cloudflare_search,cloudflare_execute")` (mcpm aggregates tools as `<server>_<tool>`) -- if those don't resolve, search `"cloudflare mcp"` instead and use whatever names come back.

The token behind this server is scoped to specific zones (Zone:DNS:Edit + Zone:Zone:Read) -- it can only see and edit the zones it was explicitly granted, never the whole account. An "unauthorized" or empty-zone-list error usually means the target domain isn't in that scope, not that the server is broken.

## Workflow

1. **Identify the zone.** Ask the user for the domain if it's not obvious from the project. Use `search()` for a "list zones" operation, then `execute()` it to confirm the zone exists and is in scope.
2. **List current records first.** Before creating anything, `execute()` a DNS-records-list call for that zone. Check for an existing record with the same name -- creating a duplicate `A`/`CNAME` is a common mistake and Cloudflare allows it silently.
3. **Create or update.** Use `search()` to find the create/update DNS record operation, then `execute()` it with the exact type, name, content, TTL, and `proxied` flag the user wants. Default `proxied: true` for web traffic unless the user needs the raw IP exposed (e.g. non-HTTP services, mail records).
4. **Verify.** Re-list the zone's records (or `dig`/`nslookup` the name) to confirm the record landed as expected.
5. **Deletions need confirmation.** Never delete or overwrite a record you didn't just list and identify by name in this session -- if a record's purpose is unclear, ask the user before touching it.

## Notes

- MX, TXT (especially SPF/DKIM/DMARC), and NS records are easy to break silently -- double check `content` formatting for these before writing.
- If the zone you need isn't in the token's scope, tell the user to add it to the Cloudflare API token's zone list (dashboard -> Profile -> API Tokens) -- don't try to work around it with a different credential.
