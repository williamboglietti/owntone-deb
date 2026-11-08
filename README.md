# OwnTone pour Ubuntu

Paquet Debian d'[OwnTone](https://github.com/owntone/owntone-server), serveur audio DAAP/AirPlay, pour Ubuntu 24.04 LTS amd64. Le binaire cible l'ensemble d'instructions x86-64 de base.

La CI vérifie également des constructions expérimentales pour Debian 13 et Ubuntu 24.04 et 26.04, en amd64 et arm64. Ces variantes sont destinées aux tests et ne sont pas publiées dans le dépôt APT. Le paquet Ubuntu 24.04 existant exige des bibliothèques propres à cette version.

## Installation

Télécharger le script, le lire, puis le lancer :

```bash
curl -fsSL -o install.sh https://mystorage.ovh/owntone/install.sh
less install.sh
sudo bash install.sh
```
