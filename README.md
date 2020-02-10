# Docker multiapp
Host several applications under nginx proxy with docker.

### Usage
Configure your services in `services.conf`.

Generate nginx and docker configuration.
```bash
./manage.sh build
```

Then deploy your server on a docker swarm
```bash
docker stack deploy --compose-file docker-compose.yml docker-multiapp
```
Or with docker-compose
```bash
docker-compose up
```

Check status of deployed services.
```bash
./manage.sh status
```

### Example

### Features
[x] Generate nginx and docker configuration
[ ] Self-signed automatic ssl certificates via certbot
[ ] HTTP2
[ ] Support different protocols
