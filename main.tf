module "dc1" {
  source = "./dc1"

  region = var.region
}

module "dc2" {
  source = "./dc2"

  network_region = var.network_region
}