<p align="center">
  <img src="Assets/AppIcon-1024.png" width="128" alt="Icône G502 Stage Mouse">
</p>

# G502 Stage Mouse pour macOS

Utilitaire macOS natif en barre des menus pour la Logitech G502 X LIGHTSPEED :
association directe des boutons en HID++, raccourcis macOS, défilement libre à
la molette, reprise après veille et contournement prudent d'un bug persistant de
survol.

**[Read in English](README.md)**

> [!IMPORTANT]
> C'est un projet personnel et communautaire, sans affiliation avec Logitech ou
> Apple. La configuration principalement testée est un Mac mini M4 Pro sous
> macOS 26 avec deux écrans externes.

## Pourquoi ce projet existe

Je ne suis pas développeur. Je suis monteur vidéo et je cherchais simplement à
rendre mon quotidien sur macOS plus confortable.

La G502 possède assez de boutons pour remplacer une bonne partie des gestes d'un
trackpad, mais macOS ne permet pas de les associer proprement à Mission Control,
App Exposé, Stage Manager, aux Spaces ou à la navigation arrière/avant. G HUB
étant peu fiable sur ma configuration, l'application communique directement
avec la souris grâce au protocole HID++ de Logitech.

Un autre problème a fait grandir le projet : depuis environ un an, le survol
pouvait cesser de se redessiner après un clic dans différentes applications. Le
curseur et les clics continuaient de fonctionner, mais les menus, contrôles
vidéo et boutons ne réagissaient plus visuellement. Un mouvement très rapide ou
un redémarrage de WindowServer rétablissait temporairement le comportement.

L'application a été construite progressivement avec du développement assisté
par IA, des tests réels pendant le travail et plusieurs audits consacrés à la
sécurité des événements et à la consommation de ressources. Le code est publié
pour que chacun puisse l'inspecter, l'adapter et l'améliorer.

## Fonctionnalités

- Association visuelle des boutons physiques G3 à G9.
- Mission Control, App Exposé, bureau, Spaces et changement d'application.
- Navigation arrière et avant native dans les applications compatibles.
- Communication HID++ directe sans dépendance à G HUB pendant l'utilisation.
- G502 X filaire, récepteur LIGHTSPEED et POWERPLAY.
- Batterie, état de charge et réglage du DPI de 100 à 25 600.
- Reconnexion automatique après veille, déverrouillage ou reconnexion USB.
- Stabilisateur de survol événementiel, sans boucle au repos.
- Défilement libre vertical et horizontal en maintenant la molette.
- Canal local de mise à jour vérifié par SHA-256 pour les builds de développement.

| Bouton | Contrôle physique | Action initiale |
| --- | --- | --- |
| G3 | Clic molette | Mission Control |
| G4 | Bouton latéral arrière | Retour arrière |
| G5 | Bouton latéral avant | Retour avant |
| G6 | DPI Shift amovible | App Exposé |
| G7 | DPI moins | Space précédent |
| G8 | DPI plus | Space suivant |
| G9 | Changement de profil | Afficher le bureau |

Toutes les associations restent modifiables dans la fenêtre visuelle.

## Stabilisateur de survol

Le réglage **Stabiliser le survol après les clics** est désactivé par défaut.
Quand le bug est visible, testez d'abord **Réveiller le survol maintenant**. Si
le survol revient, activez ensuite le mode automatique.

Après un clic gauche ou droit, la récupération automatique envoie trois
événements `mouseMoved` rapprochés à la position réelle du pointeur. Le curseur
ne bouge donc pas. Il n'existe aucun timer périodique : sans clic, le
stabilisateur ne travaille pas.

Les garde-fous sont vérifiés par
[`work/verify_hover_safety.sh`](work/verify_hover_safety.sh) :

- aucun clic simulé ;
- aucune activation, remontée ou prise de focus d'une fenêtre ;
- aucun déplacement forcé et aucune disparition du curseur ;
- aucune récupération pendant un bouton maintenu ou un glisser-déposer ;
- annulation si une frappe clavier a eu lieu dans les 400 ms précédentes ;
- arrêt des écouteurs pendant la veille, le verrouillage et la fermeture.

