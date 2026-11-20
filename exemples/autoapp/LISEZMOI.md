# Autoriser une app macOS

Application Lexis+ qui rend une application macOS (`.app`) et ses dépendances **lançables sans
blocage** et **autorisées à utiliser le réseau**. On choisit l'exécutable placé dans le paquet
(`Mon.app/Contents/MacOS/…`) ou le dossier `.app` lui-même ; l'application établit un diagnostic,
propose les opérations utiles et les applique **dans l'ordre** : Gatekeeper (quarantaine),
signature, puis réseau.

```
wdlexisrt principal.prg [chemin de l'exécutable ou du .app]
```

## 1. Diagnostic (bouton « Analyser »)

Aucune modification : chaque ligne indique ✓ (correct), ⚠ (à examiner) ou ✗ (bloquant) ;
choisir une ligne affiche l'explication.

| Contrôle | Commande |
| --- | --- |
| Info.plist valide, exécutable, identifiant, version | `plutil -lint`, `PlistBuddy -c 'Print :…'` |
| Quarantaine sur tout le paquet | `xattr -r -l` |
| Droits d'exécution de `Contents/MacOS/*` | `find … ! -perm -u+x` |
| Signature (ad hoc, Developer ID…, hardened runtime) | `codesign --verify --deep --strict --verbose=2`, `codesign -dv` |
| Évaluation Gatekeeper | `spctl --assess --type execute --verbose` |
| Déclaration « réseau local » | clé `NSLocalNetworkUsageDescription` |
| Coupe-feu applicatif | `socketfilterfw --getglobalstate`, `--getappblocked` |
| Dépendances hors du paquet (`/usr/local`, `/opt/homebrew`, dossier personnel…) : existence et quarantaine | `otool -L` sur chaque binaire Mach-O |
| Paquet modifiable sans droits d'administrateur | `test -w` |

## 2. Opérations (onglet « Autoriser (usage local) »)

Cochées d'après le diagnostic, exécutées dans cet ordre par un script shell (bouton
**Voir le script** pour le lire, **Enregistrer le script…** pour le garder) :

1. **Quarantaine** : `xattr -dr com.apple.quarantine Mon.app`, puis `xattr -d` sur chaque
   dépendance hors du paquet.
2. **Droits** : `chmod -R u+rwX Mon.app` et `chmod +x Mon.app/Contents/MacOS/*`.
3. **Réseau local** : `plutil -replace NSLocalNetworkUsageDescription` dans l'Info.plist
   (texte modifiable). Sans cette clé, macOS 15+ peut refuser l'accès au réseau local à une app
   lancée depuis le Finder.
4. **Signature ad hoc** : `codesign --force --deep --sign - Mon.app` (et, si cochée, chaque
   dépendance hors du paquet). Ajoutée d'office si le contenu du paquet change, sauf pour une app
   signée Developer ID (confirmation demandée : la signature ad hoc la remplacerait).
5. **Coupe-feu** : `socketfilterfw --add` et `--unblockapp` (connexions entrantes).
6. **Vérification** : `codesign --verify`, `spctl --assess`, quarantaine restante.

Quand le paquet ou une dépendance n'est pas modifiable par l'utilisateur, ou que le coupe-feu
est concerné, le script est lancé avec **une seule demande de mot de passe administrateur**
(`osascript … with administrator privileges`). Le journal garde le script et sa sortie, et un
nouveau diagnostic suit.

**À faire à la main** (boutons pour ouvrir les Réglages Système) :

- *Ouvrir quand même* : Confidentialité et sécurité, en bas (depuis macOS 15, le clic droit ›
  Ouvrir ne suffit plus) ;
- *Réseau local* (macOS 15+) : Confidentialité et sécurité › Réseau local, activer l'app, ou
  accepter la demande au premier lancement (bouton **Lancer l'application**) ; cette autorisation
  ne se donne pas en ligne de commande ;
- pare-feu tiers (Little Snitch, LuLu, antivirus) : règle d'autorisation ;
- autres permissions (accès complet au disque, accessibilité, caméra…) : Confidentialité et
  sécurité ; pour un parc, profil MDM (PPPC).

**Volontairement absent** : `sudo spctl --master-disable`, qui désactive Gatekeeper pour tout le
système.

## 3. Distribution (onglet « Distribuer (Developer ID) »)

Pour **votre** app destinée à d'autres Mac (compte développeur Apple et outils Xcode) :

1. **Signature Developer ID** : identité lue dans le trousseau (`security find-identity -v -p
   codesigning`), droits (*entitlements*) au choix — `network.client` / `network.server` (app
   sandboxée), `cs.disable-library-validation` (dylibs non signées par vous), `app-sandbox`.
   Signature de l'intérieur vers l'extérieur (bibliothèques, cadres, assistants, puis le paquet)
   avec `--options runtime --timestamp`, puis vérification.
2. **Notarisation et agrafage** : `ditto -c -k --keepParent`, `xcrun notarytool submit …
   --keychain-profile … --wait`, `xcrun stapler staple`, puis `spctl --assess`. Le profil du
   trousseau se crée une fois (bouton **Créer le profil**, qui ouvre la commande
   `xcrun notarytool store-credentials` dans le Terminal : identifiant Apple, équipe, mot de
   passe pour application).

Ne pas faire l'opération 4 (ad hoc) après une signature Developer ID : elle la remplacerait.

## 4. Fichiers

| Fichier | Rôle |
| --- | --- |
| `principal.prg` | fenêtre, onglets, actions |
| `analyse.prg` | diagnostic |
| `operations.prg` | script des opérations, exécution (avec ou sans administrateur) |
| `distribution.prg` | signature Developer ID, droits, notarisation |
| `outils.prg` | commandes shell (protection des chemins), journal |

Hors macOS, l'application fonctionne en **simulation** : les commandes sont seulement écrites au
journal.

---

CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
