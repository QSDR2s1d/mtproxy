#!/bin/bash

# 基础路径配置
WORKDIR="/usr/local/mtproxy_manager"
PID_FILE=$WORKDIR/pid/pid_mtproxy
CONFIG_PATH=$WORKDIR/config
SERVICE_FILE="/etc/systemd/system/mtproxy.service"

# 程序下载地址
URL_MTG="https://github.com/ellermister/mtproxy/releases/download/v0.04/$(uname -m)-mtg"
URL_MTPROTO="https://github.com/ellermister/mtproxy/releases/download/v0.04/mtproto-proxy"
URL_PY_MTPROTOPROXY="https://github.com/alexbers/mtprotoproxy/archive/refs/heads/master.zip"

BINARY_MTG_PATH=$WORKDIR/bin/mtg
BINARY_MTPROTO_PROXY_PATH=$WORKDIR/bin/mtproto-proxy
BINARY_PY_MTPROTOPROXY_PATH=$WORKDIR/bin/mtprotoproxy.py

SYSTEM_PYTHON=$(which python3 || which python)
PUBLIC_IP=""

# ----------------- 工具函数 -----------------

print_info() { echo -e "[\033[32mINFO\033[0m] $1"; }
print_warn() { echo -e "[\033[33mWARN\033[0m] $1"; }
print_err()  { echo -e "[\033[31mERROR\033[0m] $1"; exit 1; }

check_root() {
    [[ $EUID -ne 0 ]] && print_err "请使用 root 用户运行此脚本: sudo bash $0"
}