Ce mécanisme atténue un symptôme et ne corrige pas WindowServer. Un problème de
suspension de rendu très proche est documenté dans
[Mozilla Bug 2033230](https://bugzilla.mozilla.org/show_bug.cgi?id=2033230).

## Défilement libre à la molette

Activez **Défilement libre en maintenant la molette**, maintenez le clic molette
et déplacez la souris. Le mouvement devient un défilement fluide vertical et
horizontal. Les événements très fréquents sont regroupés sur 8 ms pour réduire
la pression sur WindowServer.

Sous 3 points de déplacement, le geste reste un clic court et l'action G3
s'exécute normalement. Si G3 est réglé sur **Aucune action**, un clic molette
natif est rejoué.

## Compatibilité

- macOS 13 ou version ultérieure ;
- Apple Silicon ;
- G502 X (USB uniquement, sans sans-fil) : `046D:C099`. Les changements de DPI
  ne s’appliquent qu’à la session en cours ; l’enregistrement du DPI dans la
  souris n’est pas disponible, et aucune batterie n’est affichée ;
- G502 X LIGHTSPEED reliée en USB : `046D:C098` ;
- récepteur LIGHTSPEED : `046D:C547` ;
- POWERPLAY : `046D:C53A`.

Les autres modèles Logitech ne sont pas garantis. Les contributions ajoutant
des appareils réellement testés sont les bienvenues.

## Installer une version

1. Téléchargez le ZIP depuis
   [Releases](https://github.com/ymergame/g502-stage-mouse-macos/releases).
2. Décompressez-le et placez **G502 Stage Mouse.app** dans `/Applications`.
3. Ouvrez l'application.
4. Autorisez **Accessibilité** et **Surveillance de l'entrée** dans Réglages
   Système → Confidentialité et sécurité.
5. Ouvrez l'icône de souris dans la barre des menus puis
   **Configurer visuellement…**.

Les builds communautaires actuels sont signés ad hoc et ne sont pas notarisés.
macOS peut afficher un avertissement au premier lancement et redemander les
autorisations après une mise à jour. Une signature Developer ID stable est
nécessaire pour supprimer cette limite.

Les raccourcis Mission Control et changement de Space doivent aussi être actifs
dans Réglages Système → Clavier → Raccourcis clavier → Mission Control.

## Compiler depuis les sources

Prérequis :

- Xcode Command Line Tools ;
- Rust et Cargo ;
- un Mac Apple Silicon pour la cible actuelle.

```bash
git clone https://github.com/ymergame/g502-stage-mouse-macos.git
cd g502-stage-mouse-macos/work/opengcontrol
cargo build --release
cd ../..
./build.command
```

L'archive et le manifeste sont créés dans `build/`. Pour alimenter explicitement
le canal de mise à jour local :

```bash
PUBLISH_LOCAL_UPDATE=1 ./build.command
```

Pour lancer seulement les tests du helper :

```bash
cd work/opengcontrol
cargo test --workspace --locked
```

## Autorisations et vie privée

Accessibilité sert à déclencher les raccourcis de navigation macOS. Surveillance
de l'entrée sert à recevoir les boutons supplémentaires. G502 Stage Mouse ne
contient ni télémétrie, ni compte, ni service cloud. La configuration et le canal
de mise à jour de développement restent locaux au Mac.

Ces autorisations étant puissantes, chacun peut inspecter le code et compiler
l'application. Les signalements de sécurité sont expliqués dans
[`SECURITY.md`](SECURITY.md).

## Organisation du dépôt

```text
Sources/G502StageMouse/   Application Swift/AppKit et interface
Assets/                   Icône et modèle 3D crédité séparément
work/opengcontrol/        Helper Rust HID++ intégré et extensions locales
work/verify_hover_safety.sh
                          Test de régression des événements
docs/                     Architecture et dépannage
build.command             Build, signature ad hoc, ZIP et manifeste
```

Voir [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) pour l'architecture.

## Limites connues

- Le contournement du survol est spécifique à macOS et ne résout pas tous les
  problèmes de rendu WindowServer.
- Les builds ne sont pas encore signés avec Developer ID ni notarisés.
- Le modèle 3D est sous CC BY-NC-SA 4.0 et non sous MIT ; une redistribution
  commerciale doit le remplacer. Voir [`ASSET-LICENSES.md`](ASSET-LICENSES.md).
- La compatibilité matérielle reste volontairement étroite, car la modification
  des boutons peut toucher le profil embarqué de la souris.

## Contribuer

Les rapports de bug, observations matérielles, corrections de documentation et
pull requests ciblées sont bienvenus. Indiquez le Mac exact, la version de
macOS, le type de connexion, le VID/PID du récepteur et les étapes de
reproduction.

Voir [`CONTRIBUTING.md`](CONTRIBUTING.md) et
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Crédits et licences

Le code original de l'application et sa documentation sont publiés sous
[licence MIT](LICENSE). Le helper `opengcontrol` conserve sa licence et les
crédits de ses contributeurs. Le modèle 3D utilise une licence Creative Commons
non commerciale séparée.

Consultez [`THIRD-PARTY-NOTICES.txt`](THIRD-PARTY-NOTICES.txt) et
[`ASSET-LICENSES.md`](ASSET-LICENSES.md) avant toute redistribution.
