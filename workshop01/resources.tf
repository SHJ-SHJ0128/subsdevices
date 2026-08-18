# Docker images
resource "docker_image" "bgg_database" {
  name         = "chukmunnlee/bgg-database:${var.database_version}"
  keep_locally = false
}

resource "docker_image" "bgg_backend" {
  name         = "chukmunnlee/bgg-backend:${var.backend_version}"
  keep_locally = false
}

# Docker network and database volume
resource "docker_network" "bgg_net" {
  name = "${var.app_namespace}-bgg-net"
}

resource "docker_volume" "data_vol" {
  name = "${var.app_namespace}-data-vol"
}

# MySQL database
resource "docker_container" "bgg_database" {
  name  = "${var.app_namespace}-bgg-database"
  image = docker_image.bgg_database.image_id

  networks_advanced {
    name = docker_network.bgg_net.id
  }

  volumes {
    volume_name    = docker_volume.data_vol.name
    container_path = "/var/lib/mysql"
  }

  ports {
    internal = 3306
    external = 3306
  }
}

# Three backend containers
resource "docker_container" "bgg_backend" {
  count = var.backend_instance_count

  name  = "${var.app_namespace}-bgg-backend-${count.index}"
  image = docker_image.bgg_backend.image_id

  networks_advanced {
    name = docker_network.bgg_net.id
  }

  env = [
    "BGG_DB_USER=root",
    "BGG_DB_PASSWORD=changeit",
    "BGG_DB_HOST=${docker_container.bgg_database.name}"
  ]

  ports {
    internal = 3000
  }

  depends_on = [
    docker_container.bgg_database
  ]
}

# Generate Nginx configuration from backend ports
resource "local_file" "nginx_conf" {
  filename = "${path.module}/nginx.conf"

  content = templatefile("${path.module}/sample.nginx.conf.tftpl", {
    docker_host = var.docker_host
    ports       = docker_container.bgg_backend[*].ports[0].external
  })
}

# Find the SSH key registered in DigitalOcean
data "digitalocean_ssh_key" "www_1" {
  name = var.do_ssh_key
}

# Nginx reverse-proxy Droplet
resource "digitalocean_droplet" "nginx" {
  name   = "nginx"
  image  = var.do_image
  region = var.do_region
  size   = var.do_size

  ssh_keys = [
    data.digitalocean_ssh_key.www_1.id
  ]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key)
    host        = self.ipv4_address
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "apt update -y",
      "DEBIAN_FRONTEND=noninteractive apt install nginx -y"
    ]
  }

  provisioner "file" {
    source      = local_file.nginx_conf.filename
    destination = "/etc/nginx/nginx.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "nginx -t",
      "systemctl restart nginx"
    ]
  }
}

# Workshop-required empty file
resource "local_file" "root_at_nginx" {
  filename        = "${path.module}/root@${digitalocean_droplet.nginx.ipv4_address}"
  content         = ""
  file_permission = "0444"
}

# Required outputs
output "nginx_ip" {
  value = digitalocean_droplet.nginx.ipv4_address
}

output "backend_endpoints" {
  value = [
    for port in docker_container.bgg_backend[*].ports[0].external :
    "${var.docker_host}:${port}"
  ]
}