get_ip_public() {
    local ip=""
    # 尝试多个源获取 IP，优先 ipv4/ipv6 自动识别
    ip=$(curl -s --max-time 5 https://api.ip.sb/ip -A Mozilla 2>/dev/null)
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 5 https://ipinfo.io/ip -A Mozilla 2>/dev/null)
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 5 https://icanhazip.com -A Mozilla 2>/dev/null)
    
    # IPv6 格式化处理
    if [[ "$ip" == *":"* ]]; then
        ip=$(echo $ip | tr -d ' \n')
    fi
    
    [[ -z "$ip" ]] && print_err "无法获取公网 IP，请检查网络连接。"
    echo "$ip"
}

get_architecture() {
    case $(uname -m) in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "unsupported" ;;
    esac
}

# ----------------- 系统设置 -----------------

sync_time() {
    print_info "正在同步系统时间..."
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true
    elif command -v ntpdate &>/dev/null; then
        ntpdate -u time.google.com
    else
        print_warn "未找到时间同步工具，跳过同步。建议手动确保时间准确。"
    fi
}

install_deps() {
    print_info "安装依赖..."
    if [[ -f /etc/redhat-release ]]; then
        yum update -y && yum install -y iproute curl wget net-tools unzip tar
    elif grep -Eqi "debian|ubuntu" /etc/issue; then
        apt update && apt install -y iproute2 curl wget net-tools unzip tar
    fi
    
    # 确保存放目录存在
    mkdir -p "$WORKDIR/bin" "$WORKDIR/pid"
}

# ----------------- 安装与配置 -----------------

do_install_proxy() {
    local provider=$1
    if [[ "$provider" == "mtg" ]]; then
        print_info "正在下载 mtg (GitHub Release)..."
        # 移除 -q，添加 --show-progress
        wget "$URL_MTG" -O "$BINARY_MTG_PATH" --show-progress
        chmod +x "$BINARY_MTG_PATH"
        [[ ! -f "$BINARY_MTG_PATH" ]] && print_err "mtg 下载失败，请检查服务器连接 GitHub 是否通畅"

    elif [[ "$provider" == "python-mtprotoproxy" ]]; then
        print_info "正在下载 python-mtprotoproxy..."
        wget "$URL_PY_MTPROTOPROXY" -O mtprotoproxy.zip --show-progress
        unzip -q mtprotoproxy.zip
        cp -rf mtprotoproxy-master/*.py mtprotoproxy-master/pyaes "$WORKDIR/bin/"
        rm -rf mtprotoproxy-master mtprotoproxy.zip
    
    elif [[ "$provider" == "official-MTProxy" ]]; then
        print_info "正在下载 official-MTProxy..."
        wget "$URL_MTPROTO" -O "$BINARY_MTPROTO_PROXY_PATH" --show-progress
        chmod +x "$BINARY_MTPROTO_PROXY_PATH"
    fi
}

gen_rand_hex() {
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-$1
}

str_to_hex() {
    printf "$1" | od -An -tx1 | tr -d ' \n'
}

configure() {
    local arch=$(get_architecture)
    local provider_name=""
    
    echo "========================================="
    echo "       MTProxy 极简安装向导"
    echo "========================================="
    
    # 选择版本
    if [[ "$arch" == "amd64" ]]; then
        echo "1. mtg (Go语言版 - 推荐，性能好)"
        echo "2. python-mtprotoproxy (Python版 - 兼容性好)"
        echo "3. Official MTProxy (C语言版 - 仅x86)"
        read -p "请选择版本 [默认1]: " sel
        case "$sel" in
            2) provider_name="python-mtprotoproxy" ;;
            3) provider_name="official-MTProxy" ;;
            *) provider_name="mtg" ;;
        esac
    else
        echo "1. mtg (Go语言版 - 推荐)"
        echo "2. python-mtprotoproxy (Python版)"
        read -p "请选择版本 [默认1]: " sel
        case "$sel" in
            2) provider_name="python-mtprotoproxy" ;;
            *) provider_name="mtg" ;;
        esac
    fi

    echo "已选择核心: $provider_name"

    # 端口配置
    read -p "请输入端口 [默认443]: " port
    [[ -z "$port" ]] && port=443

    # 域名配置 (TLS)
    read -p "请输入伪装域名 [默认 azure.microsoft.com]: " domain
    [[ -z "$domain" ]] && domain="azure.microsoft.com"

    # 生成密钥
    local secret=$(gen_rand_hex 32)
    local adtag="" 
    
    # 写入配置
    cat > "$CONFIG_PATH" <<EOF
provider_name="$provider_name"
port=$port
domain="$domain"
secret="$secret"
adtag="$adtag"
EOF
    
    do_install_proxy "$provider_name"
    create_systemd_service
}

# ----------------- 运行管理 (Systemd) -----------------

create_systemd_service() {
    source "$CONFIG_PATH"
    
    # 构建启动命令
    local exec_cmd=""
    
    # IP 处理
    local ip_flag="-4"
    local bind_ip="0.0.0.0"
    local prefer_ip="ipv4"
    local pub_ip_safe="$PUBLIC_IP"

    if [[ "$PUBLIC_IP" == *":"* ]]; then
        ip_flag="-6"
        bind_ip="[::]"
        prefer_ip="ipv6"
        if [[ "$PUBLIC_IP" != \[* ]]; then pub_ip_safe="[$PUBLIC_IP]"; fi
    fi

    if [[ "$provider_name" == "mtg" ]]; then
        local domain_hex=$(str_to_hex "$domain")
        local client_secret="ee${secret}${domain_hex}"
        # 适配 mtg v1 simple-run
        exec_cmd="$BINARY_MTG_PATH run $client_secret $adtag -b ${bind_ip}:$port --multiplex-per-connection 500 --prefer-ip=${prefer_ip} -t 127.0.0.1:8888 $ip_flag $pub_ip_safe:$port"
    
    elif [[ "$provider_name" == "python-mtprotoproxy" ]]; then
        # 生成 python 配置文件
        cat > "$WORKDIR/bin/config.py" <<EOF
PORT = ${port}
USERS = { "tg":  "${secret}" }
MODES = { "classic": False, "secure": False, "tls": True }
TLS_DOMAIN = "${domain}"
AD_TAG = "${adtag}"
EOF
        sed -i 's/MAX_CONNS_IN_POOL =\s[0-9]\+/MAX_CONNS_IN_POOL = 500/' "$BINARY_PY_MTPROTOPROXY_PATH"
        exec_cmd="$SYSTEM_PYTHON $BINARY_PY_MTPROTOPROXY_PATH $WORKDIR/bin/config.py"
    
    elif [[ "$provider_name" == "official-MTProxy" ]]; then
         # 仅作兼容
         curl -s https://core.telegram.org/getProxyConfig -o "$WORKDIR/proxy-multi.conf"
         curl -s https://core.telegram.org/getProxySecret -o "$WORKDIR/proxy-secret"
         local workers=$(nproc)
         exec_cmd="$BINARY_MTPROTO_PROXY_PATH -u nobody -p 8888 -H $port -S $secret --aes-pwd $WORKDIR/proxy-secret $WORKDIR/proxy-multi.conf -M $workers --domain $domain --ipv6"
    fi

    # 生成 Service 文件
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTProxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORKDIR
ExecStart=$exec_cmd
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mtproxy.service
    print_info "Systemd 服务已创建并设置为开机自启"
}

start_service() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        print_err "未找到配置文件，请先运行安装: bash $0 install"
    fi
    systemctl start mtproxy
    show_info
}

stop_service() {
    systemctl stop mtproxy
    print_info "服务已停止"
}

restart_service() {
    systemctl restart mtproxy
    print_info "服务已重启"
    show_info
}

uninstall() {
    systemctl stop mtproxy
    systemctl disable mtproxy
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    rm -rf "$WORKDIR"
    print_info "MTProxy 已卸载清除"
}

show_info() {
    if [[ ! -f "$CONFIG_PATH" ]]; then return; fi
    source "$CONFIG_PATH"
    
    local domain_hex=$(str_to_hex "$domain")
    local client_secret="ee${secret}${domain_hex}"
    local status=$(systemctl is-active mtproxy)
    local color_status="\033[33m$status\033[0m"
    [[ "$status" == "active" ]] && color_status="\033[32m运行中\033[0m"

    echo "========================================="
    echo -e " 代理状态: $color_status"
    echo -e " 端口: $port"
    echo -e " IP: $PUBLIC_IP"
    echo -e " 密钥(Secret): $client_secret"
    echo -e " 伪装域名: $domain"
    echo "========================================="
    echo -e " TG一键链接: tg://proxy?server=${PUBLIC_IP}&port=${port}&secret=${client_secret}"
    echo "========================================="
}

# ----------------- 入口逻辑 -----------------

check_root
cd $(dirname $0)

action=$1
[[ -z "$action" ]] && action="install"

if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP=$(get_ip_public)
fi

case "$action" in
    install)
        install_deps
        sync_time
        configure
        start_service
        ;;
    start)  start_service ;;
    stop)   stop_service ;;
    restart) restart_service ;;
    uninstall) uninstall ;;
    info)   show_info ;;
    *)
        echo "使用方法: bash $0 {install|start|stop|restart|uninstall|info}"
        ;;
esac