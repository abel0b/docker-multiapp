# Docker multiapp [![pipeline status](https://gitlab.com/abel0b/docker-multiapp/badges/master/pipeline.svg)](https://gitlab.com/abel0b/docker-multiapp/-/commits/master)
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
As example we deploy 2 applications, a static website with [`nginx`](https://hub.docker.com/_/nginx) image and a blog with [`ghost`](https://hub.docker.com/_/ghost).

Configure services in file `services.conf` replacing example.org with your own domain.

```
[services.static]
domains="static.example.org www.static.example.org"
endpoint="static_example"

[services.blog]
domains="example.org www.example.org"
endpoint="blog_example"
```

Generate configuration and deploy proxy.
```bash
./manage.sh build
docker stack deploy --compose-file docker-compose.yml docker-multiapp
```

Run applications. Note that they must be in the same network than the nginx container.
```bash
docker run -d --name static_example --network multiapp -v /path/to/my/static/files:/var/www/html nginx
docker run -d --name blog_example --network multiapp ghost
```

Open `static.example.org` and `blog.example.org` in a browser.

### Features
- [x] Generate nginx and docker configuration
- [ ] Self-signed automatic ssl certificates via certbot
- [ ] HTTP2
- [ ] Support different protocols
- [ ] Configuration file option
