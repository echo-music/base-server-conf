FROM rabbitmq:4.2.5-management

# 将宿主机目录下的插件复制到容器的插件目录
COPY ./plugins/rabbitmq_delayed_message_exchange-*.ez /plugins/

# 启用延迟插件
RUN rabbitmq-plugins enable --offline rabbitmq_delayed_message_exchange
