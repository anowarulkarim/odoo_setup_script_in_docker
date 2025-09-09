# 🚀 Odoo-on-Docker Automation Script

This project provides an **automation script** to set up and manage an Odoo environment with PostgreSQL, pgAdmin, and Caddy reverse proxy using **Docker & Docker Compose**.  

It also includes a **watcher service** that automatically starts, stops, and installs Python packages inside containers when you update specific files (`start.txt`, `stop.txt`, `install.txt`) in the `odoo-on-docker` directory.  

---

## 📂 Features
- 🔧 Auto-creates project structure (config, Dockerfiles, pgAdmin, addons paths).
- 🐘 PostgreSQL as the database.
- 📊 pgAdmin for DB management.
- 🟢 Odoo 18 Enterprise container with custom addons.
- 🌍 Caddy for reverse proxy with automatic config reload.
- 👀 Watcher service (`watch_docker_yml.sh`) to:
  - Start/Stop services by writing in `start.txt` / `stop.txt`.
  - Auto-install Python packages into running containers via `install.txt`.
  - Auto-apply `docker-compose` changes when `.yml` files are modified.
- 🔄 Systemd service to keep the watcher running in the background.
