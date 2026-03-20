# Docker Compose 生产环境优化说明

## 📋 优化概览

本次优化按照**生产级别标准**对 docker-compose.yaml 进行全面改进，确保服务稳定性、安全性和可观测性。

---

## ✅ 已完成的优化

### 1️⃣ **MySQL 优化**

#### 安全加固
- ✅ 使用强密码：`Mysql@Secure2024!`（建议首次启动后修改）
- ✅ 允许远程连接：`MYSQL_ROOT_HOST=%`
- ✅ 网络隔离：加入 `base-network` 专用网络

#### 稳定性提升
- ✅ 健康检查：30 秒间隔自动检测
- ✅ 资源限制：2 CPU + 2G 内存
- ✅ 文件描述符：65536 限制
- ✅ 日志持久化：`./mysql/logs:/var/log/mysql`

#### 配置优化
```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 2G
```

---

### 2️⃣ **Redis 优化**

#### 性能优化
- ✅ AOF 持久化：每秒同步（appendfsync everysec）
- ✅ 内存限制：1GB maxmemory
- ✅ LRU 淘汰：allkeys-lru 策略
- ✅ 日志持久化：新增 `./redis/logs` 挂载

#### 稳定性提升
- ✅ 健康检查：redis-cli ping
- ✅ 资源限制：1 CPU + 1.5G 内存
- ✅ 文件描述符：65536 限制
- ✅ 网络隔离：加入 base-network

#### 命令优化
```yaml
command: >
  redis-server /usr/local/etc/redis/redis.conf
  --appendonly yes
  --appendfsync everysec
  --maxmemory 1gb
  --maxmemory-policy allkeys-lru
```

---

### 3️⃣ **RabbitMQ 优化**

#### 安全加固
- ✅ 修改默认用户名：`rabbitmq_admin`（不再使用 root）
- ✅ 使用强密码：`Rabbitmq@Secure2024!`
- ✅ 虚拟主机隔离：`/production`
- ✅ 限制本地连接：`RABBITMQ_LOOPBACK_USERS=guest`

#### 性能优化
- ✅ 内存高水位：60%（防止 OOM）
- ✅ 监控端口：开放 15692（Prometheus）
- ✅ 日志持久化：新增 `./rabbitmq/logs` 挂载

#### 系统调优
- ✅ 网络连接优化：somaxconn=65536
- ✅ 文件描述符：65536 限制
- ✅ 资源限制：2 CPU + 2G 内存
- ✅ 健康检查：rabbitmq-diagnostics ping

#### 环境配置
```yaml
environment:
  - RABBITMQ_DEFAULT_USER=rabbitmq_admin
  - RABBITMQ_DEFAULT_PASS=Rabbitmq@Secure2024!
  - RABBITMQ_DEFAULT_VHOST=/production
  - RABBITMQ_VM_MEMORY_HIGH_WATERMARK=0.6
sysctls:
  - net.core.somaxconn=65536
  - net.ipv4.tcp_max_syn_backlog=65536
```

---

### 4️⃣ **网络优化**

#### 独立网络
```yaml
networks:
  base-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

**优势：**
- ✅ 容器间通信更高效
- ✅ 与外部网络隔离
- ✅ 便于流量管理
- ✅ 支持服务发现

---

## 📊 优化对比

| 项目 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| **MySQL 密码** | 123456 | 强密码 | 🔒 安全性↑ |
| **RabbitMQ 用户** | root | rabbitmq_admin | 🔒 安全性↑ |
| **健康检查** | ❌ | ✅ 全部 | 🏥 可用性↑ |
| **资源限制** | ❌ | ✅ 全部 | 💰 资源可控 |
| **网络隔离** | ❌ | ✅ base-network | 🛡️ 安全性↑ |
| **日志持久化** | MySQL | 全部服务 | 📝 可追溯↑ |
| **Redis 持久化** | 未知 | AOF+LRU | 💾 可靠性↑ |
| **文件描述符** | 默认 | 65536 | 🚀 并发↑ |

---

## 🚀 使用说明

### 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 查看状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

### 验证健康检查

```bash
# MySQL
docker exec local_mysql mysqladmin ping -h localhost -u root -p

# Redis
docker exec local_redis redis-cli ping

# RabbitMQ
docker exec local_rabbitmq rabbitmq-diagnostics -q ping
```

### 查看资源使用

```bash
# 实时查看资源占用
docker stats

