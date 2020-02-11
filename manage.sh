#!/bin/bash

bold=$(tput bold)
normal=$(tput sgr0)
green=$(tput setaf 2)
work_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)
config=$work_dir/services.conf
network="multiapp"

declare -a services
declare -a domains
declare -a endpoints
declare -a https
declare -a networks

default_domain=example.org
default_endpoint=example.org
default_https=true

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
    echo "            - $work_dir/nginx:/etc/nginx/conf.d:ro"
    echo "        networks:"
    echo "            - $network"
    for network in "${networks[@]}"
    do
        echo "            - $network"
    done
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
    domain=${domains[$1]}
    endpoint=${endpoints[$1]}
    echo "server {"
    echo "    resolver 127.0.0.11 valid=30s;"
    echo
    echo "    listen 80;"
    echo "    listen [::]:80;"
    echo
    echo "    server_name $domain;"
    echo
    echo "    location / {"
    echo "        set \$upstream $endpoint;"
    echo "        proxy_pass http://\$upstream;"
    echo "    }"
    echo "}"
}

function parse_config() {

    state="start"
    
    while read -r line
    do
        if [[ "$line" =~ ^(#.*|[[:blank:]]*)$ ]]
        then
            continue
        fi

        case $state in
            start)
                if [[ "$line" =~ ^\[(.+)\]$ ]]
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
                    else
                        error "Invalid section '$section'"
                    fi
                else
                    error "Unexpected token $line"
                fi    
                ;;
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
                    else
                        error "Invalid section '$section'"
                    fi
                else
                    error "Unexpected token $line"
                fi
                ;;
        esac
    done < $config

    if [[ "$debug" = "true" ]]
    then
        echo ${services[@]}
        echo ${domains[@]}
        echo ${endpoints[@]}
    fi
}

commands="help status build"
version=$(git describe)

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
        echo "$service ${green}OK$normal"
    done
}

function command_build() {
    gen_docker_compose > docker-compose.yml

    mkdir -p nginx
    for i in "${!services[@]}"
    do
        gen_nginx_conf $i > nginx/${services[$i]}.conf
    done
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
