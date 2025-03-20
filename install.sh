#!/bin/bash

# 全局配置
# export DOWNLOAD_URL="https://mirror.nju.edu.cn/docker-ce"
MIRROR_SOURCES=(
    "https://goppx.com/"
)
ORIGIN_URL="https://github.com/MaiM-with-u/MaiBot.git"
STABLE_BRANCH="main"
DEVELOPMENT_BRANCH="main-fix"
CLONE_DIR="MaiBot"
PACKAGES="ca-certificates curl gnupg jq git"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 智能权限提升
smart_sudo() {
    if [ -w "$1" ]; then
        "${@:2}"
    else
        sudo "${@:2}"
    fi
}


# 错误处理函数
error_exit() {
    echo -e "${RED}[错误] $1${NC}" >&2
    exit 1
}

# 安装基础依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装系统依赖...${NC}"

    if command -v apt-get >/dev/null; then
        smart_sudo /etc/apt apt-get update || error_exit "APT 更新失败"
        smart_sudo /usr apt-get install -y $PACKAGES || error_exit "APT 安装失败"
    elif command -v dnf >/dev/null; then
        smart_sudo /etc/dnf dnf install -y $PACKAGES || error_exit "DNF 安装失败"
    elif command -v yum >/dev/null; then
        smart_sudo /etc/yum yum install -y $PACKAGES || error_exit "YUM 安装失败"
    elif command -v pacman >/dev/null; then
        smart_sudo /etc/pacman pacman -Sy --noconfirm $PACKAGES || error_exit "Pacman 安装失败"
    else
        error_exit "不支持的包管理器"
    fi

    echo -e "${GREEN}依赖安装成功${NC}"
}

# 在全局配置部分添加
PYTHON_EXE="python3"

# 新增函数：检查Python版本并安装需要的版本
check_python_version() {
    echo -e "${YELLOW}检查 Python 版本...${NC}"
    
    # 获取当前Python版本
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}未找到 python3，需要安装 Python 3.12${NC}"
        install_python3_12
        PYTHON_EXE="python3.12"
        return
    fi

    local python_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    local major=$(echo $python_version | cut -d. -f1)
    local minor=$(echo $python_version | cut -d. -f2)

    if [[ $major -lt 3 || ($major -eq 3 && $minor -lt 9) ]]; then
        echo -e "${RED}当前 Python 版本 ($python_version) 低于 3.9，需要安装 Python 3.12${NC}"
        install_python3_12
        PYTHON_EXE="python3.12"
    else
        echo -e "${GREEN}正在验证安装venv${NC}"
        sudo apt-get install -y python3-venv
        echo -e "${GREEN}当前 Python 版本 ($python_version) 满足要求${NC}"
    fi
}

# 新增函数：安装Python3.12
install_python3_12() {
    echo -e "${YELLOW}开始安装 Python 3.12...${NC}"
    
    # 根据不同发行版安装
    if command -v apt-get &>/dev/null; then
        smart_sudo /etc/apt apt-get install -y software-properties-common
        smart_sudo /etc/apt add-apt-repository -y ppa:deadsnakes/ppa
        smart_sudo /etc/apt apt-get update
        smart_sudo /usr apt-get install -y python3.12 python3.12-venv
    elif command -v dnf &>/dev/null; then
        smart_sudo /etc/dnf dnf install -y python3.12
    elif command -v yum &>/dev/null; then
        smart_sudo /etc/yum yum install -y https://repo.ius.io/ius-release-el$(rpm -E %{rhel}).rpm
        smart_sudo /usr yum install -y python3.12
    elif command -v pacman &>/dev/null; then
        smart_sudo /etc/pacman pacman -Sy python
    else
        error_exit "不支持的包管理器，无法安装 Python 3.12"
    fi

    # 验证安装
    if ! command -v python3.12 &>/dev/null; then
        error_exit "Python 3.12 安装失败"
    fi
    echo -e "${GREEN}Python 3.12 安装成功${NC}"
}

