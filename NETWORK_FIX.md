# Docker Compose 网络配置修复说明

## 🐛 问题描述

启动时遇到以下错误：

```
WARN[0000] /Users/liufangting/wwwroot/base-server/docker-compose.yaml: 
the attribute `version` is obsolete, it will be ignored

Error response from daemon: invalid pool request: Pool overlaps with 
other one on this address space
```

## 🔍 问题原因

### 1. Version 属性过时
- **原因**：Docker Compose v2+ 不再需要 `version` 字段
- **解决**：已删除 `version: '3.8'` 行

### 2. 网络地址冲突
- **原配置**：使用 `172.20.0.0/16` 网段
- **冲突对象**：`rocketmq_rocketmq` 网络（属于 rocketmq 项目）
- **影响**：无法创建 `base-network` 网络

**查看现有网络：**
```bash
docker network ls --format "{{.Name}}\t{{.Scope}}"
docker network inspect rocketmq_rocketmq --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
# 输出：172.20.0.0/16
```

## ✅ 解决方案

### 修改内容

**修改前：**
```yaml
networks:
  base-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

**修改后：**
```yaml
networks:
  base-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.22.0.0/16
          gateway: 172.22.0.1
```

### 为什么选择 172.22.0.0/16？

Docker 默认使用的网段范围：
- `172.17.0.0/16` - Docker 默认 bridge 网络
- `172.18.0.0/16` ~ `172.19.0.0/16` - Compose 常用
- `172.20.0.0/16` - RocketMQ 项目已占用 ❌
- `172.21.0.0/16` - 可能与其他项目冲突
- `172.22.0.0/16` - **空闲，选择此网段** ✅

## 🎯 其他优化

### 1. RabbitMQ 配置优化

**问题**：使用了已弃用的环境变量 `RABBITMQ_VM_MEMORY_HIGH_WATERMARK`

**解决方案**：
1. 删除已弃用的环境变量
2. 使用配置文件方式

**新增配置文件挂载：**
```yaml
volumes:
  - ./rabbitmq/conf/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
```

**rabbitmq.conf 配置：**
```ini
# 内存高水位标记
vm_memory_high_watermark.relative = 0.6

# 日志级别
log.default.level = notice
log.console = true
log.console.formatter = json

# 网络端口
listeners.tcp.default = 5672
management.tcp.port = 15672
prometheus.tcp.port = 15692
```

---

## 📊 当前网络拓扑

```
┌─────────────────────────────────────────────────┐
│         base-network (172.22.0.0/16)            │
│                                                 │
│  ┌──────────────┐                              │
│  │ local_mysql  │  IP: 172.22.0.2              │
│  │  mysql-host  │  Port: 3306                  │
│  └──────────────┘                              │
│                                                 │
│  ┌──────────────┐                              │
│  │ local_redis  │  IP: 172.22.0.3              │
│  │  redis-host  │  Port: 6379                  │
│  └──────────────┘                              │
│                                                 │
│  ┌──────────────┐                              │
│  │local_rabbitmq│  IP: 172.22.0.4              │
│  │rabbitmq-node-1│ Port: 5672, 15672, 15692   │
│  └──────────────┘                              │
└─────────────────────────────────────────────────┘
                    ↕
            Docker Bridge
                    ↕
            Host Machine
                    ↕
        ┌───────────┴───────────┐
        │                       │
   Port Mapping           External Access
   3306, 6379,             (via firewall rules)
   5672, 15672,
   15692
```

---

## 🚀 重启后的状态

```bash
# 查看所有服务状态
docker-compose ps

# 输出示例：
NAME             IMAGE                       STATUS                           PORTS
local_mysql      mysql:8.0.40                Up 3 minutes (healthy)          0.0.0.0:3306->3306/tcp
local_redis      redis:7.2.7                 Up 3 minutes (healthy)          0.0.0.0:6379->6379/tcp
local_rabbitmq   rabbitmq:4.2.5-management   Up 1 minute (health: starting)  0.0.0.0:5672,15672,15692->...
```

---

## 🔧 故障排查命令

### 1. 检查网络配置

```bash
# 查看创建的 networks
docker network ls | grep base

# 查看网络详情
docker network inspect base-server_base-network

# 查看容器 IP
docker inspect local_mysql --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

### 2. 验证健康检查

```bash
# MySQL
docker exec local_mysql mysqladmin ping -h localhost -u root -p

# Redis
docker exec local_redis redis-cli ping

# RabbitMQ
docker exec local_rabbitmq rabbitmq-diagnostics -q ping
```

### 3. 查看日志

```bash
# 所有服务日志
docker-compose logs -f

# 单个服务日志
docker-compose logs -f local_rabbitmq
```

---

## 📝 最佳实践建议

### 1. 避免网络冲突

**推荐做法：**
- ✅ 为每个项目使用不同的网段
- ✅ 在 docker-compose.yaml 中明确指定子网
- ✅ 避免使用 Docker 默认的 172.17.x.x

**网段规划建议：**
```yaml
# 项目 A
subnet: 172.22.0.0/16

# 项目 B
subnet: 172.23.0.0/16

# 项目 C
subnet: 172.24.0.0/16
```

### 2. 清理无用网络

```bash
# 列出所有未使用的网络
docker network ls -f dangling=true

# 删除未使用的网络
docker network prune

# 强制删除所有自定义网络（谨慎使用）
docker network rm $(docker network ls -q)
```

### 3. 监控网络使用

```bash
# 查看网络连接
docker network inspect bridge

# 查看容器网络统计
docker stats --no-stream
```

---

## ✅ 验证清单

- [x] 删除 version 属性
- [x] 修改网段为 172.22.0.0/16
- [x] 移除 RabbitMQ 已弃用环境变量
- [x] 添加 RabbitMQ 配置文件
- [x] 所有服务正常启动
- [x] 健康检查通过
- [x] 网络隔离生效

---

## 📞 参考资源

- Docker Compose 网络文档：https://docs.docker.com/compose/networking/
- Docker 网络驱动：https://docs.docker.com/network/
- RabbitMQ 配置文档：https://www.rabbitmq.com/configure.html

---

**修复时间**: 2024 年 3 月  
**维护团队**: 运维部  
**文档版本**: v1.0
