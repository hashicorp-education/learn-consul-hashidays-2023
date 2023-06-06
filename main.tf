module "dc1" {
  source = "./dc1"

  region = var.region
}

module "dc2" {
  source = "./dc2"

  appId    = var.appId
  password = var.password
}