# 新增函数：创建虚拟环境
create_virtualenv() {
    echo -e "${YELLOW}创建 Python 虚拟环境...${NC}"
    
    # 检查是否已有虚拟环境
    if [ -d ".venv" ]; then
        read -p "发现已存在的虚拟环境，是否重新创建？(y/N): " reinstall
        if [[ $reinstall =~ ^[Yy] ]]; then
            rm -rf .venv
        else
            echo -e "${YELLOW}使用现有虚拟环境${NC}"
            return
        fi
    fi

    # 创建新环境
    $PYTHON_EXE -m venv .venv || error_exit "虚拟环境创建失败"
    
    # 安装依赖
    echo -e "${YELLOW}安装项目依赖...${NC}"
    ./.venv/bin/pip install -r requirements.txt -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple || error_exit "依赖安装失败"
    
    echo -e "${GREEN}虚拟环境准备就绪 (.venv)${NC}"
}

# 权限检查函数
check_docker_group() {
    if ! id -nG "$(whoami)" | grep -qw "docker"; then
        echo -e "${YELLOW}当前用户未加入 docker 用户组，尝试自动添加...${NC}"
        sudo usermod -aG docker "$(whoami)" || {
            echo -e "${RED}错误：需要管理员权限添加用户到 docker 组${NC}"
            echo -e "请手动执行：sudo usermod -aG docker $(whoami) && newgrp docker"
            exit 1
        }
        echo -e "${GREEN}用户已加入 docker 组，请重新登录系统后再次运行本脚本${NC}"
        exit 0
    fi
}



# Docker 安装检查
check_docker() {
    echo -e "${YELLOW}检查 Docker 环境...${NC}"

    if ! command -v docker &>/dev/null; then
        echo -e "Docker 未安装，开始安装..."
        local script_dir=$(dirname "$(realpath "$0")")
        local install_script="$script_dir/docker-install.sh"

        [ ! -f "$install_script" ] && error_exit "未找到 docker-install.sh"
        [ ! -x "$install_script" ] && chmod +x "$install_script"

        sudo "$install_script" --mirror nju || error_exit "Docker 安装失败"
        sleep 2
    fi

    echo -e "${GREEN}Docker 已安装 ($(docker --version | cut -d ' ' -f 3))${NC}"
}

# 配置镜像加速
configure_daemon() {
    # 询问是否配置镜像加速
    echo -e "${YELLOW}是否配置 Docker 镜像加速？(默认: Y) [Y/n]${NC}"
    read -p "请输入选择: " configure_choice
    configure_choice=${configure_choice:-Y}  # 默认值为 Y

    if [[ $configure_choice =~ ^[Nn] ]]; then
        echo -e "${YELLOW}已跳过 Docker 镜像加速配置${NC}"
        return
    fi

    echo -e "${YELLOW}正在配置 Docker 镜像加速...${NC}"
    
    sudo mkdir -p /etc/docker
    local config_file="/etc/docker/daemon.json"
    
    # 备份原配置文件
    if [ -f "$config_file" ]; then
        sudo cp "$config_file" "${config_file}.bak"
        echo -e "${GREEN}已备份原配置: ${config_file}.bak${NC}"
    fi

    # 生成新配置
    sudo tee "$config_file" <<EOF
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ],
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    # 重启 Docker 服务
    echo -e "${YELLOW}正在重启 Docker 服务...${NC}"
    if sudo systemctl restart docker; then
        echo -e "${GREEN}Docker 镜像加速配置成功！${NC}"
    else
        echo -e "${RED}警告：Docker 服务重启失败，请手动检查！${NC}"
    fi
}

