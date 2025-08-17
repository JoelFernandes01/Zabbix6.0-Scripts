#!/bin/bash

DATABASE_PASSWORD=${1:-Z4bb1x20205Tools}
ZABBIX_SERVER=192.168.0.100
HOSTNAME_PROXY="PRX-01"

echo "######################################################################"
echo "                        INSTALACAO DO ZABBIX PROXY 6                  "
echo "           SISTEMAS OPERACIONAIS RHEL-LIKE ROCKY/ALMA LINUX           "
echo "######################################################################"
echo "                          BASEADO EM SCRIPT:                            "
echo "           https://github.com/isaqueprofeta/zabbix-pipe2bash            "
echo "           Adaptado por: Euzébio Viana                                  "
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
firewall-cmd --add-port=161/tcp --permanent
firewall-cmd --add-port=162/udp --permanent
firewall-cmd --add-port=10050/tcp --permanent
firewall-cmd --reload

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
sudo -u postgres createdb -O zabbix -E Unicode -T template0 zabbix_proxy 2>/dev/null

echo "########################################################"
echo "ZABBIX PROXY"
echo "########################################################"

echo "########################################################"
echo "ZABBIX PROXY - Instalando Repositório"
echo "########################################################"
sudo rpm --import https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX
rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/9/x86_64/zabbix-release-latest-6.0.el9.noarch.rpm
dnf clean all

echo "########################################################"
echo "ZABBIX PROXY - Instalando Pacotes"
echo "########################################################"
dnf -y install zabbix-proxy-pgsql zabbix-sql-scripts

echo "########################################################"
echo "ZABBIX PROXY - Configurando schema do banco de dados"
echo "########################################################"
cat /usr/share/zabbix-sql-scripts/postgresql/proxy.sql | sudo -u zabbix PGPASSWORD=$DATABASE_PASSWORD psql -hlocalhost -Uzabbix zabbix_proxy 2>/dev/null

echo "########################################################"
echo "ZABBIX PROXY - Configurando o ZABBIX PROXY"
echo "########################################################"
sudo sed -i "s/# DBHost=localhost/DBHost=localhost/" /etc/zabbix/zabbix_proxy.conf
sudo sed -i '/^DBName=zabbix$/s|DBName=zabbix|DBName=zabbix_proxy|' /etc/zabbix/zabbix_proxy.conf
sudo sed -i "s/# DBPassword=/DBPassword=$DATABASE_PASSWORD/" /etc/zabbix/zabbix_proxy.conf
sudo sed -i "s/^Server=127.0.0.1$/Server=$ZABBIX_SERVER/" /etc/zabbix/zabbix_proxy.conf
sudo sed -i "s|Hostname=Zabbix proxy|Hostname=${HOSTNAME_PROXY}|" /etc/zabbix/zabbix_proxy.conf
sudo sed -i 's/^Timeout=4$/Timeout=30/' /etc/zabbix/zabbix_proxy.conf


echo "########################################################"
echo "ZABBIX PROXY - Inicializando serviço"
echo "########################################################"
systemctl enable --now zabbix-proxy

echo "#######################################"
echo "ZABBIX AGENT 2"
echo "#######################################"

echo "####################################################"
echo "ZABBIX AGENT 2 - Instalação para monitoração do PROXY"
echo "####################################################"
dnf -y install zabbix-agent2

echo "####################################################"
echo "ZABBIX AGENT 2 - Inicializando o Serviço"
echo "####################################################"
systemctl enable --now zabbix-agent2

echo "####################################################"
echo "ZABBIX PROXY - SNMPD"
echo "####################################################"
dnf -y install net-snmp net-snmp-utils
sudo systemctl enable --now snmpd