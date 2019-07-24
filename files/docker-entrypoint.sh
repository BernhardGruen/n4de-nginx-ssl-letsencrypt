#!/bin/sh

set -eu

_proxy_target() {
    CONFIG_FILENAME=$1

    cat <<-EOF >> "$CONFIG_FILENAME"
        location / {
            set \$proxy_target $PROXY_TARGET;
EOF
    cat <<-'EOF' >> "$CONFIG_FILENAME"
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
            proxy_set_header		    X-Forwarded-Proto $effective_scheme;
            chunked_transfer_encoding	off;
            proxy_buffering			    off;
            proxy_cache			        off;
        }
EOF
}

_location_lets_encrypt() {
    CONFIG_FILENAME=$1
    cat <<-'EOF' >> "$CONFIG_FILENAME"
        location ~ /.well-known {
            root /tmp/letsencrypt;
        }
EOF
}

_http_server_begin() {
    CONFIG_FILENAME=$1
    cat <<-'EOF' > "$CONFIG_FILENAME"
    server {
        listen 80;
        server_name _;
EOF
}

_https_server_begin() {
    CONFIG_FILENAME=$1
    cat <<-'EOF' > "$CONFIG_FILENAME"
    server {
        listen 443 ssl http2;
        server_name _;

        ssl on;
        ssl_certificate /data/ssl/cert.pem;
        ssl_certificate_key /data/ssl/key.pem;
        add_header		Strict-Transport-Security		"max-age=31536000;" always;
EOF
}

_server_end() {
    CONFIG_FILENAME=$1
    cat <<-'EOF' >> "$CONFIG_FILENAME"
    }
EOF
}

_location_default() {
    CONFIG_FILENAME=$1

    cat <<-'EOF' >> "$CONFIG_FILENAME"
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
}

_location_https_redirect() {
    CONFIG_FILENAME=$1

    cat <<-'EOF' >> "$CONFIG_FILENAME"
        location / {
            return 301 https://$host$request_uri;
        }
EOF
}

create_esm_config() {
cat <<-'EOF' > /etc/nginx/conf.d/02-effective-scheme-map.conf
    map $http_x_forwarded_proto $effective_scheme {
        default $http_x_forwarded_proto;
	""      $scheme;
    }
EOF
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

create_https_config() {
    _CONFIG_FILENAME=/etc/nginx/conf.d/ssl-default.conf

    if [ "$HTTPS_ACTIVE" != 1 ]; then
        return
    fi

    _https_server_begin "$_CONFIG_FILENAME"
    _location_lets_encrypt "$_CONFIG_FILENAME"

    if [ -z "$PROXY_TARGET" ] && [ -z "$NGINX_CONFIG" ]; then
        _location_default "$_CONFIG_FILENAME"
    elif [ -n "$NGINX_HTTPS_CONFIG" ]; then
        echo "$NGINX_HTTPS_CONFIG" >> "$_CONFIG_FILENAME"
    elif [ -n "$NGINX_CONFIG" ]; then
        echo "$NGINX_CONFIG" >> "$_CONFIG_FILENAME"
    elif [ -n "$PROXY_TARGET" ]; then
        _proxy_target "$_CONFIG_FILENAME"
    fi

    _server_end "$_CONFIG_FILENAME"
}

create_http_config() {
    _CONFIG_FILENAME=/etc/nginx/conf.d/default.conf

    _http_server_begin "$_CONFIG_FILENAME"

    if [ "$HTTPS_ACTIVE" = 1 ]; then
        _location_lets_encrypt "$_CONFIG_FILENAME"
    fi

    if [ "$HTTPS_ACTIVE" = 1 ] && [ "$HTTPS_REDIRECT" = 1 ]; then
        _location_https_redirect "$_CONFIG_FILENAME"
    elif [ -z "$PROXY_TARGET" ] && [ -z "$NGINX_CONFIG" ]; then
        _location_default "$_CONFIG_FILENAME"
    elif [ -n "$NGINX_HTTP_CONFIG" ]; then
        echo "$NGINX_HTTP_CONFIG" >> "$_CONFIG_FILENAME"
    elif [ -n "$NGINX_CONFIG" ]; then
        echo "$NGINX_CONFIG" >> "$_CONFIG_FILENAME"
    elif [ -n "$PROXY_TARGET" ]; then
        _proxy_target "$_CONFIG_FILENAME"
    fi

    _server_end "$_CONFIG_FILENAME"
}

create_basic_lets_encrypt_config() {
    _CONFIG_FILENAME=/etc/nginx/conf.d/default.conf

    _http_server_begin "$_CONFIG_FILENAME"
    _location_lets_encrypt "$_CONFIG_FILENAME"
    _server_end "$_CONFIG_FILENAME"
}

# Only process HTTPs if it is active and HTTPS_DOMAINS were set
if [ "${HTTPS_ACTIVE}" = 1 ] && [ -n "${HTTPS_DOMAINS}" ]; then
    mkdir -p /tmp/letsencrypt/.well-known/acme-challenge
    mkdir -p "$LE_TARGET"

    if [ "${HTTPS_TEST_MODE}" = 1 ]; then
        TEST_OPTION="--test"
    else
        TEST_OPTION=""
    fi
    
    if [ -n "$NOTIFICATION_MAIL" ]; then
        /opt/acme.sh/acme.sh --update-account $TEST_OPTION --accountemail "$NOTIFICATION_MAIL" || echo "Account update was not possible!"
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

        # create basic config for first time certificate generation
        create_basic_lets_encrypt_config

        # start a temporary nginx instance in background
        nginx -g "daemon off;" &

        # issue and install certificate
        /opt/acme.sh/acme.sh --issue -w /tmp/letsencrypt $TEST_OPTION $DOMAIN_OPTIONS
        /opt/acme.sh/acme.sh --install-cert --key-file "$LE_TARGET"/key.pem --fullchain-file "$LE_TARGET"/cert.pem --reloadcmd "nginx -s reload" $DOMAIN_OPTIONS

        # kill all temporary nginx processes
        pkill nginx
        sleep 5
    fi

    # execute cron to update certificates when needed
    crond -f &
fi

# create full nginx config
create_gzip_config
create_esm_config
create_resolver_config
create_http_config
create_https_config

echo "***** GENERATED CONFIG *****"
nginx -T
echo "***** CONFIG END ******"

# start main nginx instance
exec nginx -g "daemon off;"

