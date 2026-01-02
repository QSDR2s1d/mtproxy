# MTProxy 一键安装管理脚本

这是一个全新重构的 MTProxy 代理安装脚本，支持 Telegram 客户端连接。
脚本经过现代化改造，采用 **Systemd** 进行进程管理（自动守护、开机自启），并内置了主流的 **mtg (Go版)**、**Python版** 以及 **官方C语言版** 核心供选择。

默认支持 **Fake TLS** 伪装技术，有效抵抗防火墙检测。

## 主要特性

- **多核心支持**：
  - `mtg` (Go语言版)：**推荐**，性能强劲，轻量级，支持抗重放攻击。
  - `python-mtprotoproxy`：兼容性好，无需编译。
  - `Official MTProxy`：官方C语言版本 (仅限 x86 架构)。
- **Systemd 管理**：原生支持开机自启、进程守护，无需手动配置 crontab 或 rc.local。
- **极简交互**：一键生成密钥、配置端口和伪装域名。
- **状态查看**：一键获取 tg:// 链接和运行状态。

## 安装方式

### 方式一：使用脚本 (推荐)

支持 **CentOS / Debian / Ubuntu** 等主流 Linux 发行版。

下载并运行脚本：

```bash
# 下载脚本 (请确保你有 root 权限)
wget -N --no-check-certificate https://raw.githubusercontent.com/QSDR2s1d/mtproxy/master/mtproxy.sh

# 赋予执行权限
chmod +x mtproxy.sh

# 运行安装
bash mtproxy.sh install
```

安装过程中，你可以选择：
1. **代理核心**：推荐使用 `mtg` (Go版)。
2. **运行端口**：默认 443。
3. **伪装域名**：默认 `azure.microsoft.com` (用于 Fake TLS)。

### 方式二：使用 Docker

如果你不想污染宿主机环境，可以使用 Docker 镜像（支持 Nginx 前置伪装及白名单模式）。

**一键运行 (默认开启 IP 白名单)：**

```bash
docker run -d \
--name mtproxy \
--restart=always \
-e domain="cloudflare.com" \
-e secret="548593a9c0688f4f7d9d57377897d964" \
-e ip_white_list="OFF" \
-p 8080:80 \
-p 8443:443 \
ellermister/mtproxy
```

更多 Docker 配置参数请参考：<https://hub.docker.com/r/ellermister/mtproxy>

## 脚本管理命令

安装完成后，你可以使用以下命令管理服务：

**启动服务**
```bash
bash mtproxy.sh start
```

**停止服务**
```bash
bash mtproxy.sh stop
```

**重启服务** (修改配置后需重启)
```bash
bash mtproxy.sh restart
```

**查看状态 & 获取连接链接**
```bash
bash mtproxy.sh info
```

**卸载脚本及服务**
```bash
bash mtproxy.sh uninstall
```

## 常见问题

**Q: 如何修改端口或密钥？**
A: 修改 `/usr/local/mtproxy_manager/config` 文件，然后运行 `bash mtproxy.sh restart` 重启服务。

**Q: 为什么不需要配置 rc.local 了？**
A: 本脚本自动创建了 `/etc/systemd/system/mtproxy.service` 服务文件，系统启动时会自动拉起代理，进程崩溃也会自动重启，无需人工干预。

**Q: 提示 "Systemd 服务已创建" 但无法连接？**
A: 请检查你的服务器防火墙（Firewall/UFW）以及云服务商的安全组（Security Group），确保你设置的端口（默认443）已放行 TCP/UDP 流量。

## 交流群组

Telegram 群组：<https://t.me/EllerHK>

## 引用项目

- <https://github.com/9seconds/mtg>
- <https://github.com/alexbers/mtprotoproxy>
- <https://github.com/TelegramMessenger/MTProxy>
