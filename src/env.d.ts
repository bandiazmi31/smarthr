/// <reference types="astro/client" />

import type { Actor } from './lib/actor';
import type { SmartHrClient } from './lib/supabase';

declare global {
  namespace App {
    interface Locals {
      /** Request-scoped Supabase client carrying the caller's session. */
      supabase: SmartHrClient;
      /** Who is making this request: HR, a HOD, an employee, or nobody. */
      actor: Actor;
    }
  }
}

interface ImportMetaEnv {
  readonly SUPABASE_URL: string;
  readonly SUPABASE_ANON_KEY: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
