-- ============================================================
-- Stage 3 · 第 1 步：启用 pgvector 扩展（必须跑在 prisma db push 之前）
-- 用法（服务器上，postgres 容器已经起来之后）：
--   docker exec -i sc-postgres psql -U postgres -d summer_checkin \
--     -v ON_ERROR_STOP=1 < init-01-extension.sql
--
-- 【为什么顺序不能反】
-- schema.prisma 里两处 embedding 写的是 Unsupported("vector(1024)")。
-- db push 会照原样生成 CREATE TABLE ... "embedding" vector(1024)，
-- 而 vector 这个类型只有在扩展启用后才存在于"当前这个库"里，
-- 没启用就直接 type "vector" does not exist 建表失败。
--
-- 更关键的一句：扩展是**按库**启用的，不是按实例、更不是按镜像。
-- 镜像里带了 pgvector 的 .so 文件 ≠ 这个库能用。
-- （上游那个迁移脚本的前置条件注释就踩过这个描述："文件已内置但 installed_version 为空"。）
--
-- Prisma 自己也能建扩展，但要开 postgresqlExtensions 预览特性并在 schema 里写
-- extensions = [vector]。本项目没这么写 —— 所以这一步只能手工，而且它本身就是
-- "用了 Unsupported 类型就要自己负责扩展"这条规矩的落地。
-- ============================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- 校验：installed_version 不再是空，就是启用成功了
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'vector';
