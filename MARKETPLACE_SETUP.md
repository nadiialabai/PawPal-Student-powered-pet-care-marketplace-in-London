# UniTails two-sided marketplace — implementation foundation

This branch is **not deployed**. The existing public homepage remains a pre-launch concept with demo-only forms. Do not claim live registrations or bookings.

## Proposed stack
Keep the existing static HTML/CSS design. Use Supabase Auth (email verification), PostgreSQL, and Row Level Security for accounts and data. Use the public Supabase anon/publishable key only in the browser; never expose the service-role key. Configure Supabase URL and publishable key after creating a project.

## Schema included
`supabase/migrations/20261114_marketplace_foundation.sql` defines owner/carer profiles, owner pets, two-way interest requests, accepted connections, private messages, blocks and RLS. Either side may send interest; the recipient accepts using `accept_interest(request_uuid)`. Only acceptance establishes a connection. `resolve_interest(request_uuid, 'declined'|'cancelled')` handles rejection/cancellation.

## Before a real launch
- Provision Supabase and apply/review migration in a non-production environment.
- Implement login/signup, email verification, role onboarding, profile editing, discovery, request inbox, accept/decline, connection list, messaging, blocking and reporting in the frontend.
- Implement rate limits, spam prevention, abuse reporting and moderation, privacy notice, account deletion/data export, and appropriate pet-care safety checks. Verify all legal/insurance claims before publication.
- Test with two distinct verified test accounts, both initiation directions, blocked users, unauthorized API requests, refresh persistence, mobile Safari and accessibility.
- Restrict profile exposure and consider additional fields/consent before collecting precise location or pet medical details.
- Review the SQL policies and RPC permissions with a security specialist before real user data is stored.

**Current state:** Database migration committed to an isolated feature branch only. No Supabase backend provisioned, no frontend integration and no live end-to-end tests completed.
