#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 全局配置
CLONE_DIR="MaiBot"
STABLE_BRANCH="main"
DEVELOPMENT_BRANCH="main-fix"
COMPOSE_FILE="docker-compose.yml"
REQUIRED_FILES=("bot.py" "Dockerfile" "docker-compose.yml")

# 初始化路径
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PROJECT_DIR="${SCRIPT_DIR}/${CLONE_DIR}"

# 错误处理函数
error_exit() {
    echo -e "${RED}[错误] $1${NC}" >&2
    exit 1
}

# 显示使用说明
usage() {
    echo -e "${YELLOW}用法: $0 [command]"
    echo -e "可用命令:"
    echo -e "  start     - 启动所有服务"
    echo -e "  stop      - 停止所有服务"
    echo -e "  restart   - 重启所有服务"
    echo -e "  status    - 查看服务状态"
    echo -e "  update    - 更新代码/镜像并重启"
    echo -e "  help      - 显示本帮助信息${NC}"
    exit 0
}

# 检查当前目录是否包含必要文件
check_current_dir() {
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$file" ]; then
            return 1
        fi
    done
    echo -e "${GREEN}检测到当前目录已包含项目文件，跳过目录切换${NC}"
    return 0
}

# 进入项目目录
enter_project_dir() {
    # 如果当前目录已包含必要文件则跳过
    check_current_dir && return 0

    echo -e "${YELLOW}正在进入项目目录: ${PROJECT_DIR}${NC}"
    
    if [ ! -d "${PROJECT_DIR}" ]; then
        error_exit "项目目录不存在: ${PROJECT_DIR}"
    fi

    cd "${PROJECT_DIR}" || error_exit "无法进入项目目录"
    
    if ! check_current_dir; then
        error_exit "项目目录缺少必要文件，请检查以下文件是否存在：${REQUIRED_FILES[*]}"
    fi
}

# --------------------- 通用功能 ---------------------
check_dependencies() {
    if ! command -v docker &>/dev/null; then
        error_exit "Docker 未安装，请先安装 Docker"
    fi
}

check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        error_exit "未找到 $COMPOSE_FILE"
    fi
}

# --------------------- 服务管理 ---------------------
service_status() {
    echo -e "${YELLOW}当前服务状态:${NC}"
    docker compose ps -a || error_exit "状态查询失败"
}

start_services() {
    echo -e "${YELLOW}正在启动服务...${NC}"
    docker compose up -d --wait || error_exit "服务启动失败"
    echo -e "${GREEN}服务已成功启动${NC}"
}

stop_services() {
    echo -e "${YELLOW}正在停止服务...${NC}"
    docker compose down --remove-orphans || error_exit "服务停止失败"
    echo -e "${GREEN}服务已成功停止${NC}"
}

restart_services() {
    stop_services
    start_services
}

# --------------------- 更新相关 ---------------------
get_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || error_exit "无法获取当前分支"
}

lock_docker_files() {
    for file in Dockerfile docker-compose.yml; do
        if [ -f "$file" ]; then
            git update-index --skip-worktree "$file" 2>/dev/null
            echo -e "${GREEN}已锁定文件: $file${NC}"
        fi
    done
}

unlock_docker_files() {
    for file in Dockerfile docker-compose.yml; do
        if [ -f "$file" ]; then
            git update-index --no-skip-worktree "$file" 2>/dev/null
        fi
    done
}

update_repository() {
    echo -e "${YELLOW}正在更新代码仓库...${NC}"
    local current_branch=$(get_current_branch)

    # 锁定配置文件
    lock_docker_files

    # 重置并拉取更新
    git reset --hard "origin/$current_branch" || error_exit "重置本地修改失败"
    if ! git pull --ff-only "origin" "$current_branch"; then
        unlock_docker_files
        error_exit "代码拉取失败"
    fi

    echo -e "${GREEN}代码更新完成 (分支: ${current_branch})${NC}"
}

check_config_version() {
    echo -e "${YELLOW}检查配置文件版本...${NC}"
    
    local template_version=$(awk -F'"' '/^version/ {print $2}' template/bot_config_template.toml 2>/dev/null)
    local config_version=$(awk -F'"' '/^version/ {print $2}' bot_config.toml 2>/dev/null)
    
    if [[ -z "$template_version" || -z "$config_version" ]]; then
        echo -e "${YELLOW}跳过配置文件版本检查${NC}"
        return
    fi

    if [[ "$template_version" != "$config_version" ]]; then
        echo -e "${YELLOW}发现配置更新 (${config_version} → ${template_version})${NC}"
        
        if [[ -f "config/auto_update.py" && -d ".venv" ]]; then
            echo -e "${YELLOW}执行自动配置更新...${NC}"
            
            # 备份并临时修改配置路径
            if sed -i.bak 's|config_dir = root_dir / "config"|config_dir = root_dir / "docker-config"|' config/auto_update.py; then
                echo -e "${GREEN}已临时修改配置目录路径${NC}"
            else
                error_exit "配置文件修改失败"
            fi
            
            # 执行自动更新
            if ! ./.venv/bin/python config/auto_update.py; then
                # 恢复原始文件并报错
                mv -f config/auto_update.py.bak config/auto_update.py
                error_exit "自动更新失败"
            fi
            
            # 恢复原始配置文件
            if mv -f config/auto_update.py.bak config/auto_update.py; then
                echo -e "${GREEN}配置路径已恢复${NC}"
            else
                error_exit "配置文件恢复失败"
            fi
            
            echo -e "${GREEN}配置更新完成${NC}"
        else
            echo -e "${RED}警告：缺少自动更新所需组件${NC}"
        fi
    else
        echo -e "${GREEN}配置文件版本一致 (${template_version})${NC}"
    fi
}

update_process() {
    local current_branch=$(get_current_branch)
    
    case $current_branch in
        $STABLE_BRANCH)
            echo -e "${YELLOW}[稳定版] 拉取最新镜像...${NC}"
            docker compose pull || error_exit "镜像拉取失败"
            ;;
        $DEVELOPMENT_BRANCH)
            echo -e "${YELLOW}[开发版] 重建本地镜像...${NC}"
            docker build -t maimbot:local . || error_exit "镜像构建失败"
            ;;
        *) error_exit "不支持的更新分支: $current_branch" ;;
    esac
    
    # 检查虚拟环境
    if [ ! -d ".venv" ]; then
        error_exit "虚拟环境 .venv 不存在，请先初始化项目"
    fi
    
    check_config_version
    
    echo -e "${YELLOW}重启服务中...${NC}"
    docker compose up -d --force-recreate || error_exit "服务重启失败"
    
    # 解除文件锁定
    unlock_docker_files
    
    echo -e "${GREEN}更新完成!${NC}"
}

# --------------------- 主入口 ---------------------
main() {
    # 先检查当前目录，不满足条件时才进入项目目录
    if ! check_current_dir; then
        enter_project_dir
    fi
    
    check_dependencies
    check_compose_file

    case "$1" in
        start)    start_services ;;
        stop)     stop_services ;;
        restart)  restart_services ;;
        status)   service_status ;;
        update)
            update_repository
            update_process
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            echo -e "${RED}未知命令: $1${NC}"
            usage
            ;;
    esac
}

main "$@"