#!/bin/bash

work_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
config=$work_dir/services.conf
network="multiapp"
email="admin@example.org"
staging=${staging:-"false"}
swarm=${swarm:-"false"}
strict=${strict:-"true"}
bold="\e[1m"
normal="\e[0m"
green="\e[32m"

declare -a services
declare -a domains
declare -a endpoints
declare -a https
declare -a networks

default_domain=example.org
default_endpoint=example.org
default_https=true

if [[ "$strict" = "true" ]]
then
    set -e
fi

function docker_up() {
    if [[ "$swarm" = "true" ]]
    then
        docker stack deploy --compose-file docker-compose.yml $network
    else
        docker-compose up -d $1
    fi
}

error() {
    echo -e "\e[31m[error]\e[0m $*"
    exit 1
}

function gen_docker_compose() {
    echo "version: '3'"
    echo
    echo "services:"
    echo "    nginx:"
    echo "        image: nginx"
    echo "        ports:"
    echo "            - 80:80"
    echo "            - 443:443"
    echo "        volumes:"
    echo "            - $work_dir/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
    echo "            - $work_dir/nginx/dhparam.pem:/etc/nginx/dhparam.pem:ro"
    echo "            - $work_dir/nginx/conf.d:/etc/nginx/conf.d:ro"
    echo "            - $work_dir/letsencrypt:/etc/letsencrypt:ro"
    echo "        networks:"
    echo "            - $network"
    for network in "${networks[@]}"
    do
        echo "            - $network"
    done
    echo "    certbot:"
    echo "        image: certbot/certbot"
    echo "        volumes:"
    echo "            - $work_dir/letsencrypt/certificates:/etc/letsencrypt"
    echo "            - $work_dir/letsencrypt/acme-challenge:/var/www/html"
    echo "        entrypoint: \"/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'\""
    echo
    echo "networks:"
    echo "    $network:"
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
    if [[ "$email" =~ example\.org ]]
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
        staging_arg="--staging"
    fi

    docker run --rm -it -v $work_dir/letsencrypt/certificates:/etc/letsencrypt -v $work_dir/letsencrypt/acme-challenge:/var/www/html certbot/certbot certonly --webroot --webroot-path /var/www/html $staging_arg $domains_args --email $email -n --agree-tos --force-renewal

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
        esac
    done < $config

    if [[ "$debug" = "true" ]]
    then
        echo ${services[@]}
        echo ${domains[@]}
        echo ${endpoints[@]}
    fi
}

commands="help status build clean"
version=$(git describe || echo "v0.0.0")

function command_help() {
    echo "${bold}Docker multiapp manager$normal $version"
    echo "github.com/abel0b/docker-multiapp"
    echo
    echo "Usage: ./manage.sh <command>"
    echo
    echo "Commands"
    echo "  status  Display status information"
    echo "  build   Generate nginx and docker configuration"
}

function command_status() {
    # TODO: ping services
    for service in "${services[@]}"
    do
        echo -e "$service ${green}OK$normal"
    done
}

function command_build() {
    gen_docker_compose > docker-compose.yml

    mkdir -p nginx/conf.d
    rm -rf nginx/conf.d/*.conf

    for i in "${!services[@]}"
    do
        gen_nginx_conf $i > nginx/conf.d/${services[$i]}.conf
    done

    docker-compose up -d
    docker-compose exec nginx nginx -t
    docker-compose exec nginx nginx -s reload

    sleep 5

    for i in "${!services[@]}"
    do
        gen_certificate $i
    done

    # Uncomment ssl configuration
    sed -r -i "/^\s*#.*$/s/#//" $work_dir/nginx/conf.d/*.conf
    docker-compose exec nginx nginx -t
    docker-compose exec nginx nginx -s reload
}

function command_clean() {
    rm -rf nginx/conf.d/*
    rm -rf letsencrypt/*
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
