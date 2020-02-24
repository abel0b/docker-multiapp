# Docker multiapp [![pipeline status](https://gitlab.com/abel0b/docker-multiapp/badges/master/pipeline.svg)](https://gitlab.com/abel0b/docker-multiapp/-/commits/master)
Host several applications under nginx proxy with docker.

### Features
- [x] Generate nginx and docker configuration
- [x] Self-signed ssl certificates via certbot
- [x] Automatic certificate renewal
- [ ] Docker swarm mode
- [ ] Health check

### Usage
Configure your services in `services.conf`.

Generate configuration and deploy services.

```bash
./manage.sh up
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

Generate configuration and deploy services.
```bash
./manage.sh up
```

Run applications. Note that they must be in the same network than the nginx container.
```bash
docker run -d --name static_example --network multiapp -v /path/to/my/static/files:/usr/share/nginx/html nginx
docker run -d --name blog_example --network multiapp ghost
```

Open `static.example.org` and `blog.example.org` in a browser.