# 协议确认函数
check_eula() {
    echo -e "${YELLOW}开始用户协议确认流程...${NC}"
    echo -e "${YELLOW}按 q 键退出阅读...${NC}"
    sleep 3

    # 定义文件处理函数
    process_agreement() {
        local doc_name=$1
        local doc_file=$2
        local confirm_file=$3
        
        # 计算哈希值
        local current_hash=$(md5sum "$doc_file" 2>/dev/null | awk '{print $1}')
        [ -z "$current_hash" ] && error_exit "${doc_file} 文件不存在或无法读取"

        # 判断是否需要确认
        local need_confirm=true
        if [ -f "$confirm_file" ]; then
            local stored_hash=$(cat "$confirm_file")
            [ "$current_hash" == "$stored_hash" ] && need_confirm=false
        fi

        if $need_confirm; then
            # 显示完整协议内容
            echo -e "\n${YELLOW}====== 请仔细阅读完整 ${doc_name} ======${NC}"
            if command -v less &>/dev/null; then
                less -R "$doc_file"
            else
                cat "$doc_file"
                echo -e "\n${YELLOW}（内容结束，请向上滚动查看）${NC}"
                read -p "按回车键继续..."
            fi

            # 确认协议
            while true; do
                read -p "是否同意 ${doc_name}？(Y-同意 / N-不同意): " confirm
                case $confirm in
                    [Yy]* )
                        echo "$current_hash" > "$confirm_file"
                        echo -e "${GREEN}已确认 ${doc_name}${NC}"
                        break
                        ;;
                    [Nn]* )
                        error_exit "必须同意所有协议才能继续使用"
                        ;;
                    * )
                        echo -e "${RED}请输入 Y 或 N${NC}"
                        ;;
                esac
            done
        else
            echo -e "${GREEN}${doc_name} 已通过验证${NC}"
        fi
    }

    # 处理 EULA
    process_agreement "最终用户许可协议" "EULA.md" "eula.confirmed"
    
    # 处理隐私条款
    process_agreement "隐私保护协议" "PRIVACY.md" "privacy.confirmed"

    echo -e "${GREEN}所有协议确认完成！${NC}"
}

# 构建开发版镜像
build_dev_image() {
    echo -e "${YELLOW}开始构建开发版镜像...${NC}"

    # 检查 Dockerfile
    [ ! -f "Dockerfile" ] && error_exit "未找到 Dockerfile"

    # 配置 .dockerignore
    echo -e "${YELLOW}更新 .dockerignore 文件...${NC}"
    cat > .dockerignore <<-'EOF'
.git
__pycache__
.venv
data
logs
raw_info
*.pyc
*.pyo
*.pyd
.DS_Store
mongodb
napcat
EOF
    [ $? -ne 0 ] && error_exit ".dockerignore 文件写入失败"

    # 清理旧镜像
    if docker image inspect maimbot:local &>/dev/null; then
        read -p "发现已存在的本地镜像，是否重新构建？(Y/n): " rebuild
        if [[ $rebuild =~ ^[Nn] ]]; then
            echo -e "${YELLOW}使用现有本地镜像${NC}"
            return
        fi
    fi

    # 修改 Dockerfile 添加镜像源
    echo -e "${YELLOW}正在为 pip 添加清华镜像源...${NC}"
    sed -i 's/^\(RUN pip install --upgrade -r requirements.txt\)$/\1 -i https:\/\/mirrors.tuna.tsinghua.edu.cn\/pypi\/web\/simple/' Dockerfile || error_exit "Dockerfile 修改失败"

    # 开始构建
    echo -e "构建镜像可能需要较长时间，请耐心等待..."
    docker pull nonebot/nb-cli:latest
    if ! docker build -t maimbot:local . ; then
        error_exit "镜像构建失败，请检查 Dockerfile"
    fi

    echo -e "${GREEN}开发版镜像构建完成！${NC}"
}

