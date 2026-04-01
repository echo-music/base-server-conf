# 自定义 RabbitMQ 镜像，预装延迟消息插件
FROM rabbitmq:4.2.5-management

# 安装 wget 和 ca-certificates（用于 HTTPS 下载）
RUN apt-get update && apt-get install -y wget ca-certificates && rm -rf /var/lib/apt/lists/*

RUN wget -O /opt/rabbitmq/plugins/rabbitmq_delayed_message_exchange-3.13.0.ez \
    https://github.com/rabbitmq/rabbitmq-delayed-message-exchange/releases/download/v3.13.0/rabbitmq_delayed_message_exchange-3.13.0.ez

# 启用插件
RUN rabbitmq-plugins enable --offline rabbitmq_delayed_message_exchange
