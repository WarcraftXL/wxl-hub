-- Where an install came from, so an update can tell whether there is a newer one.
--
-- `source` is for the user: the asset and tag an install actually came from, which is the difference
-- between "1.2.0" and "wxl-foo-1.2.0.zip from v1.2.0". `etag` is for the hub: a repository that
-- ships a committed binary has no tag to compare, and the blob hash is the only honest update signal.

ALTER TABLE installed ADD COLUMN source TEXT;
ALTER TABLE installed ADD COLUMN etag TEXT;
