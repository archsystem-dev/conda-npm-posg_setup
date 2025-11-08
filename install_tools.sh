#!/bin/bash

# ------------------------------------------------------------------------------
# install_tools.sh
# Description : Script d'installation et de configuration de Miniconda, npm et
#               PostgreSQL avec gestion des paramètres via un fichier .ini.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Vérification de l'existence du fichier de configuration
# ------------------------------------------------------------------------------
CONFIG_FILE="install_tools.ini"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Erreur : Le fichier de configuration $CONFIG_FILE n'existe pas."
    exit 1
fi

# ------------------------------------------------------------------------------
# Installation de crudini si nécessaire
# Description : Vérifie si l'outil crudini est installé, sinon procède à son
#               installation pour lire les fichiers .ini.
# ------------------------------------------------------------------------------
if ! command -v crudini &>/dev/null; then
    echo "Installation de crudini..."
    sudo apt update
    sudo apt install -y crudini
fi

# ------------------------------------------------------------------------------
# Fonction : get_config_value
# Description : Récupère une valeur spécifique dans le fichier .ini à l'aide de
#               crudini. Affiche le contenu du fichier en cas d'erreur.
# Arguments   : $1 - Section du fichier .ini
#               $2 - Clé à récupérer
# Retour      : Valeur associée à la clé ou message d'erreur
# ------------------------------------------------------------------------------
get_config_value() {
    local section=$1
    local key=$2
    local value=$(crudini --get "$CONFIG_FILE" "$section" "$key" 2>/dev/null)

    if [ -z "$value" ]; then
        echo "Erreur : La clé $key dans la section [$section] est vide ou non définie."
        cat "$CONFIG_FILE"
        exit 1
    fi

    value=$(echo "$value" | sed "s|\$USER|$USER|g")
    echo "$value"
}

# ------------------------------------------------------------------------------
# Lecture des paramètres de configuration
# Description : Récupère les valeurs nécessaires depuis le fichier .ini pour
#               PostgreSQL, Miniconda et npm.
# ------------------------------------------------------------------------------
echo "Lecture des valeurs de configuration..."
PROJECTS_DIR=$(get_config_value General projects_dir)
PG_USER=$(get_config_value PostgreSQL user)
PG_PASSWORD=$(get_config_value PostgreSQL password)
PG_DATABASE=$(get_config_value PostgreSQL database)
MINICONDA_DIR=$(get_config_value Miniconda install_dir)
CONDA_AUTO_ACTIVATE=$(get_config_value Miniconda auto_activate_base)
NPM_DIR=$(get_config_value npm install_dir)
NODE_VERSION=$(get_config_value npm node_version)

# ------------------------------------------------------------------------------
# Validation des paramètres PostgreSQL
# Description : Vérifie que les valeurs pour PostgreSQL ne sont pas vides.
# ------------------------------------------------------------------------------
if [ -z "$PG_USER" ] || [ -z "$PG_PASSWORD" ] || [ -z "$PG_DATABASE" ]; then
    echo "Erreur : Une ou plusieurs valeurs PostgreSQL (user, password, database) sont vides."
    exit 1
fi

# ------------------------------------------------------------------------------
# Étape 1 : Désinstallation des outils existants
# Description : Supprime les installations précédentes de PostgreSQL, Miniconda
#               et Node.js/npm pour garantir une installation propre.
# ------------------------------------------------------------------------------
echo "Désinstallation des outils existants..."

# Désinstallation de PostgreSQL
echo "Désinstallation de PostgreSQL..."
sudo systemctl stop postgresql 2>/dev/null
sudo apt purge -y postgresql*
sudo apt autoremove -y
sudo rm -rf /etc/postgresql /var/lib/postgresql /var/log/postgresql /var/run/postgresql

# Désinstallation de Miniconda
echo "Suppression de Miniconda..."
if [ -d "$MINICONDA_DIR" ]; then
    rm -rf "$MINICONDA_DIR"
fi

# Nettoyage des configurations Miniconda dans ~/.bashrc
if grep -q "conda initialize" ~/.bashrc; then
    echo "Suppression des configurations Miniconda dans ~/.bashrc..."
    sed -i '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' ~/.bashrc
fi

