#!/bin/bash
# 数据备份脚本
# 支持全量备份和增量备份

set -e

# 配置
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DATE=$(date +%Y%m%d_%H%M%S)
DAY_OF_WEEK=$(date +%u)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# 加载环境变量
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份 MySQL
backup_mysql() {
    log_info "备份 MySQL..."
    local backup_file="$BACKUP_DIR/mysql_${DATE}.sql.gz"

    if docker ps | grep -q local_mysql; then
        docker exec local_mysql mysqldump \
            -uroot \
            -p"${MYSQL_ROOT_PASSWORD:-123456}" \
            --all-databases \
            --single-transaction \
            --quick \
            --lock-tables=false 2>/dev/null | gzip > "$backup_file" || {
            log_warn "MySQL 备份可能不完整"
        }

        if [ -f "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log_info "MySQL 备份完成: $backup_file ($size)"
        fi
    else
        log_warn "MySQL 容器未运行"
    fi
}

# 备份 Redis
backup_redis() {
    log_info "备份 Redis..."
    local backup_file="$BACKUP_DIR/redis_${DATE}.rdb"

    if docker ps | grep -q local_redis; then
        # 触发 BGSAVE
        docker exec local_redis redis-cli BGSAVE
        sleep 3

        # 复制 RDB 文件
        docker cp local_redis:/data/dump.rdb "$backup_file" 2>/dev/null || {
            log_warn "Redis 备份失败"
            return
        }

        if [ -f "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log_info "Redis 备份完成: $backup_file ($size)"
        fi
    else
        log_warn "Redis 容器未运行"
    fi
}

# 备份 RabbitMQ
backup_rabbitmq() {
    log_info "备份 RabbitMQ..."
    local backup_file="$BACKUP_DIR/rabbitmq_${DATE}.json"

    if docker ps | grep -q local_rabbitmq; then
        docker exec local_rabbitmq rabbitmqctl export_definitions /tmp/definitions.json 2>/dev/null || {
            log_warn "RabbitMQ 导出失败"
            return
        }

        docker cp local_rabbitmq:/tmp/definitions.json "$backup_file" 2>/dev/null || {
            log_warn "RabbitMQ 备份复制失败"
            return
        }

        if [ -f "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log_info "RabbitMQ 备份完成: $backup_file ($size)"
        fi
    else
        log_warn "RabbitMQ 容器未运行"
    fi
}

# 备份 MinIO 配置
backup_minio() {
    log_info "备份 MinIO 配置..."
    local backup_file="$BACKUP_DIR/minio_config_${DATE}.tar.gz"

    if docker ps | grep -q local_minio; then
        docker exec local_minio tar czf /tmp/minio_config.tar.gz /root/.minio 2>/dev/null || {
            log_warn "MinIO 配置打包失败"
            return
        }

        docker cp local_minio:/tmp/minio_config.tar.gz "$backup_file" 2>/dev/null || {
            log_warn "MinIO 配置备份复制失败"
            return
        }

        if [ -f "$backup_file" ]; then
            local size=$(du -h "$backup_file" | cut -f1)
            log_info "MinIO 配置备份完成: $backup_file ($size)"
        fi
    else
        log_warn "MinIO 容器未运行"
    fi
}

# 清理旧备份
cleanup_old_backups() {
    log_info "清理 ${RETENTION_DAYS} 天前的旧备份..."

    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "*.rdb" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "*.json" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

    log_info "清理完成"
}

# 显示备份统计
show_stats() {
    log_info "备份统计:"
    echo "------------------------"
    ls -lh "$BACKUP_DIR" | grep "$DATE" || echo "无今日备份文件"
    echo "------------------------"
    echo "备份目录总大小:"
    du -sh "$BACKUP_DIR"
}

# 显示使用帮助
show_help() {
    cat << EOF
数据备份脚本

使用方法:
    ./backup.sh [选项] [服务名]

选项:
    -h, --help      显示帮助
    --cleanup       仅清理旧备份

服务名:
    mysql       - 仅备份 MySQL
    redis       - 仅备份 Redis
    rabbitmq    - 仅备份 RabbitMQ
    minio       - 仅备份 MinIO
    all         - 备份所有服务 (默认)

环境变量:
    BACKUP_DIR      - 备份目录 (默认: ./backups)
    RETENTION_DAYS  - 备份保留天数 (默认: 7)

示例:
    ./backup.sh                 # 备份所有服务
    ./backup.sh mysql           # 仅备份 MySQL
    ./backup.sh --cleanup       # 仅清理旧备份

EOF
}

# 主函数
main() {
    local target="all"
    local cleanup_only=false

    # 解析参数
    for arg in "$@"; do
        case $arg in
            -h|--help)
                show_help
                exit 0
                ;;
            --cleanup)
                cleanup_only=true
                ;;
            mysql|redis|rabbitmq|minio|all)
                target=$arg
                ;;
        esac
    done

    if [ "$cleanup_only" = true ]; then
        cleanup_old_backups
        exit 0
    fi

    log_info "开始备份..."
    log_info "备份目录: $BACKUP_DIR"
    log_info "保留天数: $RETENTION_DAYS"

    case $target in
        mysql)
            backup_mysql
            ;;
        redis)
            backup_redis
            ;;
        rabbitmq)
            backup_rabbitmq
            ;;
        minio)
            backup_minio
            ;;
        all)
            backup_mysql
            backup_redis
            backup_rabbitmq
            backup_minio
            ;;
    esac

    cleanup_old_backups
    show_stats

    log_info "备份完成!"
}

main "$@"
