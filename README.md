# MaiBot 部署与管理工具

## 项目概述

本仓库包含两套自动化脚本，为 MaiBot 提供一站式部署和管理解决方案。包含以下核心组件：

1. **部署脚本** (`install.sh`)  ![部署流程](https://img.shields.io/badge/流程-克隆→配置→构建→部署-success)
2. **管理脚本** (`common.sh`)   ![管理功能](https://img.shields.io/badge/功能-启停+更新+状态监控-blue)

---

## 快速入门指南

### 前置要求

- Linux 系统 (推荐 Ubuntu 20.04+)
- 2GB 可用内存
- 5GB 磁盘空间
- 稳定的网络连接

### 部署流程

```bash
# 1. 下载部署脚本
# 2. 执行自动化部署（开发版）
chmod +x install.sh && ./install.sh 
```

---

## 配置架构

```
.
├── docker-config/           # 配置中心
    ├── bot_config.toml      # 主配置文件
    └── .env.prod           # 环境变量


```

---

## 管理脚本使用

```bash
# 启动麦麦
./common.sh start
# 停止麦麦
./common.sh stop
# 查看麦麦（容器）状态
./common.sh status
# 执行智能更新
./common.sh update

```

### 日志

```bash
# 实时查看日志
docker compose logs -f --tail=100

# 性能监控
docker stats $(docker ps -q)
```
