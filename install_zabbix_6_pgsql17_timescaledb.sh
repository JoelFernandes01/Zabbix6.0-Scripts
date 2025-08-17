#!/bin/bash

DATABASE_PASSWORD=${1:-Z4bb1x20205Tools}

echo "######################################################################"
echo "                        INSTALACAO DO ZABBIX                          "
echo "           SISTEMAS OPERACIONAIS RHEL-LIKE ROCKY/ALMA LINUX           "
echo "######################################################################"
echo "                          FONTE DO SCRIPT:                            "
echo "           https://github.com/isaqueprofeta/zabbix-pipe2bash          "
echo "           Update por: Euzébio Viana                                  "
echo "######################################################################"

echo "########################################################"
echo "SISTEMA OPERACIONAL"
echo "########################################################"

echo "########################################################"
echo "SISTEMA OPERACIONAL - Desabilitar selinux"
echo "########################################################"
sed -i "s/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config
setenforce 0

echo "########################################################"
echo "SISTEMA OPERACIONAL - Configurar o firewall"
echo "########################################################"
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --add-port=10051/tcp --permanent
firewall-cmd --add-port=162/udp --permanent
firewall-cmd --reload

echo "########################################################"
echo "SISTEMA OPERACIONAL - Instalando Linguagem"
echo "########################################################"
sudo dnf install -y glibc-langpack-en

echo "########################################################"
echo "BANCO DE DADOS"
echo "########################################################"

echo "########################################################"
echo "BANCO DE DADOS - Instalando Repositório"
echo "########################################################"
yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -y module disable postgresql

echo "########################################################"
echo "BANCO DE DADOS - Instalando Pacotes"
echo "########################################################"
dnf -y install postgresql17 postgresql17-server

echo "########################################################"
echo "BANCO DE DADOS - Configurações gerais"
echo "########################################################"
mkdir -p /etc/systemd/system/postgresql-17.service.d
touch /etc/systemd/system/postgresql-17.service.d/override.conf
echo "[Service]" >> /etc/systemd/system/postgresql-17.service.d/override.conf
echo "Environment=PGDATA=/data/zabbixdb/" >> /etc/systemd/system/postgresql-17.service.d/override.conf
systemctl daemon-reload

mkdir -p /data/zabbixdb
chown postgres:postgres /data/zabbixdb

/usr/pgsql-17/bin/postgresql-17-setup initdb
sed -i "s/ident/md5/g" /data/zabbixdb/pg_hba.conf
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /data/zabbixdb/postgresql.conf

chown postgres:postgres /data/zabbixdb/*

echo "########################################################"
echo "BANCO DE DADOS - Inicializando serviço"
echo "########################################################"
systemctl enable --now postgresql-17

echo "########################################################"
echo "BANCO DE DADOS - Criação de usuário do Zabbix"
echo "########################################################"
sudo -u postgres psql -c "CREATE USER zabbix WITH ENCRYPTED PASSWORD '$DATABASE_PASSWORD'" 2>/dev/null
sudo -u postgres createdb -O zabbix -E Unicode -T template0 zabbix 2>/dev/null

echo "########################################################"
echo "ZABBIX SERVER"
echo "########################################################"

echo "########################################################"
echo "ZABBIX SERVER - Instalando Repositório"
echo "########################################################"
sudo rpm --import https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX
rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/9/x86_64/zabbix-release-latest-6.0.el9.noarch.rpm
dnf clean all

echo "########################################################"
echo "ZABBIX SERVER - Instalando Pacotes"
echo "########################################################"
dnf -y install zabbix-server-pgsql zabbix-sql-scripts

echo "########################################################"
echo "ZABBIX SERVER - Configurando schema do banco de dados"
echo "########################################################"
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u zabbix PGPASSWORD=$DATABASE_PASSWORD psql -hlocalhost -Uzabbix zabbix 2>/dev/null

echo "########################################################"
echo "ZABBIX SERVER - Configurando o Zabbix Server"
echo "########################################################"
sudo sed -i "s/# DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/# DBPassword=/DBPassword=$DATABASE_PASSWORD/" /etc/zabbix/zabbix_server.conf

echo "########################################################"
echo "ZABBIX SERVER - Inicializando serviço"
echo "########################################################"
systemctl enable --now zabbix-server

echo "########################################################"
echo "ZABBIX FRONTEND"
echo "########################################################"

echo "########################################################"
echo "ZABBIX FRONTEND - Instalando pacotes"
echo "########################################################"
echo "Instalação"
dnf -y install zabbix-web-pgsql zabbix-nginx-conf

echo "########################################################"
echo "ZABBIX FRONTEND - Configurando php"
echo "########################################################"
echo "php_value[date.timezone] = America/Sao_Paulo" >> /etc/php-fpm.d/zabbix.conf

echo "########################################################"
echo "ZABBIX FRONTEND - Configurando setup web"
echo "########################################################"
sudo tee /etc/zabbix/web/zabbix.conf.php <<EOL
<?php
    \$DB["TYPE"] = "POSTGRESQL";
    \$DB["SERVER"] = "localhost";
    \$DB["PORT"] = "5432";
    \$DB["DATABASE"] = "zabbix";
    \$DB["USER"] = "zabbix";
    \$DB["PASSWORD"] = "$DATABASE_PASSWORD";
    \$DB["SCHEMA"] = "";
    \$DB["ENCRYPTION"] = false;
    \$DB["KEY_FILE"] = "";
    \$DB["CERT_FILE"] = "";
    \$DB["CA_FILE"] = "";
    \$DB["VERIFY_HOST"] = false;
    \$DB["CIPHER_LIST"] = "";
    \$DB["VAULT_URL"] = "";
    \$DB["VAULT_DB_PATH"] = "";
    \$DB["VAULT_TOKEN"] = "";
    \$DB["DOUBLE_IEEE754"] = true;
    \$ZBX_SERVER = "localhost";
    \$ZBX_SERVER_PORT = "10051";
    \$ZBX_SERVER_NAME = "Zabbix Lab Tools";
    \$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOL

echo "###############################################################################"
echo "ZABBIX FRONTEND - Configurando nginx para o zabbix na raiz do site, na porta 80"
echo "###############################################################################"
sed -i "s/#        listen          8080;/        listen 80 default_server;\\n        listen [::]:80 default_server;/" /etc/nginx/conf.d/zabbix.conf
sed -i "s/#        server_name     example.com;/        server_name _;/" /etc/nginx/conf.d/zabbix.conf
sed -i "/.*listen.*/d" /etc/nginx/nginx.conf
sed -i "/.*server_name.*/d" /etc/nginx/nginx.conf

