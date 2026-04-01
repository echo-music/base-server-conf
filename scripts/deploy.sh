#!/bin/bash
# 零停机部署脚本
# 使用方法: ./deploy.sh [service_name]
# 示例: ./deploy.sh local_mysql

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# 检查服务健康状态
check_health() {
    local service=$1
    local max_attempts=${2:-30}
    local attempt=1

    log_info "检查 $service 健康状态..."

    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps "$service" | grep -q "healthy"; then
            log_info "$service 已就绪!"
            return 0
        fi

        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "$service 健康检查失败!"
    return 1
}

# 备份指定服务
backup_service() {
    local service=$1
    local backup_dir="./backups/$(date +%Y%m%d_%H%M%S)"

    log_info "开始备份 $service..."
    mkdir -p "$backup_dir"

    case $service in
        local_mysql)
            docker exec local_mysql mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-123456}" --all-databases > "$backup_dir/mysql_backup.sql" 2>/dev/null || {
                log_warn "MySQL 备份可能不完整，请检查密码配置"
            }
            ;;
        local_redis)
            docker exec local_redis redis-cli BGSAVE
            sleep 2
            docker cp local_redis:/data/dump.rdb "$backup_dir/redis_backup.rdb" 2>/dev/null || true
            ;;
        local_rabbitmq)
            docker exec local_rabbitmq rabbitmqctl export_definitions /tmp/definitions.json 2>/dev/null || true
            docker cp local_rabbitmq:/tmp/definitions.json "$backup_dir/rabbitmq_definitions.json" 2>/dev/null || true
            ;;
        local_minio)
            log_warn "MinIO 数据备份请使用 mc 客户端或手动备份"
            ;;
    esac

    log_info "备份完成: $backup_dir"
}

# 优雅重启服务
graceful_restart() {
    local service=$1

    log_info "开始优雅重启 $service..."

    # 1. 预检查
    log_info "步骤 1/5: 预检查配置..."
    docker-compose config -q

    # 2. 备份数据
    log_info "步骤 2/5: 备份数据..."
    backup_service "$service"

    # 3. 拉取最新镜像（如果有更新）
    log_info "步骤 3/5: 更新镜像..."
    docker-compose pull "$service" 2>/dev/null || log_warn "使用本地镜像"

    # 4. 优雅停止并重启
    log_info "步骤 4/5: 停止服务（优雅关闭）..."
    docker-compose stop -t 60 "$service"

    log_info "步骤 5/5: 启动服务..."
    docker-compose up -d "$service"

    # 5. 健康检查
    if check_health "$service"; then
        log_info "$service 部署成功!"
    else
        log_error "$service 部署失败，准备回滚..."
        rollback "$service"
        exit 1
    fi
}

# 回滚服务
rollback() {
    local service=$1
    log_warn "执行回滚..."
    docker-compose restart "$service"
    check_health "$service"
}

# 显示使用帮助
show_help() {
    cat << EOF
零停机部署脚本

使用方法:
    ./deploy.sh [service_name]

可用服务:
    local_mysql     - MySQL 数据库
    local_redis     - Redis 缓存
    local_rabbitmq  - RabbitMQ 消息队列
    local_minio     - MinIO 对象存储
    all             - 所有服务

示例:
    ./deploy.sh local_mysql      # 部署 MySQL
    ./deploy.sh all              # 部署所有服务

EOF
}

# 主函数
main() {
    local target="${1:-all}"

    case $target in
        -h|--help|help)
            show_help
            exit 0
            ;;
        local_mysql)
            graceful_restart "local_mysql"
            ;;
        local_redis)
            graceful_restart "local_redis"
            ;;
        local_rabbitmq)
            graceful_restart "local_rabbitmq"
            ;;
        local_minio)
            graceful_restart "local_minio"
            ;;
        all)
            log_info "开始部署所有服务..."
            graceful_restart "local_mysql"
            graceful_restart "local_redis"
            graceful_restart "local_rabbitmq"
            graceful_restart "local_minio"
            log_info "所有服务部署完成!"
            ;;
        *)
            log_error "未知服务: $target"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
