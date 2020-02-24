#!/bin/bash
work_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
config=$work_dir/services.conf
email="admin@example.org"
staging=${staging:-"false"}
swarm=${swarm:-"true"}
strict=${strict:-"true"}
force=${force:-"false"}
stack=multiapp
bold="\e[1m"
normal="\e[0m"
green="\e[32m"

declare -a services
declare -a domains
declare -a endpoints
declare -a https
declare -a networks

networks+=("multiapp")

default_domain=example.org
default_endpoint=example.org
default_https=true

if [[ "$strict" = "true" ]]
then
    set -e
fi

error() {
    echo -e "\e[31m[error]\e[0m $*"
    exit 1
}

function gen_docker_compose() {
    echo "version: '3'"
    echo
    echo "services:"
    echo "    nginx:"
    echo "        image: nginx:stable-alpine"
    echo "        ports:"
    echo "            - 80:80"
    echo "            - 443:443"
    echo "        volumes:"
    echo "            - $work_dir/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
    echo "            - $work_dir/nginx/dhparam.pem:/etc/nginx/dhparam.pem:ro"
    echo "            - $work_dir/nginx/conf.d:/etc/nginx/conf.d:ro"
    echo "            - $work_dir/letsencrypt:/etc/letsencrypt:ro"
    echo "        networks:"
    for network in "${networks[@]}"
    do
        echo "            - $network"
    done
    echo
    echo "networks:"
    for network in "${networks[@]}"
    do
        echo "    $network:"
        echo "        external: true"
    done
}

function gen_nginx_conf() {
    server_name=${domains[$1]}
    domain=($server_name)
    domain=${domain[0]}
    endpoint=${endpoints[$1]}
    
    echo "server {"
    echo "    listen 80;"
    echo "    listen [::]:80;"
    echo
    echo "    server_name $server_name;"
    echo
    if [[ "${https[$1]}" = "false" ]]
    then
        echo "    location / {"
        echo "        set \$upstream $endpoint;"
        echo "        proxy_pass http://\$upstream;"
        echo "    }"
    else
        echo "    location ^~ /.well-known/acme-challenge/ {"
        echo "        root /etc/letsencrypt/acme-challenge;"
        echo "    }"
        echo
        echo "    location / {"
        echo "        return 301 https://\$host\$request_uri;"
        echo "    }"
    fi
    echo "}"
    if [[ "${https[$1]}" = "true" ]]
    then
        echo
        echo "#server {"
        echo "#    listen 443 ssl;"
        echo "#    listen [::]:443 ssl;"
        echo "#"
        echo "#    ssl_certificate /etc/letsencrypt/certificates/live/$domain/fullchain.pem;"
        echo "#    ssl_certificate_key /etc/letsencrypt/certificates/live/$domain/privkey.pem;"
        echo "#"
        echo "#    server_name $server_name;"
        echo "#"
        echo "#    location / {"
        echo "#        set \$upstream $endpoint;"
        echo "#        proxy_pass http://\$upstream;"
        echo "#    }"
        echo "#}"
    fi
}

function gen_certificate() {
    if [[ "$email" =~ example\.org$ ]]
    then
        error "Email @example.org not allowed"
    fi

    domains_args=""
    for domain in ${domains[$1]}
    do
        domains_args="$domains_args -d $domain"
    done
    
    domain=(${domains[$1]})
    domain=${domain[0]}
    
    staging_arg=""
    if [[ "$staging" = "true" ]]
    then
        staging_arg="--staging --break-my-certs"
    fi

    force_arg=""
    if [[ "$force" = "true" ]]
    then
        force_arg="--force-renewal"
    fi

    docker run --rm -it -v $work_dir/letsencrypt/certificates:/etc/letsencrypt -v $work_dir/letsencrypt/acme-challenge:/var/www/html certbot/certbot certonly --webroot --webroot-path /var/www/html $staging_arg $domains_args --email $email -n --agree-tos $force_arg

    if [[ "$?" = "0" ]]
    then
        echo "certificate for ${domains[$1]} obtained"
    else
        echo "could not obtain certificate for ${domains[$1]}"
    fi
}

function gen_dhparam() {
    openssl dhparam -out $work_dir/nginx/dhparam.pem 2048 
}

function gen_systemd_service() {
    echo "# /etc/systemd/system/certbot.service"
    echo
    echo "[Unit]"
    echo "Description=Certbot automatic renewal"
    echo "After=docker.service"
    echo "Requires=docker.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "ExecStart=docker run --it --rm -v $work_dir/letsencrypt/certificates:/etc/letsencrypt -v $work_dir/letsencrypt/acme-challenge:/var/www/html certbot/certbot certbot renew"
}

function gen_systemd_timer() {
    echo "# /etc/systemd/system/certbot.timer"
    echo
    echo "[Unit]"
    echo "Description=Certbot automatic renewal"
    echo "Requires=certbot.service"
    echo
    echo "[Timer]"
    echo "OnCalendar=*-*-* 00,12:00:00"
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
}