echo "#######################################"
echo "ZABBIX FRONTEND - Inicializando Serviço"
echo "#######################################"
systemctl enable --now php-fpm
sleep 5
systemctl enable --now nginx

echo "#######################################"
echo "ZABBIX AGENT 2"
echo "#######################################"

echo "####################################################"
echo "ZABBIX AGENT 2 - Instalação para monitoração do SERVER"
echo "####################################################"
dnf -y install zabbix-agent2

echo "####################################################"
echo "ZABBIX AGENT 2 - Inicializando o Serviço"
echo "####################################################"
systemctl enable --now zabbix-agent2

echo "####################################################"
echo "TIMESCALEDB"
echo "####################################################"

echo "####################################################"
echo "TIMESCALEDB - Instalando repositorios"
echo "####################################################"
sudo tee /etc/yum.repos.d/timescale_timescaledb.repo <<EOL
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/$(rpm -E %{rhel})/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOL

echo "####################################################"
echo "TIMESCALEDB - Instalando pacotes"
echo "####################################################"
dnf -y install timescaledb-2-postgresql-17-2.18.0-0.el9 timescaledb-2-loader-postgresql-17-2.18.0-0.el9.x86_64

echo "####################################################"
echo "TIMESCALEDB - Parando Zabbix Server"
echo "####################################################"
systemctl stop zabbix-server

echo "####################################################"
echo "TIMESCALEDB - Configurações do postgresql"
echo "####################################################"
echo "shared_preload_libraries = 'timescaledb'" >> /data/zabbixdb/postgresql.conf
sudo sed -i "s/max_connections = 20/max_connections = 50/" /data/zabbixdb/postgresql.conf
echo "timescaledb.license=timescale" >> /data/zabbixdb/postgresql.conf

echo "#####################################################"
echo "TIMESCALEDB - Inicializando e configurando postgresql"
echo "#####################################################"
sudo systemctl restart postgresql-17
sudo -u postgres timescaledb-tune --conf-path=/data/zabbixdb/postgresql.conf --quiet --yes --pg-config=/usr/pgsql-17/bin/pg_config
echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres psql zabbix 2>/dev/null
sudo systemctl restart postgresql-17
echo "########################################################"
echo "TIMESCALEDB - Migrando schema do zabbix para timescaledb"
echo "########################################################"
cat /usr/share/zabbix-sql-scripts/postgresql/timescaledb.sql | sudo -u zabbix psql zabbix

echo "########################################################"
echo "TIMESCALEDB - Inicializando sistema migrado"
echo "########################################################"
systemctl start zabbix-server
sleep 5
systemctl restart php-fpm
sleep 5
systemctl restart nginx

echo "########################################################"
echo "ZABBIX instalado com timescaledb e nginx"
echo "########################################################"

echo "########################################################"
echo "Acesse o IP deste servidor no browser com http"
echo "########################################################"
echo "http://$(hostname -i | awk '{print $2}')"