# Suppression du fichier ~/.condarc
if [ -f ~/.condarc ]; then
    echo "Suppression de ~/.condarc..."
    rm -f ~/.condarc
fi

# Désinstallation de Node.js et npm
echo "Désinstallation de Node.js et npm..."
sudo apt purge -y node* npm*
sudo apt autoremove -y
sudo rm -rf "$NPM_DIR" ~/.nvm /usr/local/bin/node /usr/local/bin/npm

# ------------------------------------------------------------------------------
# Étape 2 : Mise à jour du système
# Description : Met à jour les paquets du système pour garantir un environnement
#               à jour avant l'installation des outils.
# ------------------------------------------------------------------------------
echo "Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# ------------------------------------------------------------------------------
# Étape 3 : Configuration de l'utilisateur et du groupe PostgreSQL
# Description : Crée l'utilisateur et le groupe 'postgres' si nécessaire, et
#               configure les permissions des répertoires associés.
# ------------------------------------------------------------------------------
echo "Création de l'utilisateur et du groupe postgres..."
if ! id postgres &>/dev/null; then
    sudo adduser --system --group --no-create-home postgres
fi

echo "Configuration des permissions pour PostgreSQL..."
sudo mkdir -p /var/lib/postgresql /var/run/postgresql
sudo chown postgres:postgres /var/lib/postgresql /var/run/postgresql
sudo chmod 700 /var/lib/postgresql
sudo chmod 775 /var/run/postgresql
sudo chmod 755 /var/lib

# ------------------------------------------------------------------------------
# Étape 4 : Installation de PostgreSQL
# Description : Installe PostgreSQL, configure l'utilisateur et la base de données,
#               et ajuste les paramètres d'accès réseau.
# ------------------------------------------------------------------------------
echo "Installation de PostgreSQL..."
if ! sudo apt install -y postgresql postgresql-contrib; then
    echo "Erreur lors de l'installation de PostgreSQL."
    exit 1
fi

# Vérification de la version de PostgreSQL
PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -n 1)
if [ -z "$PG_VERSION" ]; then
    echo "Erreur : Aucune version de PostgreSQL trouvée dans /usr/lib/postgresql."
    exit 1
fi

sudo systemctl enable postgresql

# Configuration de l'utilisateur PostgreSQL
echo "Configuration de l'utilisateur PostgreSQL : $PG_USER"
sudo -u postgres psql -c "DROP ROLE IF EXISTS \"$PG_USER\";" 2>/dev/null
sudo -u postgres psql -c "DROP ROLE IF EXISTS \"Erreur : La clé user dans la section [PostgreSQL] est vide ou \";" 2>/dev/null

if ! sudo -u postgres psql -c "CREATE ROLE \"$PG_USER\" WITH LOGIN PASSWORD '$PG_PASSWORD';"; then
    echo "Erreur lors de la création de l'utilisateur PostgreSQL."
    echo "Journaux système :"
    sudo journalctl -u postgresql
    exit 1
fi

if ! sudo -u postgres psql -c "ALTER ROLE \"$PG_USER\" CREATEDB;"; then
    echo "Erreur lors bodile l'attribution du privilège CREATEDB."
    exit 1
fi

sudo -u postgres psql -c "CREATE DATABASE \"$PG_DATABASE\" OWNER \"$PG_USER\";"

# Configuration de l'accès réseau (localhost uniquement)
PG_CONF=$(find /etc/postgresql -name "pg_hba.conf" | head -n 1)
if [ -z "$PG_CONF" ]; then
    echo "Erreur : Fichier pg_hba.conf non trouvé."
    exit 1
fi
sudo bash -c "echo 'host all all 127.0.0.1/32 md5' >> $PG_CONF"

PG_MAIN_CONF=$(find /etc/postgresql -name "postgresql.conf" | head -n 1)
if [ -z "$PG_MAIN_CONF" ]; then
    echo "Erreur : Fichier postgresql.conf non trouvé."
    exit 1
fi
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" "$PG_MAIN_CONF"

sudo systemctl restart postgresql

# Attente du redémarrage du service
sleep 2
if ! sudo systemctl is-active --quiet postgresql; then
    echo "Erreur : Le service PostgreSQL n'est pas en cours d'exécution après le redémarrage."
    exit 1
fi

# Définition de la variable pour le mot de passe
export PGPASSWORD="$PG_PASSWORD"

