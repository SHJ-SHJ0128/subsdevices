# Find the SSH key registered in DigitalOcean
data "digitalocean_ssh_key" "www_1" {
  name = var.do_ssh_key
}

# Code Server Droplet
resource "digitalocean_droplet" "codeserver" {
  name   = "codeserver"
  image  = var.do_image
  region = var.do_region
  size   = var.do_size

  ssh_keys = [
    data.digitalocean_ssh_key.www_1.id
  ]

  tags = [
    "workshop5",
    "codeserver"
  ]
}

# Workshop-required empty connection file
resource "local_file" "root_at_codeserver" {
  filename        = "${path.module}/root@${digitalocean_droplet.codeserver.ipv4_address}"
  content         = ""
  file_permission = "0444"
}

# Generate the Ansible inventory
resource "local_sensitive_file" "inventory" {
  filename = "${path.module}/inventory.yaml"

  content = templatefile("${path.module}/inventory.yaml.tftpl", {
    codeserver_ip       = digitalocean_droplet.codeserver.ipv4_address
    ssh_private_key     = var.ssh_private_key
    codeserver_domain   = "code-server-${digitalocean_droplet.codeserver.ipv4_address}.nip.io"
    codeserver_password = var.codeserver_password
  })

  file_permission = "0600"
}

output "codeserver_ip" {
  value = digitalocean_droplet.codeserver.ipv4_address
}

output "codeserver_url" {
  value = "http://code-server-${digitalocean_droplet.codeserver.ipv4_address}.nip.io"
}
