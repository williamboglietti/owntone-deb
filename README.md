# OwnTone pour Debian et Ubuntu

Construction de paquets Debian d'[OwnTone](https://github.com/owntone/owntone-server), serveur audio DAAP/AirPlay.

La CI construit et teste des paquets pour Ubuntu 24.04 (`noble`), Ubuntu 26.04 (`resolute`) et Debian 13 (`trixie`), en `amd64` et `arm64`. Les paquets `amd64` ciblent l'ensemble d'instructions x86-64 de base.

## Installation

La publication APT est en cours de préparation. Après sa mise en service, télécharger le script, le lire, puis le lancer :

```bash
curl -fsSL -o install.sh https://mystorage.ovh/owntone/install.sh
less install.sh
sudo bash install.sh
```

Le script choisira la suite et l'architecture, vérifiera l'empreinte de la clé publique Boglietti et configurera le dépôt `https://boglietti.ovh/apt` pour APT.

## Publication APT

La CI attribue une version unique à chaque construction pour éviter de remplacer un paquet déjà publié. Elle construit chaque paquet dans sa distribution cible, teste son installation, puis rassemble les six artefacts dans un dépôt signé avec une clé temporaire. Elle teste enfin l'installation de chaque variante avec APT sur des runners natifs. La publication reste désactivée tant que les secrets et la clé de production ne sont pas configurés.

Le dépôt comporte trois suites (`noble`, `resolute`, `trixie`), avec un index `main` par architecture. Les fichiers `InRelease` et `Release.gpg` sont signés : APT vérifie la signature puis les sommes de contrôle des index et des paquets. Les `.deb` ne sont pas signés individuellement.

La clé de production doit être indépendante de toute autre identité. Conserver la clé primaire hors de la CI et fournir une sous-clé de signature exportable à l'environnement de production protégé. La CI accepte une exportation de sous-clé privée avec la partie privée de la clé primaire absente. Ne jamais placer de clé privée dans le dépôt. L'empreinte primaire devra être renseignée dans l'installateur avant son déploiement ; les valeurs de production sont fournies hors de ce dépôt.
