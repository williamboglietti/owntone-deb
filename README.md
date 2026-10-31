# owntone-deb

Paquet `.deb` d'[OwnTone](https://github.com/owntone/owntone-server) pour les postes Zorin 18
(Ubuntu 24.04, amd64), compilé en CI pour qu'**aucune compilation n'ait lieu sur les postes**.

Pourquoi : OwnTone n'est pas dans les dépôts Ubuntu 24.04, et le Toshiba (AMD E1-1200, sans SSE4
ni AVX, 2 cœurs) mettrait très longtemps à le compiler. Le rôle `workstation` d'`ansible-infra`
télécharge ce paquet et vérifie son sha256 avant de l'installer.

## Ce que fait la CI

1. Compile OwnTone dans `ubuntu:24.04` (image épinglée par condensat), avec
   `-march=x86-64 -mtune=generic`, sur la source officielle vérifiée par son sha256 (`versions.env`).
2. **Refuse le paquet** si un binaire contient des instructions AVX ou SSE4.1/4.2
   (`build/check-baseline.sh`). `tests/check-baseline-test.sh` prouve que ce contrôle refuse bien
   un binaire AVX2 et un binaire SSE4.1.
3. Installe le `.deb` sur un Ubuntu 24.04 neuf (`tests/install-test.sh`) : compte `owntone`,
   dossiers, unité systemd, bibliothèques résolues, réinstallation, purge.
4. Sur demande seulement (`workflow_dispatch`, `publish=true`) : publie le `.deb` et son `.sha256`
   dans une release `owntone-<version>-<révision>`.

Le paquet ne livre pas `/etc/owntone.conf` (posé par Ansible) ; un exemple est dans
`/usr/share/doc/owntone/owntone.conf.example`. Les dépendances d'exécution sont relevées sur les
binaires par `dpkg-shlibdeps`. Le compte `owntone` est créé par le `postinst`.

## En local

```bash
./build.sh   # Docker requis ; résultat dans dist/
```

Le condensat du `.deb` change à chaque build (horodatages) : **le sha256 à épingler dans Ansible
est celui de la release publiée**, pas celui d'un build local.

## Mettre à jour OwnTone

1. Dans `versions.env`, changer `OWNTONE_VERSION` et `OWNTONE_SHA256`
   (`gh api repos/owntone/owntone-server/releases/tags/<version> --jq '.assets[]|{name,digest}'`).
2. Remettre `DEB_REVISION=1` (ou l'incrémenter si seul le paquetage change).
3. Ouvrir une PR (la CI construit et teste), puis lancer le workflow avec `publish=true`.
4. Reporter l'URL et le sha256 de la release dans `workstation_owntone_deb_url` / `_sha256`
   d'`ansible-infra`.

## Exécuteur

`runs-on` vaut `ubuntu-24.04` ; la variable de dépôt `RUNNER` la remplace (par exemple par le
`ci-runner` auto-hébergé, à condition qu'il ait Docker).
