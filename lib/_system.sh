#!/bin/bash
set -euo pipefail

#######################################
# creates user (only to own bot folder)
#######################################
system_create_user() {
  print_banner
  printf "${WHITE} 💻 Criando usuário 'deploy' (apenas para diretório do BOT)...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  id -u deploy &>/dev/null || useradd -m -s /bin/bash -G sudo deploy
  # senha opcional (comente se não quiser)
  if [ -n "${mysql_root_password:-}" ]; then
    echo "deploy:$(openssl passwd -6 "${mysql_root_password}")" | chpasswd
  fi
EOF
  sleep 1
}

#######################################
# clones repositories using git
#######################################
system_git_clone() {
  print_banner
  printf "${WHITE} 💻 Baixando código Whaticket...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<EOF
  su - deploy -c "mkdir -p /home/deploy/${instancia_add}"
  su - deploy -c "git clone ${link_git} /home/deploy/${instancia_add}/"
  chown -R deploy:deploy /home/deploy/${instancia_add}
EOF
  sleep 1
}

#######################################
# updates system & base libs
#######################################
system_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando sistema e dependências...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  apt-get update -y
  apt-get install -y \
    ca-certificates curl gnupg lsb-release wget unzip fontconfig locales \
    libxshmfence-dev libgbm-dev gconf-service libasound2 libatk1.0-0 libc6 \
    libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 \
    libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 \
    libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 \
    libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 \
    libxi6 libxrandr2 libxrender1 libxss1 libxtst6 \
    fonts-liberation libappindicator1 libnss3 xdg-utils
EOF
  sleep 1
}

#######################################
# delete instance
#######################################
deletar_tudo() {
  print_banner
  printf "${WHITE} 💻 Removendo Instância ${empresa_delete}...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<EOF
  docker container rm redis-${empresa_delete} --force || true
  rm -f /etc/nginx/sites-enabled/${empresa_delete}-frontend
  rm -f /etc/nginx/sites-enabled/${empresa_delete}-backend
  rm -f /etc/nginx/sites-available/${empresa_delete}-frontend
  rm -f /etc/nginx/sites-available/${empresa_delete}-backend

  # Postgres (se estiver usando)
  if command -v psql >/dev/null 2>&1; then
    sudo -u postgres dropdb ${empresa_delete} 2>/dev/null || true
    sudo -u postgres dropuser ${empresa_delete} 2>/dev/null || true
  fi

  # PM2 como root
  if command -v pm2 >/dev/null 2>&1; then
    pm2 delete ${empresa_delete}-frontend ${empresa_delete}-backend 2>/dev/null || true
    pm2 save || true
  fi
EOF

  sudo su - root <<EOF
  rm -rf /home/deploy/${empresa_delete}
EOF

  print_banner
  printf "${WHITE} 💻 Instância ${empresa_delete} removida com sucesso.${GRAY_LIGHT}\n\n"
  sleep 1
}

#######################################
# bloquear
#######################################
configurar_bloqueio() {
  print_banner
  printf "${WHITE} 💻 Bloqueando Instância ${empresa_bloquear}...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<EOF
  pm2 stop ${empresa_bloquear}-backend || true
  pm2 save || true
EOF

  print_banner
  printf "${WHITE} ✅ Bloqueio concluído.${GRAY_LIGHT}\n\n"
  sleep 1
}

#######################################
# desbloquear
#######################################
configurar_desbloqueio() {
  print_banner
  printf "${WHITE} 💻 Desbloqueando Instância ${empresa_desbloquear}...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<EOF
  pm2 start ${empresa_desbloquear}-backend || true
  pm2 save || true
EOF

  print_banner
  printf "${WHITE} ✅ Desbloqueio concluído.${GRAY_LIGHT}\n\n"
  sleep 1
}

#######################################
# alterar domínio (nginx + .env + certbot)
#######################################
configurar_dominio() {
  print_banner
  printf "${WHITE} 💻 Alterando domínios...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<EOF
  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-{frontend,backend}
  rm -f /etc/nginx/sites-available/${empresa_dominio}-{frontend,backend}
EOF

  sudo su - root <<EOF
  sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=https://${alter_backend_url}|" /home/deploy/${empresa_dominio}/frontend/.env
  sed -i "s|^BACKEND_URL=.*|BACKEND_URL=https://${alter_backend_url}|" /home/deploy/${empresa_dominio}/backend/.env
  sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=https://${alter_frontend_url}|" /home/deploy/${empresa_dominio}/backend/.env
EOF

  backend_hostname="${alter_backend_url#https://}"
  frontend_hostname="${alter_frontend_url#https://}"

  # NGINX backend
  sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa_dominio}-backend <<NGX
