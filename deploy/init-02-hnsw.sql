-- ============================================================
-- Stage 3 · 第 3 步：建两个 HNSW 向量索引（必须跑在 prisma db push 之后）
-- 用法：
--   docker exec -i sc-postgres psql -U postgres -d summer_checkin \
--     -v ON_ERROR_STOP=1 < init-02-hnsw.sql
--
-- 【为什么 db push 建不出这两个索引】
-- Prisma 的 @@index 只能表达普通 B-tree 索引，语法里没有 USING hnsw(...) 这种
-- "索引方法 + 操作符家族"的位置。所以 schema 里那些 @@index 都会被建出来，
-- 唯独向量索引必须手工补 —— 这不是本项目偷懒，是 Prisma 的能力边界，
-- 业界的通用做法就是"schema 之外再挂一个手工 SQL 脚本"（本项目放 prisma/*.sql）。
--
-- 【为什么不能直接跑上游那份 prisma/migrate-to-pgvector.sql】
-- 那是给"已经在跑的旧库"做 jsonb → vector 一次性搬家用的，它自己也写了不可重复执行：
-- 新库里 embedding 已经是 vector 类型，再对它做 (embedding #>> '{}')::vector
-- 会直接报错（#>> 只适用于 jsonb）。
-- 我们只要它第 4 步那两条 CREATE INDEX，其余全部跳过。
--
-- 【vector_cosine_ops 是怎么定的】
-- 要和查询里用的距离运算符一致。代码里余弦相似用的是 <=>，
-- 对应的 ops family 就是 vector_cosine_ops；
-- 若填成 vector_l2_ops（欧氏 <–>）或 vector_ip_ops（内积 <#>），
-- 表照样建、查询照样跑，只是**索引完全不命中**，退化成全表扫 ——
-- 这类"不报错但白干"的错，是数据库里最难发现的一类，值得记一条。
-- ============================================================

-- IF NOT EXISTS 让这份脚本可以重复执行（第 1 步那份也可以，这是故意的差别：
-- 初始化脚本能重跑，比"跑第二遍炸了不知道现在什么状态"值钱得多）
CREATE INDEX IF NOT EXISTS documentchunk_embedding_hnsw
    ON documentchunk USING hnsw (embedding vector_cosine_ops);

CREATE INDEX IF NOT EXISTS usermemory_embedding_hnsw
    ON usermemory USING hnsw (embedding vector_cosine_ops);

-- ---- 校验：三件事，一条 SQL 都不省 ----
-- 1 两个索引都在，且索引方法确实是 hnsw（看 indexdef 里的 "USING hnsw"）
SELECT indexname, indexdef
FROM pg_indexes
WHERE indexname IN ('documentchunk_embedding_hnsw', 'usermemory_embedding_hnsw');

-- 2 列类型确实是 vector(1024)，不是回退成了 jsonb / 变成了其它维度
--   （维度错了后果最狠：写入时报 "expected 1024 dimensions, not 1536"）
SELECT table_name, data_type, udt_name
FROM information_schema.columns
WHERE table_name IN ('documentchunk', 'usermemory') AND column_name = 'embedding';

-- 3 扩展状态 + 全库表数量（db push 到底建了多少张表，心里要有数：schema 里 24 个 model）
SELECT name, installed_version FROM pg_available_extensions WHERE name = 'vector';
SELECT COUNT(*) AS tables_in_public FROM pg_tables WHERE schemaname = 'public';
