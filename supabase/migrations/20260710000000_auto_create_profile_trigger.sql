-- Guarantees every auth.users row has a matching profiles row, atomically,
-- in the SAME transaction as account creation — closing the gap where a
-- client-side crash/network-drop/kill between "auth succeeds" and "client
-- inserts profiles row" left a signed-in user with no profile (blank
-- name, no saved progress, everything profile-dependent silently empty).
--
-- All other columns fall back to the profiles table's own DEFAULTs
-- (level='beginner', native_language='English', etc.) — this only needs to
-- set id + a best-effort display name.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email, 'Student')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- One-time backfill: repair any orphaned auth.users rows that already exist
-- from testing (auth account with no profiles row).
INSERT INTO public.profiles (id, display_name)
SELECT u.id, COALESCE(u.raw_user_meta_data->>'full_name', u.email, 'Student')
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;
