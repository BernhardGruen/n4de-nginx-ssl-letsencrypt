#!/bin/sh

set -eu

create_ssl_config() {
cat <<-'EOF' > /etc/nginx/conf.d/ssl-default.conf
server {
    listen 443 ssl http2;
    server_name _;

    ssl on;
    ssl_certificate /data/ssl/cert.pem;
    ssl_certificate_key /data/ssl/key.pem;
    add_header		Strict-Transport-Security		"max-age=31536000;" always;
EOF

if [ -z "$PROXY_TARGET" ] && [ -z "$NGINX_CONFIG" ]; then
cat <<-'EOF' >> /etc/nginx/conf.d/ssl-default.conf
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }
    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
EOF
elif [ -n "$NGINX_CONFIG" ]; then
    echo "$NGINX_CONFIG" >> /etc/nginx/conf.d/ssl-default.conf
elif [ -n "$PROXY_TARGET" ]; then
cat <<-EOF >> /etc/nginx/conf.d/ssl-default.conf
location / {
    set \$proxy_target $PROXY_TARGET;
EOF
cat <<-'EOF' >> /etc/nginx/conf.d/ssl-default.conf
    proxy_pass                  $proxy_target;
    proxy_http_version		    1.1;
    proxy_set_header		    Host $host;
    proxy_set_header		    X-Real-IP $remote_addr;
    proxy_set_header		    X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_hide_header		    Pragma;
    proxy_hide_header		    Cache-Control;
    proxy_send_timeout		    120;
    proxy_read_timeout		    120;
    proxy_connect_timeout	    30;
    send_timeout			    120;
    client_body_timeout		    120;
    proxy_set_header		    X-Forwarded-Proto $scheme;
    chunked_transfer_encoding	off;
    proxy_buffering			    off;
    proxy_cache			        off;
}
EOF
fi

cat <<-'EOF' >> /etc/nginx/conf.d/ssl-default.conf
}
EOF
}

create_https_redirect() {
if [ "$HTTPS_REDIRECT" = 1 ]; then
cat <<-'EOF' > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;

    location / {
        return 301 https://$host$request_uri;
    }
}
EOF
fi
}

create_gzip_config() {
cat <<-'EOF' > /etc/nginx/conf.d/00-gzip.conf    
    gzip on;
    gzip_buffers 16 8k;
    gzip_comp_level 1;
    gzip_http_version 1.1;
    gzip_min_length 10;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/x-icon application/vnd.ms-fontobject font/opentype application/x-font-ttf;
    gzip_vary on;
    gzip_proxied any; # Compression for all requests.
    ## No need for regexps. See
    ## http://wiki.nginx.org/NginxHttpGzipModule#gzip_disable
    gzip_disable msie6;
EOF
}

create_resolver_config() {
cat <<-EOF > /etc/nginx/conf.d/01-resolver.conf    
    resolver $RESOLVER_IPS;
EOF
}

# Only process HTTPs if it is active and HTTPS_DOMAINS were set
if [ "${HTTPS_ACTIVE}" = 1 ] && [ -n "${HTTPS_DOMAINS}" ]; then
    if [ "${HTTPS_TEST_MODE}" = 1 ]; then
        TEST_OPTION="--test"
    else
        TEST_OPTION=""
    fi
    
    if [ -n "$NOTIFICATION_MAIL" ]; then
        /opt/acme.sh/acme.sh --update-account $TEST_OPTION --accountemail "$NOTIFICATION_MAIL"
    fi

    DOMAIN_OPTIONS=""
    DOMAIN_IN_LIST=1

    for DOMAIN in ${HTTPS_DOMAINS}
    do
        if ! /opt/acme.sh/acme.sh --list | grep -q "$DOMAIN"; then
            DOMAIN_IN_LIST=0
        fi
        DOMAIN_OPTIONS="$DOMAIN_OPTIONS -d ""$DOMAIN"
    done
    if [ "${DOMAIN_IN_LIST}" != 1 ]; then
        mkdir -p "$LE_TARGET"
        /opt/acme.sh/acme.sh --issue --standalone $TEST_OPTION $DOMAIN_OPTIONS || true
        /opt/acme.sh/acme.sh --install-cert --key-file "$LE_TARGET"/key.pem --fullchain-file "$LE_TARGET"/cert.pem --reloadcmd "nginx -s reload || true" $DOMAIN_OPTIONS
    fi

    create_gzip_config
    create_resolver_config
    create_https_redirect
    create_ssl_config

    # execute cron to update certificates
    crond -f &
fi

exec nginx -g "daemon off;"