terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.42"
    }
  }
}

provider "google" {
  project = "cloudweb-465120"
  region  = "us-west1"
}

# Compute Instance
resource "google_compute_instance" "web" {
  name         = "website-instance"
  machine_type = "e2-medium"
  zone         = "us-west1-a"
  tags         = ["http-server"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"
    access_config {} # Enables external IP
  }

  metadata_startup_script = <<-EOF
  #!/bin/bash
  apt update
  apt install -y nginx
  systemctl start nginx
  systemctl enable nginx
EOF
}

# Cloud SQL
resource "google_sql_database_instance" "main" {
  name             = "main-instance"
  database_version = "POSTGRES_15"
  region           = "us-west1"

  settings {
    # Second-generation instance tiers are based on the machine
    # type. See argument reference below.
    tier = "db-f1-micro"
  }
}

resource "google_storage_bucket" "project_bucket" {
  name                     = "jp-webcicd-bucket2"
  location                 = "US"
  force_destroy            = true
  public_access_prevention = "enforced"
}

resource "google_compute_health_check" "http_health_check" {
  name = "http-health-check"

  timeout_sec        = 5
  check_interval_sec = 5

  http_health_check {
    port         = 80
    request_path = "/"

  }
}

resource "google_compute_instance_group" "web-test" {
  name = "web-instance-group"
  zone = "us-west1-a"

  instances = [google_compute_instance.web.self_link]
  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_backend_service" "backend" {
  name          = "web-backend-service"
  protocol      = "HTTP"
  port_name     = "http"
  timeout_sec   = 10
  health_checks = [google_compute_health_check.http_health_check.id]
  backend {
    group = google_compute_instance_group.web-test.self_link
  }
}

resource "google_compute_url_map" "urlmap" {
  name            = "web-url-map"
  default_service = google_compute_backend_service.backend.self_link
}

resource "google_compute_target_http_proxy" "http" {
  name    = "web-proxy"
  url_map = google_compute_url_map.urlmap.self_link
}

resource "google_compute_global_forwarding_rule" "http" {
  name        = "web-forwarding-rule"
  ip_protocol = "TCP"
  port_range  = "80"
  target      = google_compute_target_http_proxy.http.self_link
}

resource "google_compute_firewall" "allow-http" {
  name          = "allow-http"
  network       = "default"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  target_tags = ["http-server"]
}
