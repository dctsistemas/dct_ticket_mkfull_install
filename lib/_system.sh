#!/bin/bash
# Instalador Whaticket - Ubuntu 20.04 (focal) - Root only
set -euo pipefail

# =============== CONFIG ===============
NODE_DESIRED_MAJOR="${NODE_DESIRED_MAJOR:-18}"  # mude para 16, 18, 20 etc.
TIMEZONE="${TIMEZONE:-America/Sao_Paulo}"

# Variáveis esperadas no seu fluxo (já usadas no seu script original)
# instancia_add, link_git, empresa_delete, empresa_bloquear, empresa_desbloquear,
# empresa_dominio, alter_backend_url, alter_frontend_url, alter_backend_port, alter_frontend_port,
# backend_url, frontend_url, deploy_email, mysql_root_password
# ======================================

require_focal() {
  . /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "focal" ]]; then
    echo "Este instalador é apenas para Ubuntu 20.04 (focal). Detectado: ${VERSION_CODENAME:-desconhecido}"
    exit 1
  fi
}

print_banner() { :; } # mantenho seu placeholder

#######################################
# Usuário deploy (apenas dono do diretório do BOT)
#######################################
system_create_user() {
  print_banner
  printf "💻 Criando usuário 'deploy' (apenas p/ diretório do BOT)...\n\n"
  sleep 1
  if ! id -u deploy >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo deploy
    if [[ "${mysql_root_password:-}" != "" ]]; then
      echo "deploy:$(openssl passwd -6 "${mysql_root_password}")" | chpasswd
    fi
  fi
}

#######################################
# Clonar repositório (como deploy) — sem PM2
#######################################
system_git_clone() {
  print_banner
  printf "💻 Baixando código Whaticket...\n\n"
  sleep 1
  su - deploy -c "mkdir -p /home/deploy/${instancia_add}"
  su - deploy -c "git clone ${link_git} /home/deploy/${instancia_add}/"
  chown -R deploy:deploy "/home/deploy/${instancia_add}"
}

#######################################
# Update base + libs Puppeteer
#######################################
system_update() {
  print_banner
  printf "💻 Atualizando sistema e dependências base...\n\n"
  sleep 1
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y \
    ca-certificates curl wget gnupg lsb-release apt-transport-https \
    software-properties-common unzip git build-essential \
    fontconfig locales ufw fail2ban

  # Deps cromadas p/ Puppeteer/Chromium (válidas em 20.04)
  apt-get install -y \
    libxshmfence-dev libgbm-dev \
    libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 \
    libfontconfig1 libgcc1 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 \
    libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 \
    libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 \
    libxrandr2 libxrender1 libxss1 libxtst6 fonts-liberation libnss3 xdg-utils \
    libappindicator3-1

  timedatectl set-timezone "${TIMEZONE}" || true
}

#######################################
# Node.js LTS via NodeSource + verificação de versão
#######################################
system_node_install() {
  print_banner
  printf "💻 Instalando Node.js (LTS desejado: %s.x)...\n\n" "${NODE_DESIRED_MAJOR}"
  sleep 1

  # Remove repositórios NodeSource antigos (se existirem) para evitar conflito
  rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource*.list || true

  # Repo NodeSource para o major desejado
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_DESIRED_MAJOR}.x" | bash -
  apt-get install -y nodejs

  # npm atualizado
  npm i -g npm@latest

  # Verifica a versão instalada
  if ! command -v node >/dev/null 2>&1; then
    echo "Falha: 'node' não encontrado após instalação."
    exit 1
  fi

  NODEV="$(node -v | sed 's/^v//')"
  NODE_MAJOR_INSTALLED="${NODEV%%.*}"

  echo "Node instalado: v${NODEV} (major=${NODE_MAJOR_INSTALLED})"
  if [[ "${NODE_MAJOR_INSTALLED}" != "${NODE_DESIRED_MAJOR}" ]]; then
    echo "Falha: Node major instalado (${NODE_MAJOR_INSTALLED}) difere do desejado (${NODE_DESIRED_MAJOR})."
    echo "Verifique se a série ${NODE_DESIRED_MAJOR}.x está disponível no NodeSource para Ubuntu 20.04."
    exit 1
  fi
}

