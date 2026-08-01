# Storage security

## Buckets (representative — verify in Supabase dashboard)

- `property-images` (avatars + listing media per codebase references).  
- Review **public** vs **private** flag per bucket.  
- Prefer **signed URLs** for private documents (contracts, ID copies).

## Policies

- Deny anonymous write to sensitive buckets.  
- Authenticated upload: constrain path prefix to `user_id` or `org_id` folder pattern via policy.

## MIME / malware

- Client: restrict picker file types + size.  
- Server: ClamAV or cloud malware scanning on upload pipeline (placeholder until implemented).

## Realtime

- If channels expose listing IDs, validate membership against RLS-equivalent rules in `realtime` authorization hooks.
