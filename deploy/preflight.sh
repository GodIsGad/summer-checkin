#!/bin/sh
# ============================================================
# 启动前预检：确认 .env 里该填的都填了，再交给 docker compose
#
# 用法（在 /srv/summer-checkin/repo/deploy 或任何能读到 .env 的地方）：
#   sh preflight.sh            # 只检查，不改动任何东西
#
# 为什么要有这个文件，而不是把规矩写进 compose：
#   compose 的"没配就拒绝启动"语法（变量名后跟 :?）实测两次把整行
#   吃成非法变量名——报错文案里的中文标点会被解析器吞进变量名。
#   语法糖不可靠就退回朴素写法：compose 里 ${POSTGRES_PASSWORD} 没配就是空串，
#   "必须非空"这条由这里负责。
#
# 一条硬规矩：本脚本永远只打印【键名 + 长度】，绝不打印值。
#   服务器上敲一条命令，输出会被顺手贴进聊天记录/截图——
#   密码一旦出现在那种地方就等于泄露了，而"看一眼确认填没填"是最常用的动作。
# ============================================================

ENV_FILE=./.env
if [ ! -f "$ENV_FILE" ]; then
  echo "找不到 $ENV_FILE"
  echo "compose 只读它自己那个目录下的 .env。若是软链方式管理，先确认链接有效：ls -l $ENV_FILE"
  exit 1
fi

# 必须由我们把关的键：空 = 直接失败。
# 只列"空了服务就起不来或起不来对"的那些；可选键放下面单独看。
REQUIRED="POSTGRES_PASSWORD BETTER_AUTH_SECRET NEXT_SERVER_ACTIONS_ENCRYPTION_KEY ACR_VPC APP_TAG"

# 有默认倾向、但空着会静默降级的键：只 WARN，不拦。
# CRON_SECRET 空 = /api/agent/cron/daily 变成不鉴权的公开接口（BUG-01），
# 学习阶段没接定时器可以容忍，但绝不能"空着且没人说"。
WARN_IF_EMPTY="CRON_SECRET"

fail=0

# 取一个键的值：只取最后一次的 KEY=VALUE 写法，去掉行尾 \r（Windows 改过的文件常见）
# 注意这里必须先赋值给 key 再拼进 sed：写成 "$$1" 会被 shell 展开成「进程号 + 1」，
# 于是正则匹配的是一个根本不存在的键，所有值都读成空——这类错只会表现为"全都 [空]"，很坑。
get_val() {
  key=$1
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r'
}

check() {
  name=$1
  val=$(get_val "$name")
  len=$(printf '%s' "$val" | wc -c | tr -d ' ')
  if [ "$len" -eq 0 ]; then
    echo "  [空]   $name"
    return 1
  fi
  echo "  [OK]   $name  (${len} 字符)"
  return 0
}

echo "== 必需项 =="
for k in $REQUIRED; do
  check "$k" || fail=1
done

echo "== 可选项（空了不拦启动，但会有后果）=="
for k in $WARN_IF_EMPTY; do
  check "$k" || echo "         ↑ 空着会让定时器接口无鉴权（见 BUG-01），学习阶段可先不管"
done

# BETTER_AUTH_URL 单独看：它空着也能起来，但填错的后果是"登录成功却没有 cookie"，
# 属于最难查的一类错，所以这里把它当前值原样打出来——它不是秘密（就是公网地址）。
BAU=$(get_val BETTER_AUTH_URL)
echo "== 对外地址 =="
if [ -z "$BAU" ]; then
  echo "  [空]   BETTER_AUTH_URL  ← 登录会 200 掉线，务必填 http://公网IP:8080"
  fail=1
else
  echo "  $BAU"
fi

# 顺手把 compose 需要的两件事确认掉，避免跑到 up 那步才发现
echo "== 环境 =="
if ! docker compose version >/dev/null 2>&1; then
  echo "  [失败] docker compose 不可用（需要 v2）"
  fail=1
else
  echo "  [OK]   $(docker compose version --short 2>/dev/null)"
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "预检没过，先补齐上面标 [空] 的键再来。本脚本不写文件、不改 .env。"
  exit 1
fi

echo
echo ">>> 预检通过，可以 docker compose up -d postgres"