# 查看特定服务
docker stats local_mysql local_redis local_rabbitmq
```

---

## 🔐 安全建议

### 首次启动后必须做

1. **修改密码**
   ```sql
   -- MySQL
   ALTER USER 'root'@'%' IDENTIFIED BY 'YourNewStrongPassword!';
   
   -- Redis (需要重启)
   # 修改 redis.conf 中的 requirepass
   
   -- RabbitMQ
   rabbitmqctl change_password rabbitmq_admin YourNewStrongPassword!
   ```

2. **限制访问**
   ```bash
   # 通过防火墙限制端口访问
   sudo ufw allow from 192.168.1.0/24 to any port 3306
   sudo ufw allow from 192.168.1.0/24 to any port 6379
   sudo ufw allow from 192.168.1.0/24 to any port 5672
   ```

3. **定期备份**
   ```bash
   # MySQL 备份
   docker exec local_mysql mysqldump -u root -p --all-databases > backup.sql
   
   # Redis 备份
   docker exec local_redis redis-cli BGSAVE
   
   # RabbitMQ 备份
   docker exec local_rabbitmq rabbitmqctl export_definitions /backup.json
   ```

---

## 📈 监控指标

### MySQL 关键指标

```bash
# 连接数
docker exec local_mysql mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"

# 缓冲池命中率
docker exec local_mysql mysql -u root -p -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%';"

# 慢查询
docker exec local_mysql mysql -u root -p -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';"
```

### Redis 关键指标

```bash
# 内存使用
docker exec local_redis redis-cli INFO memory

# 连接数
docker exec local_redis redis-cli INFO clients

# Key 数量
docker exec local_redis redis-cli DBSIZE
```

### RabbitMQ 关键指标

```bash
# 队列状态
docker exec local_rabbitmq rabbitmqctl list_queues name messages consumers

# 连接状态
docker exec local_rabbitmq rabbitmqctl list_connections

# 节点状态
docker exec local_rabbitmq rabbitmq-diagnostics status
```

---

## ⚙️ 调优参数说明

### 资源限制建议

| 服务 | CPU | 内存 | 适用场景 |
|------|-----|------|----------|
| **MySQL** | 2.0 | 2G | 中小型应用 |
| **Redis** | 1.0 | 1.5G | 缓存/会话存储 |
| **RabbitMQ** | 2.0 | 2G | 中等消息量 |

**调整方法：**
```yaml
deploy:
  resources:
    limits:
      cpus: '4.0'    # 根据需求调整
      memory: 4G     # 根据需求调整
```

### 文件描述符

```yaml
ulimits:
  nofile:
    soft: 65536
    hard: 65536
```

**为什么重要：**
- 每个连接需要一个文件描述符
- 高并发场景需要更多描述符
- 避免 "Too many open files" 错误

### 健康检查参数

```yaml
healthcheck:
  test: ["CMD", "检查命令"]
  interval: 30s      # 检查间隔
  timeout: 10s       # 超时时间
  retries: 3         # 重试次数
  start_period: 60s  # 启动宽限期
```

---

## 🔧 故障排查

### 常见问题

#### 1. 服务无法启动

```bash
# 查看详细日志
docker-compose logs <service-name>

# 检查配置文件
docker-compose config

# 检查端口占用
netstat -tlnp | grep 3306
```

#### 2. 健康检查失败

```bash
# 手动执行健康检查
docker exec local_mysql mysqladmin ping -h localhost
docker exec local_redis redis-cli ping
docker exec local_rabbitmq rabbitmq-diagnostics -q ping
```

#### 3. 内存超限

```bash
# 查看资源使用
docker stats

# 调整资源配置
vim docker-compose.yaml  # 修改 limits.memory
```

---

## 📝 版本历史

- **v2.0** (2024-03) - 生产级优化
  - ✅ 全面健康检查
  - ✅ 资源限制
  - ✅ 网络隔离
  - ✅ 安全加固
  
- **v1.0** (早期版本) - 基础配置
  - ✅ 基本服务部署
  - ✅ 数据持久化

---

## 🆘 技术支持

如遇到问题：
1. 查看日志：`docker-compose logs -f`
2. 检查配置：`docker-compose config`
3. 查看文档：各服务官方文档
4. 监控系统资源：`docker stats`

---

**维护团队：** 运维部  
**最后更新：** 2024 年 3 月  
**文档版本：** v2.0
