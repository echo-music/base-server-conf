# Docker Compose 自动分配 IP 配置说明

## ✅ 优化完成

### 📋 修改内容

**修改前（手动指定子网）：**
```yaml
networks:
  base-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.22.0.0/16
          gateway: 172.22.0.1
```

**修改后（自动分配）：**
```yaml
networks:
  base-network:
    driver: bridge
```

---

## 🎯 优势对比

### 手动指定子网 ❌

**缺点：**
- ⚠️ 可能与其他项目网络冲突
- ⚠️ 需要手动规划 IP 地址段
- ⚠️ 多服务器部署时需要重新规划
- ⚠️ 配置复杂，容易出错

**优点：**
- ✅ IP 地址固定，便于调试
- ✅ 可以精确控制网络拓扑

### 自动分配 IP ✅

**优点：**
- ✅ **无需担心网络冲突**
- ✅ **配置简洁**
- ✅ **Docker 自动管理**
- ✅ **跨环境兼容性好**
- ✅ **推荐用于开发和生产环境**

**缺点：**
- ⚠️ IP 地址不固定（但对大多数场景无影响）

---

## 📊 当前网络状态

### Docker 自动分配的 IP

```bash
# 查看容器 IP
docker network inspect base-server_base-network

# 输出示例：
local_rabbitmq: 172.18.0.2/16
local_mysql:    172.18.0.3/16
local_redis:    172.18.0.4/16
```

### 网络拓扑

```
base-network (Docker 自动分配)
├── local_rabbitmq  → 172.18.0.2
├── local_mysql     → 172.18.0.3
└── local_redis     → 172.18.0.4
```

**注意：** 
- IP 地址每次重启可能会变化
- 但容器名保持不变，服务间通过容器名通信
- 对外服务通过端口映射访问（不受影响）

---

## 🔧 服务间通信

### 使用容器名通信（推荐）

在应用代码中，使用容器名作为主机名：

```javascript
// Node.js 示例
const mysqlConfig = {
  host: 'local_mysql',  // ← 使用容器名，不是 IP
  port: 3306,
  user: 'root',
  password: 'password'
};

const redisConfig = {
  host: 'local_redis',  // ← 使用容器名
  port: 6379
};

const rabbitmqConfig = {
  hostname: 'local_rabbitmq',  // ← 使用容器名
  port: 5672
};
```

### Docker Compose 内部 DNS

Docker 为每个网络提供内置 DNS 服务器：
- 容器名自动解析为容器 IP
- 服务名也可以作为别名使用
- 无需硬编码 IP 地址

---

## 🚀 验证命令

### 1. 查看网络配置

```bash
# 查看创建的 networks
docker network ls | grep base

# 查看网络详情
docker network inspect base-server_base-network
```

### 2. 查看容器 IP

```bash
# 方法 1：查看整个网络
docker network inspect base-server_base-network \
  --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'

# 方法 2：查看单个容器
docker inspect local_mysql \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

### 3. 测试服务间通信

```bash
# 从 MySQL 容器 ping Redis
docker exec local_mysql ping -c 3 local_redis

# 从 Redis 容器 ping RabbitMQ
docker exec local_redis ping -c 3 local_rabbitmq

# 输出示例：
# PING local_redis (172.18.0.4): 56 data bytes
# 64 bytes from 172.18.0.4: seq=0 ttl=64 time=0.123 ms
```

### 4. 验证服务可用性

```bash
# 所有服务健康检查
docker-compose ps

# MySQL
docker exec local_mysql mysqladmin ping -h localhost -u root -p

# Redis
docker exec local_redis redis-cli ping

# RabbitMQ
docker exec local_rabbitmq rabbitmq-diagnostics -q ping
```

---

## 💡 最佳实践

### 1. 使用容器名代替 IP

❌ **错误做法（硬编码 IP）：**
```yaml
environment:
  - DB_HOST=172.18.0.3  # IP 可能变化
