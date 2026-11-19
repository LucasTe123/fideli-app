-- Product photos are compressed on-device at a high quality. Allow enough
-- room for detailed 2,000 px images instead of forcing them below 350 KB.
update storage.buckets
set file_size_limit = 2000000,
    allowed_mime_types = array['image/jpeg']
where id = 'storefront-images';
