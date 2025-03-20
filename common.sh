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

# 初始化路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/${CLONE_DIR}"

# 错误处理函数
error_exit() {
    echo -e "${RED}[错误] $1${NC}" >&2
    exit 1
}

# 进入项目目录
enter_project_dir() {
    echo -e "${YELLOW}正在进入项目目录: ${PROJECT_DIR}${NC}"
    cd "${PROJECT_DIR}" || error_exit "无法进入项目目录"
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
    docker compose ps -a 2>&1 # 直接输出原生信息
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

update_repository() {
    echo -e "${YELLOW}正在更新代码仓库...${NC}"
    local current_branch=$(get_current_branch)
    
    # 锁定关键配置文件（新增部分）
    lock_docker_files() {
        for file in Dockerfile docker-compose.yml; do
            if [ -f "$file" ]; then
                git update-index --skip-worktree "$file" || error_exit "无法锁定文件: $file"
                echo -e "${GREEN}已锁定文件: $file${NC}"
            fi
        done
    }

    # 解除文件锁定
    unlock_docker_files() {
        for file in Dockerfile docker-compose.yml; do
            if [ -f "$file" ]; then
                git update-index --no-skip-worktree "$file"
            fi
        done
    }

    # 在更新前锁定文件
    lock_docker_files

    # 重置并拉取更新
    git reset --hard "origin/$current_branch" || error_exit "重置本地修改失败"
    git pull --ff-only "origin" "$current_branch" || error_exit "代码拉取失败"

    # 更新后解除锁定
    #unlock_docker_files
    
    echo -e "${GREEN}代码更新完成 (分支: ${current_branch})${NC}"
}

check_config_version() {
    echo -e "${YELLOW}检查配置文件版本...${NC}"
    
    # 使用更安全的版本提取方式
    local template_version=$(awk -F'"' '/^version/ {print $2}' template/bot_config_template.toml)
    local config_version=$(awk -F'"' '/^version/ {print $2}' bot_config.toml)
    
    if [[ "$template_version" != "$config_version" ]]; then
        echo -e "${YELLOW}发现配置更新 (${config_version} → ${template_version})${NC}"
        
        if [[ -f "config/auto_update.py" ]]; then
            echo -e "${YELLOW}执行自动配置更新...${NC}"
            ./.venv/bin/python config/auto_update.py || error_exit "自动更新失败"
            echo -e "${GREEN}配置更新完成${NC}"
        else
            echo -e "${RED}警告：缺少自动更新脚本 config/auto_update.py${NC}"
        fi
    else
        echo -e "${GREEN}配置文件版本一致 (${template_version})${NC}"
    fi
}

update_process() {
    local current_branch=$(get_current_branch)
    
    # 分支专属操作
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
    [[ -d ".venv" ]] || error_exit "虚拟环境 .venv 不存在"
    
    # 配置更新检查
    check_config_version
    
    # 重启服务
    echo -e "${YELLOW}重启服务中...${NC}"
    docker compose up -d --force-recreate || error_exit "服务重启失败"
    echo -e "${GREEN}更新完成!${NC}"
}

# --------------------- 主入口 ---------------------
main() {
    enter_project_dir  # 确保所有操作在项目目录执行
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
        *)
            echo "使用方法: $0 {start|stop|restart|status|update}"
            exit 1
            ;;
    esac
}

main "$@"