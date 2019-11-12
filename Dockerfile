FROM nginx:stable-alpine

EXPOSE 80
EXPOSE 443
VOLUME [ "/data" ]
ENTRYPOINT [ "/docker-entrypoint.sh" ]

ENV LE_CONFIG_HOME /data/acme.sh
ENV LE_WORKING_DIR /opt/acme.sh
ENV LE_TARGET /data/ssl

ENV HTTPS_ACTIVE 0
ENV HTTPS_REDIRECT 1
ENV HTTPS_DOMAINS ""
ENV HTTPS_TEST_MODE 1
ENV PROXY_TARGET ""
ENV NGINX_CONFIG ""
ENV NGINX_HTTP_CONFIG ""
ENV NGINX_HTTPS_CONFIG ""
ENV NGINX_IMAGE_FILTER 0
ENV NOTIFICATION_MAIL ""
ENV RESOLVER_IPS="127.0.0.11 valid=20s ipv6=off"
    
# Install acme.sh and set up single crontab entry
RUN apk add -U openssl ca-certificates curl netcat-openbsd socat && \
    update-ca-certificates && \
    curl https://get.acme.sh | sh && \
    echo '9 0 * * * /opt/acme.sh/acme.sh --cron --home '${LE_CONFIG_HOME}' --config-home '${LE_CONFIG_HOME} | crontab -

COPY files/ /