# 主安装流程
main() {

    sudo chmod +x ./common.sh
    
    # 安装依赖
    install_dependencies

    # 检查Python版本
    check_python_version

    # 检查 Docker
    check_docker
    configure_daemon

    # docker权限检查
    check_docker_group

    # 克隆仓库
    echo -e "${YELLOW}开始克隆仓库...${NC}"
    read -p "选择版本 (1-稳定版 / 2-开发版): " branch_choice
    case $branch_choice in
        1) branch=$STABLE_BRANCH ;;
        2) branch=$DEVELOPMENT_BRANCH ;;
        *) error_exit "无效选择" ;;
    esac

   # 镜像加速选择
    read -p "是否启用 GitHub 镜像加速？(Y/n): " mirror_choice
    if [[ $mirror_choice =~ ^[Nn] ]]; then
        repo_url=$ORIGIN_URL
    else
        selected_mirror=${MIRROR_SOURCES[$RANDOM % ${#MIRROR_SOURCES[@]}]}
        repo_url="${selected_mirror}${ORIGIN_URL}"  # 修正后的关键行
    fi

    git clone -b "$branch" "$repo_url" "$CLONE_DIR" || error_exit "仓库克隆失败"
    cd "$CLONE_DIR" || error_exit "无法进入项目目录"

    # 创建虚拟环境
    create_virtualenv
    
    # 开发版镜像构建
    if [ "$branch" = "$DEVELOPMENT_BRANCH" ]; then
        build_dev_image
    fi

    # 生成配置文件
    echo -e "${YELLOW}生成配置文件...${NC}"
    cp template/bot_config_template.toml bot_config.toml
    cp template.env .env.prod

    # 自动设置 MongoDB 主机地址
    echo -e "${YELLOW}配置数据库连接...${NC}"
    sed -i "s/^MONGODB_HOST=.*/MONGODB_HOST=mongodb/" .env.prod

    # 配置 QQ 机器人
    read -p "请输入机器人 QQ 号: " qq_num
    while [[ ! $qq_num =~ ^[0-9]+$ ]]; do
        read -p "无效输入，请重新输入 QQ 号: " qq_num
    done

    read -p "允许回复的群号（多个用逗号分隔）: " groups
    groups=$(echo "$groups" | tr -d '[:space:]' | sed 's/,/, /g')

    sed -i "s/qq = 123/qq = $qq_num/" bot_config.toml
    sed -i "s/talk_allowed = \[.*\]/talk_allowed = [${groups}]/" bot_config.toml

    # API 配置
    read -p "输入 SiliconFlow API 密钥: " api_key
    sed -i "s/SILICONFLOW_KEY=/SILICONFLOW_KEY=$api_key/" .env.prod

    # 协议确认
    check_eula

    # 生成 docker-compose
    echo -e "${YELLOW}生成容器配置...${NC}"
    local maimbot_image="sengokucola/maimbot:latest"
    [ "$branch" = "$DEVELOPMENT_BRANCH" ] && maimbot_image="maimbot:local"

    cat > docker-compose.yml <<EOF
services:
  napcat:
    image: mlikiowa/napcat-docker:latest
    container_name: napcat
    environment:
      - TZ=Asia/Shanghai
      - NAPCAT_UID=1000
      - NAPCAT_GID=1000
    ports:
      - "6099:6099"
    volumes:
      - napcat_data:/app/.config/QQ
      - napcat_config:/app/napcat/config
      - maimbot_data:/MaiMBot/data
    restart: unless-stopped

  mongodb:
    image: mongo:latest
    container_name: mongodb
    environment:
      - TZ=Asia/Shanghai
    ports:
      - "27017:27017"
    volumes:
      - ./mongodb:/data/db
      - ./mongodb/config:/data/configdb
    restart: unless-stopped

  maimbot:
    image: $maimbot_image
    container_name: maimbot
    environment:
      - TZ=Asia/Shanghai
      - EULA_AGREE=35362b6ea30f12891d46ef545122e84a
      - PRIVACY_AGREE=2402af06e133d2d10d9c6c643fdc9333
    depends_on:
      - mongodb
      - napcat
    volumes:
      - ./bot_config.toml:/MaiMBot/config/bot_config.toml
      - ./.env.prod:/MaiMBot/.env.prod
      - ./elua.confirmed:/MaiMBot/elua.confirmed
      - ./privacy.confirmed:/MaiMBot/privacy.confirmed
      - maimbot_data:/MaiMBot/data
      - napcat_config:/MaiMBot/napcat
    restart: unless-stopped

volumes:
  napcat_data:
  napcat_config:
  maimbot_data:
EOF

    # 启动服务
    echo -e "${GREEN}正在启动容器...${NC}"
    
    docker compose up -d

    echo -e "${GREEN}部署完成！${NC}"
    echo -e "${RED}提示："
    echo -e "${GREEN}修改.env.prod来配置其他api提供商${NC}"
    echo -e "${GREEN}启动webui或修改bot_config.toml进行更多配置${NC}"
    echo -e "访问 http://localhost:6099 进行配置napcat"
    echo -e "执行./common.sh 管理服务${NC}"
}

# 执行主函数
main