#!/bin/bash
# ============================================================
# bt_migrate.sh —— 宝塔软件跨服务器迁移总控（php / nginx 通用）
#
# 适用场景：两台同系统、同 CPU 架构的服务器（均装宝塔面板 v9），
#   其中 B 有外网、A 无外网。在 B 上装好软件后，用本脚本把
#   编译好的软件整包 + 运行依赖 打包，搬到 A 解包即可运行，
#   A 的宝塔面板能通过文件探测自动识别到迁移过来的软件。
#
# 子命令：
#   package <php|nginx> [php版本...]   在【B服务器/有外网】执行，生成迁移包
#   restore <php|nginx>               在【A服务器/无外网】执行，从同级目录读取迁移包还原
#
# 用法示例：
#   ./bt_migrate.sh package php            # 自动扫描 /www/server/php 下所有已装 PHP 并打包
#   ./bt_migrate.sh package php 82 8.2 74  # 只打包指定版本（82 / 8.2 / 74 混写均可）
#   ./bt_migrate.sh package nginx          # 打包 nginx 整包 + 运行依赖
#   ./bt_migrate.sh restore php            # 从同级 php_migrate.tar.gz 还原
#   ./bt_migrate.sh restore nginx          # 从同级 nginx_migrate.tar.gz 还原
#
# 关键原理（来自 php.sh / nginx.sh 逆向）：
#   - 面板靠"文件探测"识别已装软件：php 看 /www/server/php/<V>/bin/php + version.pl
#                                   nginx 看 /www/server/nginx/sbin/nginx + version.pl + panel/data/nginx_md5.pl
#   - PHP 的 openssl111/curl_2/icu/onig/libsodium/libzip 等依赖在 /usr/local，需用 ldd 一并带走
#   - nginx 的 openssl/pcre 已静态编入二进制；仅 jemalloc/luajit/lua-cjson 动态链接需带走
#   - nginx 单一目录不分版本，且 conf 须与二进制同源（故还原时用 B 自带 conf，旧 conf 备份到 /www/backup）
#
# 路径约定：迁移包与脚本同级目录；临时目录用同级隐藏目录，跑完即删
# 详细说明见同目录 README.md
# ============================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "用法: $0 <package|restore> <php|nginx> [php版本...]"
  echo ""
  echo "  package php [版本...]   B端执行：打包 PHP（不传版本=自动扫描全部已装）"
  echo "  package nginx           B端执行：打包 nginx"
  echo "  restore php             A端执行：从同级 php_migrate.tar.gz 还原"
  echo "  restore nginx           A端执行：从同级 nginx_migrate.tar.gz 还原"
  exit 1
}

# 可选：让面板重新探测（默认不自动重启，避免通过宝塔终端 WebSSH 执行时
# 重启面板导致终端断开、脚本中断）。设置环境变量 BT_MIGRATE_RESTART=1 可开启，
# 会用 setsid 后台 detached 执行，即便终端随后被断开也不影响迁移结果。
maybe_restart_panel() {
  if [ "${BT_MIGRATE_RESTART:-0}" = "1" ]; then
    echo "==> 已安排后台重启宝塔面板（detached，不阻塞本脚本）..."
    setsid bash -c 'sleep 2; bt restart >/dev/null 2>&1 || service bt restart >/dev/null 2>&1 || /etc/init.d/bt restart >/dev/null 2>&1' </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  else
    echo "==> 迁移已完成。请在浏览器刷新/重新打开宝塔面板以查看新软件"
    echo "    （面板按文件探测识别，无需重启即可生效；如需强制刷新缓存可在新终端执行: bt restart）"
  fi
}

[ $# -lt 2 ] && usage
ACTION="$1"; SOFT="$2"; shift 2
case "$ACTION" in
  package|restore) ;;
  *) echo "错误：未知子命令 '$ACTION'"; usage ;;
esac
case "$SOFT" in
  php|nginx) ;;
  *) echo "错误：软件类型必须是 php 或 nginx"; usage ;;
esac

