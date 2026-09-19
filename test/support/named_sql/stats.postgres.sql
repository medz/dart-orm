-- :not_a_parameter; fixed query with explicit result aliases
SELECT author, COUNT(*) AS post_count, SUM(points)::bigint AS points
FROM posts
WHERE points >= :minimum AND (:author IS NULL OR author = :author)
GROUP BY author;