# Vérification de la connexion PostgreSQL
echo "Vérification de PostgreSQL..."
if psql -U "$PG_USER" -d "$PG_DATABASE" -h 127.0.0.1 -c "\q" 2>/dev/null; then
    echo "Connexion PostgreSQL réussie."
else
    echo "Erreur : Échec de la connexion à PostgreSQL."
    exit 1
fi

# Nettoyage de la variable pour des raisons de sécurité
unset PGPASSWORD

# ------------------------------------------------------------------------------
# Étape 5 : Installation de Miniconda
# Description : Télécharge et installe Miniconda dans le répertoire spécifié,
#               configure l'activation automatique de l'environnement de base.
# ------------------------------------------------------------------------------
echo "Installation de Miniconda..."
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
bash miniconda.sh -b -p "$MINICONDA_DIR"
rm miniconda.sh
source "$MINICONDA_DIR/bin/activate"
conda config --set auto_activate_base $CONDA_AUTO_ACTIVATE

# Vérification de l'installation de Miniconda
echo "Vérification de Miniconda..."
if conda --version; then
    echo "Miniconda installé correctement."
else
    echo "Erreur : Échec de l'installation de Miniconda."
    exit 1
fi

# ------------------------------------------------------------------------------
# Étape 6 : Installation de Node.js et npm
# Description : Installe Node.js et npm, configure la version spécifiée et
#               ajuste les chemins pour npm global.
# ------------------------------------------------------------------------------
echo "Installation de Node.js et npm..."
sudo apt install -y nodejs npm
sudo npm install -g n
sudo n "$NODE_VERSION"

# Configuration de npm global
mkdir -p "$NPM_DIR"
npm config set prefix "$NPM_DIR"
echo "export PATH=$NPM_DIR/bin:\$PATH" >> ~/.bashrc
source ~/.bashrc

# Vérification de l'installation de npm
echo "Vérification de npm..."
if npm --version; then
    echo "npm installé correctement."
else
    echo "Erreur : Échec de l'installation de npm."
    exit 1
fi

# ------------------------------------------------------------------------------
# Étape 7 : Création du répertoire des projets
# Description : Crée le répertoire des projets spécifié dans le fichier .ini.
# ------------------------------------------------------------------------------
echo "Création du répertoire des projets : $PROJECTS_DIR"
mkdir -p "$PROJECTS_DIR"

# ------------------------------------------------------------------------------
# Vérification finale de Miniconda
# Description : Vérifie que Miniconda est correctement installé dans le répertoire
#               spécifié.
# ------------------------------------------------------------------------------
if [ ! -d "$MINICONDA_DIR" ]; then
    echo "Erreur : Miniconda n'est pas trouvé dans $MINICONDA_DIR. Veuillez vérifier le chemin."
    exit 1
fi

# ------------------------------------------------------------------------------
# Configuration du fichier .bashrc pour Miniconda
# Description : Ajoute les lignes nécessaires à l'initialisation de Miniconda dans
#               ~/.bashrc si elles ne sont pas déjà présentes.
# ------------------------------------------------------------------------------
BASHRC="$HOME/.bashrc"
CONDA_INIT="# Initialisation de Miniconda
export PATH=\"$MINICONDA_DIR/bin:\$PATH\"
. $MINICONDA_DIR/etc/profile.d/conda.sh"

if grep -q "Miniconda" "$BASHRC"; then
    echo "L'initialisation de Miniconda est déjà présente dans $BASHRC."
else
    echo "$CONDA_INIT" >> "$BASHRC"
    echo "Initialisation de Miniconda ajoutée à $BASHRC."
fi

# Rechargement du fichier .bashrc
echo "Rechargement du .bashrc..."
source "$BASHRC"

# Vérification de l'accessibilité de conda
if command -v conda >/dev/null 2>&1; then
    echo "Conda est maintenant configuré. Version : $(conda --version)"
else
    echo "Erreur : Conda n'est pas accessible. Vérifiez l'installation de Miniconda."
    exit 1
fi

# ------------------------------------------------------------------------------
# Finalisation
# Description : Affiche un message indiquant que l'installation s'est terminée
#               avec succès.
# ------------------------------------------------------------------------------
echo "Installation terminée avec succès !"