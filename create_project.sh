#!/bin/bash

# ------------------------------------------------------------------------------
# create_project.sh
# Description : Script pour créer un projet avec des environnements npm (frontend),
#               Conda (backend) et une base de données PostgreSQL, configurés à
#               partir d'un fichier .ini.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Vérification de l'existence du fichier de configuration
# ------------------------------------------------------------------------------
CONFIG_INSTALL_FILE="install_tools.ini"

if [ ! -f "$CONFIG_INSTALL_FILE" ]; then
    echo "Erreur : Le fichier de configuration $CONFIG_INSTALL_FILE n'existe pas."
    exit 1
fi

# ------------------------------------------------------------------------------
# Saisie du nom du projet
# Description : Demande à l'utilisateur de saisir le nom du projet et vérifie
#               qu'il n'est pas vide.
# ------------------------------------------------------------------------------
read -p "Entrez le nom du projet : " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
    echo "Erreur : Le nom du projet ne peut pas être vide."
    exit 1
fi

# ------------------------------------------------------------------------------
# Vérification de l'existence du fichier de configuration
# Description : Vérifie si le fichier de configuration project_config.ini existe.
#               Arrête le script si le fichier est absent.
# ------------------------------------------------------------------------------
CONFIG_FILE="$PROJECT_NAME.ini"

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
    local config_file=$1
    local section=$2
    local key=$3
    local value=$(crudini --get "$config_file" "$section" "$key" 2>/dev/null)

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
# Description : Récupère les valeurs nécessaires depuis le fichier .ini pour le
#               projet, PostgreSQL et les environnements.
# ------------------------------------------------------------------------------
PROJECTS_DIR=$(get_config_value "$CONFIG_INSTALL_FILE" General projects_dir)
MINICONDA_PATH=$(get_config_value "$CONFIG_INSTALL_FILE" Miniconda install_dir)

PYTHON_VERSION=$(get_config_value "$CONFIG_FILE" General python_version)
DB_PREFIX=$(get_config_value "$CONFIG_FILE" PostgreSQL database_prefix)
USER_PREFIX=$(get_config_value "$CONFIG_FILE" PostgreSQL user_prefix)
PG_PASSWORD=$(get_config_value "$CONFIG_FILE" PostgreSQL password_default)

# ------------------------------------------------------------------------------
# Vérification de l'existence de conda.sh
# Description : Vérifie que le fichier conda.sh existe dans le chemin de Miniconda
#               pour activer les fonctionnalités de Conda.
# ------------------------------------------------------------------------------
if [ -f "$MINICONDA_PATH/etc/profile.d/conda.sh" ]; then
    . "$MINICONDA_PATH/etc/profile.d/conda.sh"
else
    echo "Erreur : Impossible de trouver conda.sh dans $MINICONDA_PATH."
    exit 1
fi

# ------------------------------------------------------------------------------
# Définition des chemins et noms
# Description : Configure les chemins pour les répertoires du projet et les noms
#               pour la base de données et l'utilisateur PostgreSQL.
# ------------------------------------------------------------------------------
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"
FRONTEND_DIR="$PROJECT_DIR/frontend"
BACKEND_DIR="$PROJECT_DIR/backend"
DB_NAME="$DB_PREFIX$PROJECT_NAME"
PG_USER="$USER_PREFIX$PROJECT_NAME"

# ------------------------------------------------------------------------------
# Étape 1 : Création de la structure des répertoires
# Description : Crée les répertoires pour le frontend et le backend dans le chemin
#               spécifié pour le projet.
# ------------------------------------------------------------------------------
echo "Création de la structure du projet : $PROJECT_DIR"
mkdir -p "$FRONTEND_DIR" "$BACKEND_DIR"
cd "$PROJECT_DIR" || exit 1

# ------------------------------------------------------------------------------
# Étape 2 : Initialisation de l’environnement npm
# Description : Initialise un environnement npm dans le répertoire frontend et
#               installe le module Express.
# ------------------------------------------------------------------------------
echo "Initialisation de l’environnement npm dans $FRONTEND_DIR..."
cd "$FRONTEND_DIR" || exit 1
npm init -y
npm install express --save
echo "node_modules/" > .gitignore
echo "Environnement npm créé."
cd "$PROJECT_DIR" || exit 1

# ------------------------------------------------------------------------------
# Étape 3 : Création de l’environnement Conda
# Description : Crée un environnement Conda avec la version de Python spécifiée
#               dans le répertoire backend.
# ------------------------------------------------------------------------------
echo "Création de l’environnement Conda dans $BACKEND_DIR..."
cd "$BACKEND_DIR" || exit 1
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
conda create -p "./conda_$PROJECT_NAME" python="$PYTHON_VERSION" -y
echo "Environnement Conda conda_$PROJECT_NAME créé."
cd "$PROJECT_DIR" || exit 1

# ------------------------------------------------------------------------------
# Étape 4 : Configuration de PostgreSQL
# Description : Crée un utilisateur et une base de données PostgreSQL pour le projet.
# ------------------------------------------------------------------------------
echo "Création de l’utilisateur et de la base de données PostgreSQL..."
export PGPASSWORD="$PG_PASSWORD"
sudo -u postgres psql -c "CREATE ROLE $PG_USER WITH LOGIN PASSWORD '$PG_PASSWORD';"
sudo -u postgres psql -c "ALTER ROLE $PG_USER CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $PG_USER;"
unset PGPASSWORD
echo "Base de données $DB_NAME et utilisateur $PG_USER créés."

# ------------------------------------------------------------------------------
# Étape 5 : Initialisation du dépôt Git
# Description : Initialise un dépôt Git et configure un fichier .gitignore pour
#               exclure les fichiers inutiles.
# ------------------------------------------------------------------------------
echo "Initialisation du dépôt Git..."
git init
cat <<EOL > .gitignore
# Ignorer les fichiers Python/Conda
__pycache__/
*.pyc
backend/conda_$PROJECT_NAME/

# Ignorer les fichiers Node.js
frontend/node_modules/
EOL

# ------------------------------------------------------------------------------
# Étape 6 : Vérification finale des environnements
# Description : Vérifie le bon fonctionnement des environnements npm, Conda et
#               PostgreSQL.
# ------------------------------------------------------------------------------
echo "Vérification des environnements..."

# Vérification de l’environnement npm
cd "$FRONTEND_DIR" || exit 1
npm list express && echo "Environnement npm fonctionnel."
cd "$PROJECT_DIR" || exit 1

# Vérification de l’environnement Conda
conda activate "$BACKEND_DIR/conda_$PROJECT_NAME" && python --version && conda deactivate && echo "Environnement Conda fonctionnel."

# Vérification de la connexion PostgreSQL
export PGPASSWORD="$PG_PASSWORD"
psql -U "$PG_USER" -d "$DB_NAME" -h 127.0.0.1 -c "\q" && echo "Connexion PostgreSQL fonctionnelle."
unset PGPASSWORD

# ------------------------------------------------------------------------------
# Finalisation
# Description : Affiche un message confirmant la création réussie du projet.
# ------------------------------------------------------------------------------
echo "Projet $PROJECT_NAME créé avec succès dans $PROJECT_DIR !"