#######################################
# Docker Engine (focal) + Compose plugin
#######################################
system_docker_install() {
  print_banner
  printf "💻 Instalando Docker (focal)...\n\n"
  sleep 1
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

#######################################
# MySQL Server + criar DB utf8mb4
#######################################
system_mysql_install() {
  print_banner
  printf "💻 Instalando MySQL Server...\n\n"
  sleep 1
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y mysql-server
  systemctl enable --now mysql
}

system_mysql_create() {
  print_banner
  printf "💻 Criando banco MySQL (utf8mb4)...\n\n"
  sleep 1
  mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${mysql_root_password}';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS \`${instancia_add}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL
}

#######################################
# PM2 (rodando como root)
#######################################
system_pm2_install() {
  print_banner
  printf "💻 Instalando PM2 (root)...\n\n"
  sleep 1
  npm install -g pm2
  pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
  pm2 save || true
  systemctl enable pm2-root || true
}

#######################################
# snapd + certbot (snap) + link
#######################################
system_snapd_install() {
  print_banner
  printf "💻 Instalando snapd...\n\n"
  sleep 1
  apt-get install -y snapd
  snap install core
  snap refresh core
}

system_certbot_install() {
  print_banner
  printf "💻 Instalando Certbot (snap)...\n\n"
  sleep 1
  apt-get remove -y certbot || true
  snap install --classic certbot
  ln -sf /snap/bin/certbot /usr/bin/certbot
}

#######################################
# NGINX (instala, conf global, restart)
#######################################
system_nginx_install() {
  print_banner
  printf "💻 Instalando Nginx...\n\n"
  sleep 1
  apt-get install -y nginx
  rm -f /etc/nginx/sites-enabled/default || true
}

system_nginx_conf() {
  print_banner
  printf "💻 Configurando Nginx (conf global)...\n\n"
  sleep 1
  cat >/etc/nginx/conf.d/deploy.conf <<'NGX'
client_max_body_size 100M;
NGX
}

system_nginx_restart() {
  print_banner
  printf "💻 Reiniciando Nginx...\n\n"
  sleep 1
  systemctl reload nginx || service nginx restart
}

#######################################
# Certbot emitir (nginx)
#######################################
system_certbot_setup() {
  print_banner
  printf "💻 Emitindo certificados Let's Encrypt...\n\n"
  sleep 1
  backend_domain="${backend_url#https://}"
  frontend_domain="${frontend_url#https://}"
  certbot -m "$deploy_email" --nginx --agree-tos --non-interactive \
    -d "${backend_domain}" -d "${frontend_domain}"
}

#######################################
# Alterar domínio (env + nginx + certbot)
#######################################
configurar_dominio() {
  print_banner
  printf "💻 Alterando domínios...\n\n"
  sleep 1

  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-frontend || true
  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-backend || true
  rm -f /etc/nginx/sites-available/${empresa_dominio}-frontend || true
  rm -f /etc/nginx/sites-available/${empresa_dominio}-backend || true

  # .envs
  sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=https://${alter_backend_url}|" "/home/deploy/${empresa_dominio}/frontend/.env" || true
  sed -i "s|^BACKEND_URL=.*|BACKEND_URL=https://${alter_backend_url}|" "/home/deploy/${empresa_dominio}/backend/.env" || true
  sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=https://${alter_frontend_url}|" "/home/deploy/${empresa_dominio}/backend/.env" || true

  backend_hostname="${alter_backend_url#https://}"
  frontend_hostname="${alter_frontend_url#https://}"

  # backend
  cat >/etc/nginx/sites-available/${empresa_dominio}-backend <<EOF
server {
  listen 80;
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
EOF
  ln -sf "/etc/nginx/sites-available/${empresa_dominio}-backend" "/etc/nginx/sites-enabled/${empresa_dominio}-backend"

  # frontend
  cat >/etc/nginx/sites-available/${empresa_dominio}-frontend <<EOF
server {
  listen 80;
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
EOF
  ln -sf "/etc/nginx/sites-available/${empresa_dominio}-frontend" "/etc/nginx/sites-enabled/${empresa_dominio}-frontend"

  system_nginx_restart

  backend_domain="${backend_url#https://}"
  frontend_domain="${frontend_url#https://}"
  certbot -m "$deploy_email" --nginx --agree-tos --non-interactive \
    -d "${backend_domain}" -d "${frontend_domain}"

  printf "✅ Domínios atualizados e certificados emitidos.\n\n"
}

#######################################
# Bloquear / Desbloquear (PM2 root)
#######################################
configurar_bloqueio() {
  print_banner
  printf "💻 Bloqueando backend...\n\n"
  pm2 stop "${empresa_bloquear}-backend" || true
  pm2 save || true
  printf "✅ Bloqueio concluído.\n"
}

configurar_desbloqueio() {
  print_banner
  printf "💻 Desbloqueando backend...\n\n"
  pm2 start "${empresa_desbloquear}-backend" || true
  pm2 save || true
  printf "✅ Desbloqueio concluído.\n"
}

#######################################
# Deletar tudo (sem Postgres)
#######################################
deletar_tudo() {
  print_banner
  printf "💻 Removendo Instância %s...\n\n" "${empresa_delete}"
  docker container rm "redis-${empresa_delete}" --force 2>/dev/null || true

  rm -f "/etc/nginx/sites-enabled/${empresa_delete}-frontend" || true
  rm -f "/etc/nginx/sites-enabled/${empresa_delete}-backend" || true
  rm -f "/etc/nginx/sites-available/${empresa_delete}-frontend" || true
  rm -f "/etc/nginx/sites-available/${empresa_delete}-backend" || true
  system_nginx_restart || true

  if command -v pm2 >/dev/null 2>&1; then
    pm2 delete "${empresa_delete}-frontend" "${empresa_delete}-backend" 2>/dev/null || true
    pm2 save || true
  fi

  rm -rf "/home/deploy/${empresa_delete}"

  print_banner
  printf "✅ Instância %s removida com sucesso.\n\n" "${empresa_delete}"
}

# ------------- Preflight e exemplo de uso -------------
require_focal
echo "OK: Ubuntu focal detectado."
# Daqui pra baixo chame as funções conforme seu fluxo original.
# Exemplo:
# system_update
# system_create_user
# system_git_clone
# system_node_install
# system_pm2_install
# system_mysql_install
# system_mysql_create
# system_nginx_install
# system_nginx_conf
# system_nginx_restart
# system_snapd_install
# system_certbot_install
# configurar_dominio   # quando for alterar domínios