function parse_config() {
    state="start"
    
    while read -r line
    do
        if [[ "$line" =~ ^(#.*|[[:blank:]]*)$ ]]
        then
            continue
        elif [[ "$line" =~ ^\[(.+)\]$ ]]
        then
            section=${BASH_REMATCH[1]}
            if [[ "$section" =~ ^services.(.+) ]]
            then
                services+=(${BASH_REMATCH[1]})
                domains+=("$default_domain")
                endpoints+=("$default_endpoint")
                https+=("$default_https")
                service_id=$((${#services[@]}-1))
                state="service"
                continue
            elif [[ "$section" = "docker" ]]
            then
                state="docker"
                continue
            elif [[ "$section" = "letsencrypt" ]]
            then
                state="letsencrypt"
                continue
            else
                error "Invalid section '$section'"
            fi
        fi

        case $state in
            service)
                if [[ "$line" =~ ^([a-z]+)=(.*)$ ]]
                then
                    # TODO: syntax check $line
                    property=${BASH_REMATCH[1]}
                    value=${BASH_REMATCH[2]}

                    case $property in
                        domains|domain)
                            domains[$service_id]=${value//\"/}
                            ;;
                        endpoint)
                            endpoints[$service_id]=${value//\"/}
                            ;;
                        https)
                            https[$service_id]=$value
                            ;; 
                        *)
                            error "Invalid property '$property'"
                            ;;
                    esac
                fi
                ;;
            docker)
                if [[ "$line" =~ ^([a-z]+)=(.*)$ ]]
                then
                    property=${BASH_REMATCH[1]}
                    value=${BASH_REMATCH[2]}
                    case $property in
                        networks)
                            networks+=("${value//\"/}")
                            ;;
                        *)
                            error "Invalid property '$property'"
                            ;;
                    esac
                fi
                ;;
            letsencrypt)
                if [[ "$line" =~ ^([a-z]+)=(.*)$ ]]
                then
                    property=${BASH_REMATCH[1]}
                    value=${BASH_REMATCH[2]}
                    case $property in
                        email)
                           email="${value//\"/}"
                            ;;
                        *)
                            error "Invalid property '$property'"
                            ;;
                    esac
                fi
                ;;
        esac
    done < $config

    if [[ "${#services[@]}" = "0" ]]
    then
        error "No service configured"
    fi

    if [[ "$debug" = "true" ]]
    then
        echo ${services[@]}
        echo ${domains[@]}
        echo ${endpoints[@]}
    fi
}

commands="help status up autorenew clean"
version=$(git describe --tags || echo "v0.0.0")

function command_help() {
    echo -e "${bold}Docker multiapp manager$normal $version"
    echo "github.com/abel0b/docker-multiapp"
    echo
    echo "Usage: ./manage.sh <command>"
    echo
    echo "Commands"
    echo "  status  Display status information"
    echo "  up      Generate configuration and start proxy"
}

function command_status() {
    # TODO: ping services
    for service in "${services[@]}"
    do
        echo -e "$service ${green}OK$normal"
    done
}

function command_up() {
    if [[ "$swarm" = "true" ]]
    then
        docker network create --attachable --scope swarm --driver overlay ${networks[0]} || true
    else
        docker network create --attachable ${networks[0]} || true
    fi

    gen_docker_compose > docker-compose.yml

    mkdir -p $work_dir/nginx/conf.d
    rm -rf $work_dir/nginx/conf.d/*.conf

    for i in "${!services[@]}"
    do
        gen_nginx_conf $i > $work_dir/nginx/conf.d/${services[$i]}.conf
    done

    docker run --rm -it -v $work_dir/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -v $work_dir/nginx/dhparam.pem:/etc/nginx/dhparam.pem:ro -v $work_dir/nginx/conf.d:/etc/nginx/conf.d:ro -v $work_dir/letsencrypt:/etc/letsencrypt:ro nginx:stable-alpine nginx -t

    #if [[ "$swarm" = "true" ]]
    #then
        docker stack deploy --compose-file docker-compose.yml $stack
    #else
    #    docker-compose down || true
    #    docker-compose up -d
    #fi

    for i in "${!services[@]}"
    do
        gen_certificate $i
    done

    # Uncomment ssl configuration
    sed -r -i "/^\s*#.*$/s/#//" $work_dir/nginx/conf.d/*.conf
    
    docker run --rm -it -v $work_dir/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -v $work_dir/nginx/dhparam.pem:/etc/nginx/dhparam.pem:ro -v $work_dir/nginx/conf.d:/etc/nginx/conf.d:ro -v $work_dir/letsencrypt:/etc/letsencrypt:ro nginx:stable-alpine nginx -t
    #if [[ "$swarm" = "true" ]]
    #then
        docker stack deploy --compose-file docker-compose.yml $stack
    #else
    #    docker-compose restart nginx
    #fi

    mkdir -p $work_dir/systemd
    gen_systemd_service > $work_dir/systemd/certbot.service
    gen_systemd_timer > $work_dir/systemd/certbot.timer
}

function command_clean() {
    rm -rf $work_dir/nginx/conf.d/*
    rm -rf $work_dir/letsencrypt/*
}

function command_autorenew() {
    ln -sf $work_dir/systemd/certbot.service /etc/systemd/system/certbot.service 
    ln -sf $work_dir/systemd/certbot.timer /etc/systemd/system/certbot.timer
    systemctl enable certbot.timer
    systemctl start certbot.timer
}

command=""
arguments=""
for token in "$@"
do
    case $token in
        -d|--debug)
            set -x
            ;;
        -h)
            command_help
            exit
            ;;
        -*)
            echo -e "\e[31m[error]\e[0m Unknown option $token"
            exit 1
            ;;
        *)
            if [[ -z "$command" ]]
            then
                command=$token
            else
                arguments="$arguments $token"
            fi
            ;;
    esac
done

command=${command:-help}

if [[ "$command" =~ ^(${commands//[[:space:]]/\|})$ ]]
then
    parse_config
    command_$command $arguments
else
    echo "\e[31m[error]\e[0m Unknown command '$command'"
    echo
    command_help
fi