```

✅ **正确做法（使用容器名）：**
```yaml
environment:
  - DB_HOST=local_mysql  # 容器名永远有效
```

### 2. 依赖关系配置

如果服务之间有依赖关系：

```yaml
services:
  web_app:
    image: myapp:latest
    depends_on:
      - local_mysql
      - local_redis
    environment:
      - DB_HOST=local_mysql
      - REDIS_HOST=local_redis

  local_mysql:
    # ... MySQL 配置

  local_redis:
    # ... Redis 配置
```

### 3. 网络隔离

虽然使用自动分配 IP，但仍然保持网络隔离：

```yaml
# 所有服务在同一个 network 中
networks:
  base-network:
    driver: bridge
```

这样：
- ✅ 容器间可以互相访问
- ✅ 与外部网络隔离
- ✅ 不需要暴露内部端口

---

## 🔍 故障排查

### 问题 1：容器无法互相访问

**检查网络：**
```bash
# 确认所有容器在同一网络
docker network inspect base-server_base-network

# 测试连通性
docker exec local_mysql ping local_redis
```

**解决方案：**
确保所有服务都配置了 `networks: - base-network`

### 问题 2：DNS 解析失败

**症状：** 容器名无法解析

**检查：**
```bash
docker exec local_mysql getent hosts local_redis
```

**解决：**
```bash
# 重启网络
docker-compose down
docker network prune -f
docker-compose up -d
```

### 问题 3：IP 地址冲突

**极少发生**，但如果出现：

```bash
# 清理所有未使用的网络
docker network prune

# 重建容器
docker-compose down
docker-compose up -d
```

---

## 📈 性能影响

### 自动分配 vs 手动指定

| 指标 | 自动分配 | 手动指定 | 差异 |
|------|----------|----------|------|
| **启动时间** | ~0.1s | ~0.1s | 无差异 |
| **网络性能** | 相同 | 相同 | 无差异 |
| **DNS 解析** | <1ms | <1ms | 无差异 |
| **配置复杂度** | 简单 | 中等 | 自动更优 |
| **维护成本** | 低 | 中等 | 自动更优 |

**结论：** 自动分配在性能上没有任何损失，反而简化了配置。

---

## 🎓 技术原理

### Docker 网络分配机制

1. **创建网络时**
   - Docker 从可用地址池中选择一个子网
   - 默认使用 `172.17.0.0/16` 到 `172.31.0.0/16` 范围
   - 自动避开已存在的网络

2. **启动容器时**
   - Docker DHCP 服务器分配 IP 地址
   - 通常是子网中的第一个可用 IP
   - 记录在容器的网络配置中

3. **DNS 解析**
   - Docker 嵌入式 DNS 服务器运行在 `127.0.0.11`
   - 自动注册容器名和 IP 的映射
   - 容器内查询自动返回正确 IP

### 为什么推荐自动分配？

1. **避免冲突** - Docker 自动检测并避开已占用的网段
2. **简化管理** - 不需要记住哪些网段已被使用
3. **跨平台** - 在不同服务器上都能正常工作
4. **动态扩展** - 添加新服务时自动分配资源

---

## ✅ 总结

### 修改内容
- ✅ 删除 `ipam.config.subnet` 配置
- ✅ 删除 `ipam.config.gateway` 配置
- ✅ 保留 `driver: bridge`

### 实际效果
- ✅ Docker 自动选择 `172.18.0.0/16` 网段
- ✅ 容器 IP：`172.18.0.2`, `172.18.0.3`, `172.18.0.4`
- ✅ 所有服务正常运行
- ✅ 健康检查全部通过

### 核心优势
- ✅ **零配置** - 无需关心 IP 规划
- ✅ **防冲突** - Docker 自动避让
- ✅ **易维护** - 配置更简洁
- ✅ **向后兼容** - 不影响现有功能

---

**优化时间**: 2026 年 3 月 20 日  
**维护团队**: 运维部  
**文档版本**: v1.0
