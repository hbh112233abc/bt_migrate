# bt_migrate.sh —— 宝塔软件跨服务器迁移工具

把**有外网服务器（B）** 上已编译安装好的 PHP / nginx 整包，连同运行依赖一起打包，
搬到**无外网服务器（A）** 解包即用，A 的宝塔面板能自动识别迁移过来的软件。

## 适用条件

- 两台服务器**系统版本相同、CPU 架构相同**（如都是 CentOS 7 + x86_64）。
- 两台都装了**同版本宝塔面板**（实测 v9），默认安装路径 `/www`。
- B 能访问外网、可以正常装软件；A 无外网、不想重装编译。
- 迁移前后路径保持一致（B 装哪、A 就还原到哪），脚本默认从 `/www` 读取（`/var/bt_setupPath.conf` 可改根路径）。

## 工作原理（为什么复制目录面板就能识别）

宝塔面板靠**文件探测**而非注册表来识别已装软件（源自 `php.sh` / `nginx.sh` 逆向）：

- **PHP**：探测 `/www/server/php/<版本>/bin/php` 是否存在 + 读取 `version.pl` 显示版本号。
- **nginx**：探测 `/www/server/nginx/sbin/nginx` 存在 + `version.pl` + `/www/server/panel/data/nginx_md5.pl`。

所以只要把目录整包复制过去，面板"软件商店 - 已安装"里就能看到对应软件，无需重装。

依赖库差异（这是迁移最容易翻车的地方，脚本已自动处理）：

| 软件 | 静态编入二进制 | 需一起带走的动态库（在 /usr/local） |
|------|----------------|--------------------------------------|
| PHP  | 无（全部动态） | openssl111 / curl_2 / icu / onig / libsodium / libzip … |
| nginx | openssl、pcre | jemalloc / LuaJIT / lua-cjson |

脚本用 `ldd` 自动收集二进制实际链接的 `/usr/local` 库，并用 `tar -T` 列表方式打包（避免多行路径被拼成假文件名）。

## 使用方法

脚本通过**子命令 + 软件类型**分发：

```bash
# ===== B 端（有外网）：打包 =====
./bt_migrate.sh package php            # 不传版本=自动扫描 /www/server/php 下所有已装 PHP
./bt_migrate.sh package php 82 8.2 74  # 只打包指定版本（82 / 8.2 / 74 混写均可）
./bt_migrate.sh package nginx          # nginx 单一目录，无需版本参数

# ===== A 端（无外网）：还原 =====
./bt_migrate.sh restore php            # 从同级 php_migrate.tar.gz 还原
./bt_migrate.sh restore nginx          # 从同级 nginx_migrate.tar.gz 还原
```

### 完整迁移三步

1. **B 端打包**：把 `bt_migrate.sh` 放到某目录（如 `/root/migrate/`）执行 `package`，
   生成的迁移包 `php_migrate.tar.gz` / `nginx_migrate.tar.gz` 默认输出到**脚本同级目录**。
2. **传输**：把脚本和对应的迁移包一起弄到 A 的同级目录（U 盘 / 移动硬盘 / 内网能通则 `scp`）。
3. **A 端还原**：在 A 上执行 `restore`，脚本自动解包、刷 `ldconfig`、注册并启动服务。
   还原完成后软件即可运行，**无需重启面板**——在浏览器刷新一下宝塔面板页面，面板会按文件探测重新识别到新软件。

> 路径约定：迁移包与脚本同级目录；中间临时目录用同级隐藏目录（`.php_migrate_build` 等），跑完即删，**不会删除源包**。

## 迁移清单

### PHP（分版本目录 `/www/server/php/<V>`）
- PHP 主目录：含 `bin/php`、`sbin/php-fpm`、`etc/`、`lib/`（扩展 .so）、`version.pl`
- 面板识别记录：`/www/server/panel/data/php<V>_md5.pl`、`php-fpm<V>_md5.pl`
- 动态依赖库：`/usr/local` 下 PHP 实际链接的库（`ldd` 自动收集）
- ld.so 配置：`/etc/ld.so.conf.d/z*.conf`
- 服务文件：`/etc/init.d/php-fpm-<V>` 或 `*/systemd/system/php-fpm-<V>.service`
- nginx 配置（可选）：`/www/server/nginx/conf/enable-php-<V>.conf`

### nginx（单一目录 `/www/server/nginx`，不分版本）
- nginx 主目录（排除编译临时 `src/` 以减小体积）
- 面板识别记录：`/www/server/panel/data/nginx_md5.pl`
- 动态依赖库：jemalloc / LuaJIT / lua-cjson 等（`ldd` 自动收集）
- ld.so 配置：`/etc/ld.so.conf.d/z*.conf`
- 服务文件：`/etc/init.d/nginx` 或 `*/systemd/system/nginx.service`

## 注意事项 / 已知坑

1. **nginx 的 conf 必须与二进制同源**：A 原 nginx 的 `conf/nginx.conf` 不会被保留，
   还原时改用 B 自带的 `nginx.conf`（与 B 二进制编译特性一致）。
   A 原 conf 会备份到 `/www/backup/nginx.conf.a.bak_<时间戳>`，有自定义 server 块可参考手动合并。
   旧二进制同样备份到 `/www/backup/nginxBak_<时间戳>` 便于回滚。

2. **lua 模块兼容**：若 B 编译 nginx 时未带 lua 模块、而 A 原配置里有 `lua_package_path` 等指令，
   还原脚本会在启动前自动检测并注释掉这些 lua 指令，保证 nginx 能起来。
   但此时 lua 功能（如某些 WAF）在 A 上是缺失的——如需完整功能，请先在 B 重新编译带 lua 的 nginx 再迁移。

3. **依赖库缺失兜底**：还原后若 php-fpm / nginx 启动报 `libxxx.so not found`，
   说明 A 缺对应系统库。因 A 无外网，需从 B 用 `yumdownloader`/`apt-get download` 把 rpm/deb 包下载后拷到 A 安装。

4. **www 用户**：php-fpm 默认以 `www` 用户运行，A 上需存在该用户（宝塔默认已创建）。

5. **调用方式**：脚本靠 `BASH_SOURCE` 定位自身目录，请用 `./bt_migrate.sh` 或 `bash bt_migrate.sh` 调用，
   不要用 `source` 或管道喂给 bash（会取不到真实路径）。

6. **关于"重启面板"**：`restore` **默认不会重启宝塔面板**。原因：若你是在宝塔面板自带的
   终端（WebSSH）里执行脚本，`bt restart` 会连同终端一起断开，导致脚本后续步骤（清理临时目录、
   打印完成信息）丢失。而面板是"按文件探测"识别软件的，文件就位后只需在浏览器**刷新面板页面**
   即可看到新软件，无需重启。
   - 若你是在**独立 SSH 终端**执行、想顺手刷新面板缓存，可设置环境变量开启自动重启：
     `BT_MIGRATE_RESTART=1 ./bt_migrate.sh restore php`
     该方式用 `setsid` 后台 detached 执行 `bt restart`，即便终端随后被断开也不影响迁移结果。
   - 任何时候你也可以手动在**新终端**执行 `bt restart` 强制刷新。

## 文件清单

```
bt_migrate.sh    # 总控脚本（package / restore 子命令，php / nginx 通用）
README.md        # 本说明
```
