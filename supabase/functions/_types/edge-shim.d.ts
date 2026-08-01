/** IDE-only types for Supabase Edge Functions (Deno runtime). Not used at deploy. */
/// <reference lib="dom" />

declare namespace Deno {
  namespace env {
    function get(key: string): string | undefined;
  }
}

type EdgeServeHandler = (req: Request) => Response | Promise<Response>;

declare module "https://deno.land/std@0.224.0/http/server.ts" {
  export function serve(handler: EdgeServeHandler): void;
}

declare module "https://esm.sh/@supabase/supabase-js@2.45.4" {
  export function createClient(...args: unknown[]): any;
}

declare module "https://esm.sh/@supabase/supabase-js@2.49.1" {
  export function createClient(...args: unknown[]): any;
}

declare module "https://esm.sh/stripe@14.21.0?target=deno" {
  const Stripe: new (...args: unknown[]) => any;
  export default Stripe;
}

declare module "jsr:@supabase/functions-js/edge-runtime.d.ts" {}
