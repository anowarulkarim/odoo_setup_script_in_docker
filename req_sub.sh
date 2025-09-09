#!/bin/bash
parent="odoo-on-docker"
conf="conf"
dockerfile="dockerfile"
pgadmin="pgadmin"
odoo_18_ee="/opt/odoo/custom-addons/odoo-18ee-custom-addons"
odoo_17_ee="/opt/odoo/custom-addons/odoo-17ee-custom-addons"
odoo_16_ee="/opt/odoo/custom-addons/odoo-16ee-custom-addons"
odoo_18_ce="/opt/odoo/custom-addons/odoo-18ce-custom-addons"
odoo_17_ce="/opt/odoo/custom-addons/odoo-17ce-custom-addons"
odoo_16_ce="/opt/odoo/custom-addons/odoo-16ce-custom-addons"

echo "input company name"
read comp_name
echo "input domain name"
read domain
echo "input odoo enterprise addons path"
read ent_path

create_files_and_folders(){
    
    mkdir -p "$parent"
    mkdir -p "$parent/$conf"
    mkdir -p "$parent/$dockerfile"
    mkdir -p "$parent/$pgadmin"

    mkdir -p "$odoo_18_ee"
    mkdir -p "$odoo_17_ee"
    mkdir -p "$odoo_16_ee"
    mkdir -p "$odoo_18_ce"
    mkdir -p "$odoo_17_ce"
    mkdir -p "$odoo_16_ce"

    touch "$parent/$conf/$comp_name.conf"
    touch "$parent/$pgadmin/.pgpass"
    touch "$parent/$pgadmin/.servers.json"
    touch "$parent/$dockerfile/odoo-admin-18ee.dockerfile"
    touch "$parent/start.txt"
    touch "$parent/stop.txt"
    touch "$parent/docker-compose.yml"
    touch "$parent/Caddyfile"
    touch "$parent/watch_docker_yml.sh"

}
write_in_files(){
cat <<EOF > "$parent/docker-compose.yml"
services:
  db:
    image: postgres:latest
    container_name: postgres-container
    environment:
      POSTGRES_USER: shamim
      POSTGRES_PASSWORD: shamim
    volumes:
      - odoo_db_data:/var/lib/postgresql/data
    networks:
      - odoo-net

  # Container name must same as service name and conf file name
  odoo-admin-18ee:
    ports:
      - "8069:8069"
    build:
      context: ./dockerfile
      dockerfile: odoo-admin-18ee.dockerfile
    container_name: odoo-admin-18ee
    depends_on:
      - db
    environment:
      - HOST=db
      - USER=shamim
      - PASSWORD=shamim
    volumes:
      - /opt/odoo/custom-addons/odoo-18ee-custom-addons:/mnt/extra-addons
      - $ent_path:/mnt/odoo-18-ee
      - ./conf/$comp_name.conf:/etc/odoo/odoo.conf
      - /opt/odoo-on-docker:/opt/odoo-on-docker/
    command: >
      odoo -d $comp_name-odoo-db -i website,request_subdomain,change_admin_credentials
    networks:
      - odoo-net


  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: pgadmin4
    depends_on:
      - db
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@admin.com
      PGADMIN_DEFAULT_PASSWORD: admin
    ports:
      - "5050:80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
      - ./pgadmin/servers.json:/pgadmin4/servers.json
      - ./pgadmin/pgpass:/pgpass
    restart: always
    networks:
      - odoo-net

  caddy:
    image: caddy:latest
    container_name: caddy-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - odoo-admin-18ee
      - pgadmin
    restart: always
    networks:
      - odoo-net

networks:
  odoo-net:
    name: odoo-net
    driver: bridge

volumes:
  odoo_db_data:
  pgadmin_data:
  caddy_data:
  caddy_config:

EOF
cat <<EOF > "$parent/$pgadmin/.pgpass"
db:5432:mydatabase:shamim:shamim
EOF
cat <<EOF > "$parent/$pgadmin/.servers.json"
{
  "Servers": {
    "1": {
      "Name": "MyPostgresServer",
      "Group": "Servers",
      "Host": "db",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "shamim",
      "SSLMode": "prefer",
      "PassFile": "/pgpass"
    }
  }
}
EOF
cat <<EOF > "$parent/$conf/$comp_name.conf"
[options]
admin_passwd = admin-12321
db_port = 5432
db_user = shamim
db_password = shamim
addons_path = /mnt/odoo-18-ee,/mnt/extra-addons
db_filter = ^admin-db
EOF
cat <<EOF > "$parent/$dockerfile/odoo-admin-18ee.dockerfile"
FROM odoo:18
USER root

# Switch to a different mirror
RUN sed -i 's|http://archive.ubuntu.com/ubuntu|http://us.archive.ubuntu.com/ubuntu|' /etc/apt/sources.list

# Install pip (and any tools you want like nano)
RUN apt-get update && apt-get install -y \
    python3-pip \
    nano \
    && rm -rf /var/lib/apt/lists/*


# Install required Python packages with override
RUN pip install --break-system-packages \
    --ignore-installed \
    pydantic==2.10.6 \
    pydantic-core==2.27.2 \
    email_validator==2.2.0 \
    phonenumbers==9.0.12
EOF
cat <<EOF > "$parent/Caddyfile"
$domain {
    reverse_proxy odoo-admin-18ee:8069
    encode gzip
}
EOF
cat <<'EOF' > "$parent/watch_docker_yml.sh"
#!/bin/bash

WATCH_DIR="/opt/odoo-on-docker"
STOP_FILE="$WATCH_DIR/stop.txt"
START_FILE="$WATCH_DIR/start.txt"
CADDY_FILE="$WATCH_DIR/Caddyfile"
INSTALL_FILE="$WATCH_DIR/install.txt"

echo "Watching $WATCH_DIR for .yml file changes and $STOP_FILE/$START_FILE/$INSTALL_FILE for new lines..."

# Ensure the files exist
touch "$STOP_FILE"
touch "$START_FILE"
touch "$CADDY_FILE"
touch "$INSTALL_FILE"

LAST_STOP_LINE_NUM=$(wc -l < "$STOP_FILE")
LAST_START_LINE_NUM=$(wc -l < "$START_FILE")
LAST_INSTALL_LINE_NUM=$(wc -l < "$INSTALL_FILE")

inotifywait -m -e create -e delete -e modify --format '%e %w%f' "$WATCH_DIR" | while read -r EVENT FULLPATH; do
    FILENAME=$(basename "$FULLPATH")

    # --- Handle .yml file created ---
    if [[ "$EVENT" == *CREATE* && "$FILENAME" == *.yml ]]; then
        echo "New YAML file detected: $FILENAME"
        docker-compose -f "$FULLPATH" up -d
    fi

    # --- Handle .yml file deleted ---
    if [[ "$EVENT" == *DELETE* && "$FILENAME" == *.yml ]]; then
        echo "YAML file deleted: $FILENAME"
        docker-compose -f "$FULLPATH" down
    fi

    # --- Handle stop.txt modification ---
    if [[ "$FULLPATH" == "$STOP_FILE" && "$EVENT" == *MODIFY* ]]; then
        CURRENT_LINE_NUM=$(wc -l < "$STOP_FILE")
        if (( CURRENT_LINE_NUM > LAST_STOP_LINE_NUM )); then
            echo "New line(s) added to stop.txt:"
            sed -n "$((LAST_STOP_LINE_NUM + 1)),$((CURRENT_LINE_NUM))p" "$STOP_FILE" | while read -r LINE; do
                if [[ -n "$LINE" ]]; then
                    echo "Stopping $LINE via docker-compose..."
                    docker-compose -f "$WATCH_DIR/$LINE-compose.yml" stop
                fi
            done
            LAST_STOP_LINE_NUM=$CURRENT_LINE_NUM
        fi
    fi

    # --- Handle start.txt modification ---
    if [[ "$FULLPATH" == "$START_FILE" && "$EVENT" == *MODIFY* ]]; then
        CURRENT_LINE_NUM=$(wc -l < "$START_FILE")
        if (( CURRENT_LINE_NUM > LAST_START_LINE_NUM )); then
            echo "New line(s) added to start.txt:"
            sed -n "$((LAST_START_LINE_NUM + 1)),$((CURRENT_LINE_NUM))p" "$START_FILE" | while read -r LINE; do
                if [[ -n "$LINE" ]]; then
                    echo "Starting $LINE via docker-compose..."
                    docker-compose -f "$WATCH_DIR/$LINE-compose.yml" start
                fi
            done
            LAST_START_LINE_NUM=$CURRENT_LINE_NUM
        fi
    fi

    # --- Handle install.txt modification ---
    if [[ "$FULLPATH" == "$INSTALL_FILE" && "$EVENT" == *MODIFY* ]]; then
        CURRENT_LINE_NUM=$(wc -l < "$INSTALL_FILE")
        if (( CURRENT_LINE_NUM > LAST_INSTALL_LINE_NUM )); then
            echo "New line(s) added to install.txt:"
            sed -n "$((LAST_INSTALL_LINE_NUM + 1)),$((CURRENT_LINE_NUM))p" "$INSTALL_FILE" | while read -r LINE; do
                if [[ -n "$LINE" ]]; then
                    SERVICE=$(echo "$LINE" | awk '{print $1}')
                    PACKAGE=$(echo "$LINE" | awk '{print $2}')
                    CONTAINER_NAME="${SERVICE}-container"

                    echo "Installing $PACKAGE in $CONTAINER_NAME..."
                    docker exec -i "$CONTAINER_NAME" pip install "$PACKAGE"
                fi
            done
            LAST_INSTALL_LINE_NUM=$CURRENT_LINE_NUM
        fi
    fi

    docker-compose restart caddy
done
EOF
chmod +x "$parent/watch_docker_yml.sh"
}
make_service_file(){
    dir="/etc/systemd/system"
    service_file="$dir/watchodoo.service"

    sudo bash -c "cat > $service_file" <<'EOF'
[Unit]
Description=Odoo yml file tracker to help start and stop the docker service
After=network.target

[Service]
Type=simple
ExecStart=/opt/odoo-on-docker/watch_docker_yml.sh
Restart=on-failure
User=root
WorkingDirectory=/opt/odoo-on-docker
StandardOutput=append:/var/log/watchodoo.log
StandardError=append:/var/log/watchodoo.log

[Install]
WantedBy=multi-user.target
EOF

}
clone_repo_in_18ee(){

    repo_url="https://github.com/anowarulkarim/request_subdomain.git"
    repo_url2="https://github.com/anowarulkarim/change_admin_credentials.git"
    repo_url3="https://github.com/anowarulkarim/package_install.git"
    target_dir="/opt/odoo/custom-addons/odoo-18ee-custom-addons"
    
    echo "📂 Cloning $repo_url into $target_dir ..."
    
    # Clone repo
    git clone "$repo_url" "$target_dir/$(basename "$repo_url" .git)" && echo "✅ Repo cloned successfully!" || echo "❌ Failed to clone repo."
    git clone "$repo_url2" "$target_dir/$(basename "$repo_url2" .git)" && echo "✅ Repo2 cloned successfully!" || echo "❌ Failed to clone repo."
    git clone "$repo_url3" "$target_dir/$(basename "$repo_url3" .git)" && echo "✅ Repo3 cloned successfully!" || echo "❌ Failed to clone repo."
    
}

sudo apt update
sudo apt install inotify-tools -y

create_files_and_folders
write_in_files
make_service_file
clone_repo_in_18ee

sudo systemctl daemon-reload
sudo systemctl start watchodoo.service