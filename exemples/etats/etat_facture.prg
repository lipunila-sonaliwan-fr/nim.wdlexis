&& État « facture » — généré par l'éditeur d'états de wdlexis+.
&& Régénéré à chaque modification dans l'éditeur : modifiez le dessin là-bas, pas ce fichier.
&&   r = rapport.debut("facture.pdf")
&&   r.ajoute("zone", {variable = valeur, ...})       zones de l'état : entete, suite, colonnes, ligne, total, pied
&&   r.fin()                                         écrit le PDF

fonction ETAT_FACTURE()
retourner [[
{
  "etat": "facture",
  "props": {},
  "zones": [
    {
      "name": "entete",
      "height": 48.0,
      "props": {},
      "items": [
        {
          "kind": "rectangle",
          "name": "logo",
          "x": 0.0,
          "y": 0.0,
          "w": 52.0,
          "h": 22.0,
          "props": {
            "fond": "#1E3A8A",
            "bordure": "",
            "rayon": "3"
          }
        },
        {
          "kind": "texte",
          "name": "societe",
          "x": 3.0,
          "y": 3.0,
          "w": 46.0,
          "h": 8.0,
          "props": {
            "texte": "{societe}",
            "taille": "14.0",
            "gras": "true",
            "couleur": "#FFFFFF"
          }
        },
        {
          "kind": "texte",
          "name": "adresse",
          "x": 3.0,
          "y": 11.0,
          "w": 46.0,
          "h": 10.0,
          "props": {
            "texte": "{adresse}",
            "taille": "7.5",
            "couleur": "#DBEAFE"
          }
        },
        {
          "kind": "texte",
          "name": "titre",
          "x": 95.0,
          "y": 0.0,
          "w": 85.0,
          "h": 9.0,
          "props": {
            "texte": "FACTURE n° {numero}",
            "taille": "16.0",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "date",
          "x": 95.0,
          "y": 9.0,
          "w": 85.0,
          "h": 6.0,
          "props": {
            "texte": "du {date}",
            "taille": "9.0",
            "alignement": "droite"
          }
        },
        {
          "kind": "rectangle",
          "name": "cadreclient",
          "x": 95.0,
          "y": 18.0,
          "w": 85.0,
          "h": 26.0,
          "props": {
            "bordure": "#94A3B8",
            "rayon": "2"
          }
        },
        {
          "kind": "texte",
          "name": "clientnom",
          "x": 99.0,
          "y": 20.0,
          "w": 78.0,
          "h": 7.0,
          "props": {
            "texte": "{client}",
            "taille": "11.0",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "clientadresse",
          "x": 99.0,
          "y": 27.0,
          "w": 78.0,
          "h": 15.0,
          "props": {
            "texte": "{client_adresse}",
            "taille": "9.0",
            "retour": "true"
          }
        }
      ]
    },
    {
      "name": "suite",
      "height": 21.0,
      "props": {},
      "items": [
        {
          "kind": "texte",
          "name": "titre",
          "x": 0.0,
          "y": 2.0,
          "w": 180.0,
          "h": 7.0,
          "props": {
            "texte": "Facture n° {numero} — {client} (suite)",
            "taille": "10.0",
            "gras": "true"
          }
        },
        {
          "kind": "rectangle",
          "name": "fond",
          "x": 0.0,
          "y": 12.0,
          "w": 180.0,
          "h": 8.0,
          "props": {
            "fond": "#E2E8F0",
            "bordure": ""
          }
        },
        {
          "kind": "texte",
          "name": "designation",
          "x": 2.0,
          "y": 13.5,
          "w": 98.0,
          "h": 5.0,
          "props": {
            "texte": "Désignation",
            "taille": "9.0",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "quantite",
          "x": 100.0,
          "y": 13.5,
          "w": 20.0,
          "h": 5.0,
          "props": {
            "texte": "Qté",
            "taille": "9.0",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "prix",
          "x": 120.0,
          "y": 13.5,
          "w": 30.0,
          "h": 5.0,
          "props": {
            "texte": "Prix unitaire",
            "taille": "9.0",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "total",
          "x": 150.0,
          "y": 13.5,
          "w": 28.0,
          "h": 5.0,
          "props": {
            "texte": "Total HT",
            "taille": "9.0",
            "gras": "true",
            "alignement": "droite"
          }
        }
      ]
    },
    {
      "name": "colonnes",
      "height": 8.0,
      "props": {
        "fond": "#E2E8F0"
      },
      "items": [
        {
          "kind": "texte",
          "name": "designation",
          "x": 2.0,
          "y": 1.5,
          "w": 98.0,
          "h": 5.0,
          "props": {
            "texte": "Désignation",
            "taille": "9.0",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "quantite",
          "x": 100.0,
          "y": 1.5,
          "w": 20.0,
          "h": 5.0,
          "props": {
            "texte": "Qté",
            "taille": "9.0",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "prix",
          "x": 120.0,
          "y": 1.5,
          "w": 30.0,
          "h": 5.0,
          "props": {
            "texte": "Prix unitaire",
            "taille": "9.0",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "total",
          "x": 150.0,
          "y": 1.5,
          "w": 28.0,
          "h": 5.0,
          "props": {
            "texte": "Total HT",
            "taille": "9.0",
            "gras": "true",
            "alignement": "droite"
          }
        }
      ]
    },
    {
      "name": "ligne",
      "height": 7.0,
      "props": {
        "extensible": "true"
      },
      "items": [
        {
          "kind": "texte",
          "name": "designation",
          "x": 2.0,
          "y": 1.0,
          "w": 98.0,
          "h": 5.0,
          "props": {
            "texte": "{designation}",
            "taille": "9.0"
          }
        },
        {
          "kind": "texte",
          "name": "quantite",
          "x": 100.0,
          "y": 1.0,
          "w": 20.0,
          "h": 5.0,
          "props": {
            "texte": "{quantite}",
            "taille": "9.0",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "prix",
          "x": 120.0,
          "y": 1.0,
          "w": 30.0,
          "h": 5.0,
          "props": {
            "texte": "{prix:2} €",
            "taille": "9.0",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "total",
          "x": 150.0,
          "y": 1.0,
          "w": 28.0,
          "h": 5.0,
          "props": {
            "texte": "{total:2} €",
            "taille": "9.0",
            "alignement": "droite"
          }
        },
        {
          "kind": "ligne",
          "name": "trait",
          "x": 0.0,
          "y": 6.8,
          "w": 180.0,
          "h": 0.0,
          "props": {
            "couleur": "#E2E8F0"
          }
        }
      ]
    },
    {
      "name": "total",
      "height": 26.0,
      "props": {},
      "items": [
        {
          "kind": "rectangle",
          "name": "cadre",
          "x": 110.0,
          "y": 3.0,
          "w": 70.0,
          "h": 21.0,
          "props": {
            "bordure": "#1E3A8A",
            "rayon": "2"
          }
        },
        {
          "kind": "texte",
          "name": "lht",
          "x": 113.0,
          "y": 5.0,
          "w": 35.0,
          "h": 5.0,
          "props": {
            "texte": "Total HT",
            "taille": "9.0"
          }
        },
        {
          "kind": "texte",
          "name": "ht",
          "x": 145.0,
          "y": 5.0,
          "w": 32.0,
          "h": 5.0,
          "props": {
            "texte": "{ht:2} €",
            "taille": "9.0",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "ltva",
          "x": 113.0,
          "y": 11.0,
          "w": 35.0,
          "h": 5.0,
          "props": {
            "texte": "TVA {taux} %",
            "taille": "9.0"
          }
        },
        {
          "kind": "texte",
          "name": "tva",
          "x": 145.0,
          "y": 11.0,
          "w": 32.0,
          "h": 5.0,
          "props": {
            "texte": "{tva:2} €",
            "taille": "9.0",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "lttc",
          "x": 113.0,
          "y": 17.0,
          "w": 35.0,
          "h": 6.0,
          "props": {
            "texte": "Total TTC",
            "taille": "11.0",
            "gras": "true"
          }
        },
        {
          "kind": "texte",
          "name": "ttc",
          "x": 140.0,
          "y": 17.0,
          "w": 37.0,
          "h": 6.0,
          "props": {
            "texte": "{ttc:2} €",
            "taille": "11.0",
            "gras": "true",
            "alignement": "droite"
          }
        },
        {
          "kind": "texte",
          "name": "mentions",
          "x": 0.0,
          "y": 5.0,
          "w": 100.0,
          "h": 18.0,
          "props": {
            "texte": "{mentions}",
            "taille": "8.0"
          }
        }
      ]
    },
    {
      "name": "pied",
      "height": 10.0,
      "props": {},
      "items": [
        {
          "kind": "ligne",
          "name": "trait",
          "x": 0.0,
          "y": 1.0,
          "w": 180.0,
          "h": 0.0,
          "props": {
            "couleur": "#94A3B8"
          }
        },
        {
          "kind": "texte",
          "name": "societe",
          "x": 0.0,
          "y": 3.0,
          "w": 120.0,
          "h": 5.0,
          "props": {
            "texte": "{societe} — SIRET {siret}",
            "taille": "7.5"
          }
        },
        {
          "kind": "texte",
          "name": "page",
          "x": 120.0,
          "y": 3.0,
          "w": 60.0,
          "h": 5.0,
          "props": {
            "texte": "Page {page} / {nombre de page}",
            "taille": "7.5",
            "alignement": "droite"
          }
        }
      ]
    }
  ]
}
]]
finfonction
