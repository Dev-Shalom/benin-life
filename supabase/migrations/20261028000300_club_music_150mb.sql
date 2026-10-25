-- Owner: club music files up to 150 MB (was 30 MB). Idempotent.
-- This is the BUCKET limit. Supabase also has a global upload limit (Dashboard > Storage > Settings > "Upload file size limit",
-- 50 MB on the free plan) that must be at least 150 MB for such files to go through.
update storage.buckets
   set file_size_limit = 157286400,   -- 150 MB
       allowed_mime_types = array['audio/mpeg', 'audio/mp3', 'audio/x-mpeg', 'audio/x-mp3', 'audio/mpeg3', 'audio/x-mpeg-3',
                                  'audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac', 'audio/ogg', 'application/ogg',
                                  'audio/wav', 'audio/x-wav', 'audio/wave', 'audio/vnd.wave', 'audio/webm']::text[]
 where id = 'club-music';
notify pgrst, 'reload schema';