server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${alter_backend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
NGX
ln -sf /etc/nginx/sites-available/${empresa_dominio}-backend /etc/nginx/sites-enabled/${empresa_dominio}-backend
EOF

  # NGINX frontend
  sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa_dominio}-frontend <<NGX
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${alter_frontend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
NGX
ln -sf /etc/nginx/sites-available/${empresa_dominio}-frontend /etc/nginx/sites-enabled/${empresa_dominio}-frontend
EOF

  sudo su - root <<'EOF'
  systemctl reload nginx || service nginx restart
EOF

  backend_domain="${alter_backend_url#https://}"
  frontend_domain="${alter_frontend_url#https://}"

  sudo su - root <<EOF
  certbot -m "$deploy_email" --nginx --agree-tos --non-interactive \
    -d "${backend_domain}" -d "${frontend_domain}"
EOF

  print_banner
  printf "${WHITE} ✅ Domínios atualizados e certificados emitidos.${GRAY_LIGHT}\n\n"
  sleep 1
}

#######################################
# Node.js (18.x LTS) + Postgres + timezone
#######################################
system_node_install() {
  print_banner
  printf "${WHITE} 💻 Instalando Node.js 18 LTS e Postgres...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  # NodeSource 18.x
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
  npm i -g npm@latest

  # PostgreSQL (PGDG)
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgres.gpg
  echo "deb [signed-by=/etc/apt/keyrings/postgres.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  apt-get update -y && apt-get install -y postgresql

  timedatectl set-timezone America/Sao_Paulo || true
EOF
  sleep 1
}

#######################################
# Docker (repo focal + keyring)
#######################################
system_docker_install() {
  print_banner
  printf "${WHITE} 💻 Instalando Docker (focal)...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
EOF
  sleep 1
}

#######################################
# Puppeteer deps (já cobertas em update)
#######################################
system_puppeteer_dependencies() {
  print_banner
  printf "${WHITE} 💻 Conferindo dependências do Puppeteer...${GRAY_LIGHT}\n\n"
  sleep 1
  # Já instalado em system_update
}

#######################################
# MySQL server
#######################################
system_mysql_install() {
  print_banner
  printf "${WHITE} 💻 Instalando MySQL Server...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  apt-get install -y mysql-server
  systemctl enable --now mysql
EOF
  sleep 1
}

#######################################
# MySQL create DB (utf8mb4)
#######################################
system_mysql_create() {
  print_banner
  printf "${WHITE} 💻 Criando banco MySQL utf8mb4...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<EOF
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \\\`${instancia_add}\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${mysql_root_password}';
FLUSH PRIVILEGES;
SQL
EOF
  sleep 1
}

#######################################
# PM2 (como root)
#######################################
system_pm2_install() {
  print_banner
  printf "${WHITE} 💻 Instalando PM2 (root)...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  npm install -g pm2
  pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
  pm2 save || true
  systemctl enable pm2-root || true
EOF
  sleep 1
}

#######################################
# snapd + certbot via snap
#######################################
system_snapd_install() {
  print_banner
  printf "${WHITE} 💻 Instalando snapd...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  apt-get install -y snapd
  snap install core
  snap refresh core
EOF
  sleep 1
}

system_certbot_install() {
  print_banner
  printf "${WHITE} 💻 Instalando certbot (snap)...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  apt-get remove -y certbot || true
  snap install --classic certbot
  ln -sf /snap/bin/certbot /usr/bin/certbot
EOF
  sleep 1
}

#######################################
# nginx (root)
#######################################
system_nginx_install() {
  print_banner
  printf "${WHITE} 💻 Instalando Nginx...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  apt-get install -y nginx
  rm -f /etc/nginx/sites-enabled/default
EOF
  sleep 1
}

system_nginx_restart() {
  print_banner
  printf "${WHITE} 💻 Reiniciando Nginx...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  systemctl reload nginx || service nginx restart
EOF
  sleep 1
}

system_nginx_conf() {
  print_banner
  printf "${WHITE} 💻 Configurando Nginx (conf global)...${GRAY_LIGHT}\n\n"
  sleep 1

  sudo su - root <<'EOF'
  cat > /etc/nginx/conf.d/deploy.conf <<'NGX'
client_max_body_size 100M;
NGX
EOF
  sleep 1
}

system_certbot_setup() {
  print_banner
  printf "${WHITE} 💻 Emitindo certificados (Nginx)...${GRAY_LIGHT}\n\n"
  sleep 1

  backend_domain="${backend_url#https://}"
  frontend_domain="${frontend_url#https://}"

  sudo su - root <<EOF
  certbot -m "$deploy_email" --nginx --agree-tos --non-interactive \
    -d "${backend_domain}" -d "${frontend_domain}"
EOF
  sleep 1
}