# ===================== PHP =====================
php_package() {
  local PHP_BASE=/www/server/php
  normalize() { local v="$1"; v="${v//./}"; echo "$v"; }

  local VERSIONS=()
  if [ $# -eq 0 ]; then
    echo "==> 未指定版本，自动扫描 $PHP_BASE 下已安装 PHP ..."
    for d in "$PHP_BASE"/*; do
      [ -d "$d" ] || continue
      [ -x "$d/bin/php" ] && VERSIONS+=("$(basename "$d")")
    done
  else
    for arg in "$@"; do VERSIONS+=("$(normalize "$arg")"); done
  fi

  [ ${#VERSIONS[@]} -eq 0 ] && { echo "未找到任何可迁移的 PHP 版本，退出"; exit 1; }
  for V in "${VERSIONS[@]}"; do
    if [ ! -x "$PHP_BASE/$V/bin/php" ]; then
      echo "错误：/www/server/php/$V/bin/php 不存在，请检查版本号"; exit 1
    fi
  done
  echo "==> 将要迁移的版本：${VERSIONS[*]}"

  local WORK="$SCRIPT_DIR/.php_migrate_build"
  rm -rf "$WORK"; mkdir -p "$WORK"

  # 1) php 主目录（支持多版本）
  tar czf "$WORK/php_dir.tar.gz" -C "$PHP_BASE" "${VERSIONS[@]}"

  # 2) 面板识别用的 md5 记录
  > "$WORK/md5_args"
  for V in "${VERSIONS[@]}"; do
    [ -f /www/server/panel/data/php${V}_md5.pl ] && echo "php${V}_md5.pl" >> "$WORK/md5_args"
    [ -f /www/server/panel/data/php-fpm${V}_md5.pl ] && echo "php-fpm${V}_md5.pl" >> "$WORK/md5_args"
  done
  if [ -s "$WORK/md5_args" ]; then
    tar czf "$WORK/php_panel.tar.gz" -C /www/server/panel/data -T "$WORK/md5_args"
  else
    tar czf "$WORK/php_panel.tar.gz" -T /dev/null
  fi

  # 3) 动态依赖库（ldd 收集 /usr/local 下实际链接的库，过滤存在项后 -T 读取）
  > "$WORK/libs_args"
  for V in "${VERSIONS[@]}"; do
    { ldd "$PHP_BASE/$V/bin/php"; ldd "$PHP_BASE/$V/sbin/php-fpm"; } 2>/dev/null \
      | grep -oE '/usr/local/[^ ]+' | sed 's#^/##'
  done | sort -u > "$WORK/libs_args"
  > "$WORK/libs_args.filtered"
  while read -r p; do [ -e "/$p" ] && echo "$p"; done < "$WORK/libs_args" > "$WORK/libs_args.filtered"
  if [ -s "$WORK/libs_args.filtered" ]; then
    tar czf "$WORK/php_libs.tar.gz" -C / --ignore-failed-read -T "$WORK/libs_args.filtered"
  else
    tar czf "$WORK/php_libs.tar.gz" -T /dev/null
  fi

  # 4) ld.so 配置（宝塔本地库配置均以 z 开头）
  tar czf "$WORK/php_ldso.tar.gz" -C / etc/ld.so.conf.d/z*.conf 2>/dev/null || tar czf "$WORK/php_ldso.tar.gz" -T /dev/null

  # 5) 服务文件 + nginx conf（保留绝对路径）
  > "$WORK/svc_args"
  for V in "${VERSIONS[@]}"; do
    [ -f /etc/init.d/php-fpm-$V ] && echo "/etc/init.d/php-fpm-$V" >> "$WORK/svc_args"
    [ -f /usr/lib/systemd/system/php-fpm-$V.service ] && echo "/usr/lib/systemd/system/php-fpm-$V.service" >> "$WORK/svc_args"
    [ -f /lib/systemd/system/php-fpm-$V.service ] && echo "/lib/systemd/system/php-fpm-$V.service" >> "$WORK/svc_args"
    [ -f /www/server/nginx/conf/enable-php-$V.conf ] && echo "/www/server/nginx/conf/enable-php-$V.conf" >> "$WORK/svc_args"
  done
  if [ -s "$WORK/svc_args" ]; then
    tar czf "$WORK/svc.tar.gz" -C / -T "$WORK/svc_args"
  else
    tar czf "$WORK/svc.tar.gz" -T /dev/null
  fi

  echo "${VERSIONS[*]}" > "$WORK/php_versions.list"
  cd "$WORK"
  tar czf "$SCRIPT_DIR/php_migrate.tar.gz" php_dir.tar.gz php_panel.tar.gz php_libs.tar.gz php_ldso.tar.gz svc.tar.gz php_versions.list
  rm -rf "$WORK"
  echo "完成！迁移包: $SCRIPT_DIR/php_migrate.tar.gz"
  echo "包含版本: ${VERSIONS[*]}"
  echo "把它放到 A 服务器 bt_migrate.sh 的同级目录，再执行: ./bt_migrate.sh restore php"
}

php_restore() {
  local PHP_BASE=/www/server/php
  local ARCHIVE="$SCRIPT_DIR/php_migrate.tar.gz"
  [ -f "$ARCHIVE" ] || { echo "未找到 $ARCHIVE，退出"; exit 1; }

  local WORK="$SCRIPT_DIR/.php_migrate_extract"
  rm -rf "$WORK"; mkdir -p "$WORK"
  tar xzf "$ARCHIVE" -C "$WORK"
  cd "$WORK"

  local VERSIONS=($(cat php_versions.list))
  echo "==> 将还原版本：${VERSIONS[*]}"

  # 0) 备份 A 上已有版本的 etc 配置（php.ini / php-fpm.conf 等），还原后恢复，避免被 B 的配置覆盖
  mkdir -p /www/backup
  local ETC_BAK="/www/backup/php_etc.a.bak_$(date +%s)"
  mkdir -p "$ETC_BAK"
  local HAD_ETC=0
  for V in "${VERSIONS[@]}"; do
    if [ -d "$PHP_BASE/$V/etc" ]; then
      cp -a "$PHP_BASE/$V/etc" "$ETC_BAK/$V"
      HAD_ETC=1
    fi
  done
  if [ "$HAD_ETC" -eq 1 ]; then
    echo "==> 已备份 A 原有 PHP 配置到 $ETC_BAK"
  fi

  tar xzf php_dir.tar.gz   -C "$PHP_BASE/"

  # 0.5) 恢复 A 原有 PHP 配置（保持原有配置优先；A 没装过该版本时用 B 自带的）
  for V in "${VERSIONS[@]}"; do
    if [ -d "$ETC_BAK/$V" ]; then
      cp -a "$ETC_BAK/$V/." "$PHP_BASE/$V/etc/"
      echo "==> 已恢复 A 原有 php$V 配置（etc/）"
    fi
  done

  tar xzf php_panel.tar.gz -C /www/server/panel/data/ 2>/dev/null || true
  tar xzf php_libs.tar.gz  -C / 2>/dev/null || true
  tar xzf php_ldso.tar.gz  -C / 2>/dev/null || true
  tar xzf svc.tar.gz       -C / 2>/dev/null || true
  ldconfig

  local RESTART_BT=0
  for V in "${VERSIONS[@]}"; do
    echo "==> 处理 php$V"
    if [ -f /usr/lib/systemd/system/php-fpm-$V.service ] || [ -f /lib/systemd/system/php-fpm-$V.service ]; then
      systemctl daemon-reload
      systemctl enable php-fpm-$V.service
      if systemctl restart php-fpm-$V.service 2>/dev/null; then RESTART_BT=1; else echo "  注意：php-fpm-$V 启动失败，可能是 A 原配置与新版不兼容，请检查 $PHP_BASE/$V/etc/"; fi
    elif [ -f /etc/init.d/php-fpm-$V ]; then
      chkconfig --add php-fpm-$V 2>/dev/null || update-rc.d php-fpm-$V defaults 2>/dev/null || true
      if /etc/init.d/php-fpm-$V restart 2>/dev/null; then RESTART_BT=1; else echo "  注意：php-fpm-$V 启动失败，可能是 A 原配置与新版不兼容，请检查 $PHP_BASE/$V/etc/"; fi
    else
      echo "  警告：未找到 php-fpm-$V 服务文件，目录已就位但未启动"
    fi
    "$PHP_BASE/$V/bin/php" -v
    ls /tmp/php-cgi-$V.sock >/dev/null 2>&1 && echo "  php-fpm-$V sock 就绪" || echo "  注意：php-fpm-$V sock 未生成"
  done

  if [ "$RESTART_BT" -eq 1 ]; then
    maybe_restart_panel
  fi
  echo "全部完成。"
  rm -rf "$WORK"
}

# ===================== nginx =====================
nginx_package() {
  local ROOT_PATH NGX
  if [ -s /var/bt_setupPath.conf ]; then
    ROOT_PATH="$(cat /var/bt_setupPath.conf)"
  else
    ROOT_PATH=/www
  fi
  NGX="$ROOT_PATH/server/nginx"

  [ -x "$NGX/sbin/nginx" ] || { echo "错误：$NGX/sbin/nginx 不存在，B 上似乎没装 nginx"; exit 1; }

  echo "==> 将要迁移 nginx: $NGX"
  echo "    版本: $(cat "$NGX/version.pl" 2>/dev/null || echo '未知')"

  local WORK="$SCRIPT_DIR/.nginx_migrate_build"
  rm -rf "$WORK"; mkdir -p "$WORK"

  # 1) nginx 主目录（排除编译临时 src 目录以减小体积）
  tar czf "$WORK/nginx_dir.tar.gz" -C "$ROOT_PATH" --exclude='server/nginx/src' server/nginx

  # 2) 面板识别用的 md5 记录
  if [ -f /www/server/panel/data/nginx_md5.pl ]; then
    tar czf "$WORK/nginx_panel.tar.gz" -C /www/server/panel/data nginx_md5.pl
  else
    tar czf "$WORK/nginx_panel.tar.gz" -T /dev/null
  fi

  # 3) 动态依赖库（ldd 自动收集 nginx 实际链接的 /usr/local 库）
  > "$WORK/libs_args"
  ldd "$NGX/sbin/nginx" 2>/dev/null | grep -oE '/usr/local/[^ ]+' | sed 's#^/##' | sort -u >> "$WORK/libs_args"
  # lua 脚本库目录（lua 模块运行期可能需要，存在才收集；头文件运行期不需要故不收集）
  [ -d /usr/local/lib/lua ] && echo "usr/local/lib/lua" >> "$WORK/libs_args"
  > "$WORK/libs_args.filtered"
  while read -r p; do [ -e "/$p" ] && echo "$p"; done < "$WORK/libs_args" > "$WORK/libs_args.filtered"
  if [ -s "$WORK/libs_args.filtered" ]; then
    tar czf "$WORK/nginx_libs.tar.gz" -C / --ignore-failed-read -T "$WORK/libs_args.filtered"
  else
    tar czf "$WORK/nginx_libs.tar.gz" -T /dev/null
  fi

  # 4) ld.so 配置
  tar czf "$WORK/nginx_ldso.tar.gz" -C / etc/ld.so.conf.d/z*.conf 2>/dev/null || tar czf "$WORK/nginx_ldso.tar.gz" -T /dev/null

  # 5) 服务文件
  > "$WORK/svc_args"
  [ -f /etc/init.d/nginx ] && echo "/etc/init.d/nginx" >> "$WORK/svc_args"
  [ -f /usr/lib/systemd/system/nginx.service ] && echo "/usr/lib/systemd/system/nginx.service" >> "$WORK/svc_args"
  [ -f /lib/systemd/system/nginx.service ] && echo "/lib/systemd/system/nginx.service" >> "$WORK/svc_args"
  if [ -s "$WORK/svc_args" ]; then
    tar czf "$WORK/svc.tar.gz" -C / -T "$WORK/svc_args"
  else
    tar czf "$WORK/svc.tar.gz" -T /dev/null
  fi

  cd "$WORK"
  tar czf "$SCRIPT_DIR/nginx_migrate.tar.gz" nginx_dir.tar.gz nginx_panel.tar.gz nginx_libs.tar.gz nginx_ldso.tar.gz svc.tar.gz
  rm -rf "$WORK"
  echo "完成！迁移包: $SCRIPT_DIR/nginx_migrate.tar.gz"
  echo "包含: nginx 主目录 + 面板md5 + /usr/local依赖(jemalloc/luajit/cjson) + ld.so配置 + 服务文件"
  echo "把它放到 A 服务器 bt_migrate.sh 的同级目录，再执行: ./bt_migrate.sh restore nginx"
}

nginx_restore() {
  local ROOT_PATH NGX
  local ARCHIVE="$SCRIPT_DIR/nginx_migrate.tar.gz"
  [ -f "$ARCHIVE" ] || { echo "未找到 $ARCHIVE，退出"; exit 1; }

  if [ -s /var/bt_setupPath.conf ]; then
    ROOT_PATH="$(cat /var/bt_setupPath.conf)"
  else
    ROOT_PATH=/www
  fi
  NGX="$ROOT_PATH/server/nginx"

  local WORK="$SCRIPT_DIR/.nginx_migrate_extract"
  rm -rf "$WORK"; mkdir -p "$WORK"
  tar xzf "$ARCHIVE" -C "$WORK"
  cd "$WORK"

  # 1) 先停 A 现有 nginx（升级必然短暂下线）
  echo "==> 停止 A 现有 nginx ..."
  /etc/init.d/nginx stop 2>/dev/null || systemctl stop nginx.service 2>/dev/null || service nginx stop 2>/dev/null || true
  pkill -9 nginx 2>/dev/null || true
  sleep 1

  # 2) 备份 A 的原 conf 整目录（保持原有配置优先；校验失败才回退 B 的 conf）
  mkdir -p /www/backup
  local A_CONF_BAK=""
  if [ -d "$NGX/conf" ]; then
    A_CONF_BAK="/www/backup/nginx_conf.a.bak_$(date +%s)"
    cp -a "$NGX/conf" "$A_CONF_BAK"
    echo "==> 已备份 A 的原 conf 目录到 $A_CONF_BAK"
  fi

  # 2.5) 备份旧二进制便于回滚
  [ -f "$NGX/sbin/nginx" ] && cp -a "$NGX/sbin/nginx" "/www/backup/nginxBak_$(date +%s)" 2>/dev/null || true

  # 3) 还原 nginx 主目录（B 的 conf 与 B 二进制同源，先落地）
  tar xzf nginx_dir.tar.gz -C "$ROOT_PATH/"

  # 3.5) 暂存 B 的 conf（供 A 配置校验失败时自动回退）
  local B_CONF_BAK="$WORK/nginx_conf.b.bak"
  cp -a "$NGX/conf" "$B_CONF_BAK"

  # 4) 恢复 A 的原有配置（保持原有配置优先；A 没装过 nginx 时保留 B 的）
  if [ -n "$A_CONF_BAK" ]; then
    cp -a "$A_CONF_BAK/." "$NGX/conf/"
    echo "==> 已恢复 A 的原有 conf（保持原有配置）"
  fi

  # 5) 还原面板 md5、依赖库、ld.so、服务文件
  tar xzf nginx_panel.tar.gz -C /www/server/panel/data/ 2>/dev/null || true
  tar xzf nginx_libs.tar.gz  -C / 2>/dev/null || true
  tar xzf nginx_ldso.tar.gz  -C / 2>/dev/null || true
  tar xzf svc.tar.gz         -C / 2>/dev/null || true
  ldconfig

  # 6) 命令行软链（指向新版本）
  ln -sf "$NGX/sbin/nginx" /usr/bin/nginx

  # 7) 启动前校验：lua 兼容兜底 + nginx -t，失败自动回退 B 的 conf 保证可启动
  echo "==> 校验配置 ..."
  if ! "$NGX/sbin/nginx" -V 2>&1 | grep -qi 'lua'; then
    echo "    检测到 nginx 未编译 lua 模块，自动注释 conf 中的 lua 指令（如需 lua 功能请先在 B 重新编译带 lua 的 nginx）"
    sed -i '/lua_package_path/s/^/#/' "$NGX/conf/nginx.conf"
    sed -i '/include.*luawaf.conf/s/^/#/' "$NGX/conf/nginx.conf"
  fi
  local T_OUT T_FAIL=0
  T_OUT=$("$NGX/sbin/nginx" -t 2>&1) || T_FAIL=1
  echo "$T_OUT" | tail -8
  if [ "$T_FAIL" -eq 1 ] && [ -n "$A_CONF_BAK" ]; then
    echo "  A 的原配置与新二进制不兼容，自动回退为 B 自带 conf（保证 nginx 可启动）"
    rm -rf "$NGX/conf"
    cp -a "$B_CONF_BAK" "$NGX/conf"
    "$NGX/sbin/nginx" -t 2>&1 | tail -4 || true
    echo "  A 原配置备份在 $A_CONF_BAK，请手动合并差异后覆盖 $NGX/conf/nginx.conf"
  fi

  # 8) 启动
  echo "==> 启动 nginx ..."
  if [ -f /usr/lib/systemd/system/nginx.service ] || [ -f /lib/systemd/system/nginx.service ]; then
    systemctl daemon-reload
    systemctl enable nginx.service
    systemctl restart nginx.service
  else
    chkconfig --add nginx 2>/dev/null || update-rc.d nginx defaults 2>/dev/null || true
    /etc/init.d/nginx restart
  fi

  # 9) 让面板重新探测（可选：默认不自动重启，避免宝塔终端执行时终端断开）
  maybe_restart_panel

  echo "==> 完成。nginx 当前版本："
  "$NGX/sbin/nginx" -v
  rm -rf "$WORK"
}

# ===================== 分发 =====================
case "$SOFT" in
  php)
    [ "$ACTION" = "package" ] && php_package "$@"
    [ "$ACTION" = "restore" ] && php_restore
    ;;
  nginx)
    [ "$ACTION" = "package" ] && nginx_package
    [ "$ACTION" = "restore" ] && nginx_restore
    ;;
esac
