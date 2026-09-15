# GSTIN verification setup

The Flutter app calls the `gstin-lookup` Supabase Edge Function. The GSTIN API
key remains only in Supabase and is never stored in the mobile app.

From a terminal with the Supabase CLI signed in and linked to this project:

```powershell
supabase secrets set GSTINAPI_KEY="your-gstinapi.in-key"
supabase functions deploy gstin-lookup
```

The function validates and uppercases GSTIN values before contacting
`gstinapi.in`; retries only HTTP 429 and 502 up to three attempts; and logs
the remaining credit count to Supabase Edge Function logs. It requests the
provider's `include=profile` data but populates the existing customer form
only with name and address fields that the app currently stores.

Never add `GSTINAPI_KEY` to Flutter, a `.env` file committed to Git, or the
Supabase publishable key configuration.
